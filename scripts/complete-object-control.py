"""Explicit, test-only full-object two-consumer control. Never print private data.

Unsupported containers are INCONCLUSIVE, not candidates for a second fetch or a
looser demuxer. The old selected-media triage and its constants are independent.
"""
import argparse
from contextlib import contextmanager
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import stat
import struct
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener
import uuid
import zlib

CAP = 64 * 1024 * 1024
PNG_CAP = 4 * 1024 * 1024
NAMESPACE = "complete-object-control"
PRIVATE_PREFIX = "selected-media-private-complete-object-"
BUNDLE = "com.wm0104.xinxingarden"
LOCATOR = "selected-media-private.json"
TARGETS = {5: "plain-05.png", 15: "plain-15.png", 25: "plain-25.png", 52: "plain-paused52.png"}
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
SHA = r"[0-9a-f]{64}"
HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://www.bilibili.com/",
           "Range": f"bytes=0-{CAP - 1}", "Accept-Encoding": "identity"}
REASONS = frozenset("""not_enabled opt_in_required private_root_rejected unsafe_path
metadata_unavailable metadata_limit metadata_schema locator_rejected redirect_limit
redirect_rejected credentials_rejected encoding_rejected http_rejected range_rejected
response_size_rejected mime_rejected incomplete_transfer network_deadline
mp4_unsupported mp4_structure mp4_budget mp4_external_reference mp4_sample_span
mp4_timeline mp4_source_precondition namespace_exists source_changed
source_unavailable manifest_rejected result_unavailable result_rejected
returned_pts_invalid software_tools_unavailable decode_metadata_unavailable
decode_unsupported exact_pts_unavailable png_rejected png_metadata_rejected
process_deadline process_output_limit process_failed process_group_unverified
simulator_unavailable container_unavailable container_rejected cleanup_unverified
capture_failed same_bytes_complete partial_first_buffer private_operation_failed
cancelled export_failed""".split())


class Inconclusive(Exception):
    pass


def require(condition, code):
    if not condition:
        raise Inconclusive(code if code in REASONS else "private_operation_failed")


def safe_path(path, root):
    path, root = Path(os.path.abspath(path)), Path(os.path.abspath(root))
    require(path != root and path.is_relative_to(root), "unsafe_path")
    for component in (path, *path.parents):
        require(not component.is_symlink(), "unsafe_path")
    return path


def unique_json(raw):
    def pairs(values):
        result = {}
        for key, value in values:
            require(key not in result, "metadata_schema")
            result[key] = value
        return result
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Inconclusive("metadata_schema")))
    except (ValueError, UnicodeError, RecursionError):
        raise Inconclusive("metadata_schema") from None


def bounded_json(path, root, limit):
    path = safe_path(path, root)
    require(path.is_file() and path.stat().st_nlink == 1 and path.stat().st_size <= limit, "metadata_unavailable")
    with path.open("rb") as stream:
        raw = stream.read(limit + 1)
    require(len(raw) <= limit, "metadata_limit")
    return unique_json(raw)


def approved_url(value):
    try:
        parsed = urlparse(value)
        host = parsed.hostname or ""
        return (isinstance(value, str) and len(value) <= 12000 and parsed.scheme == "https" and
                parsed.username is None and parsed.password is None and parsed.port in (None, 443) and
                not parsed.fragment and not any(ord(c) < 33 or ord(c) == 127 for c in value) and
                (host == "bilivideo.com" or host.endswith(".bilivideo.com") or
                 host == "upos-hz-mirrorakam.akamaized.net"))
    except (ValueError, TypeError, AttributeError):
        return False


def locator_url(row):
    require(isinstance(row, dict) and set(row) == {"schema", "generation", "launch", "identityNamespace", "url"}, "locator_rejected")
    require(type(row["schema"]) is int and row["schema"] == 1 and type(row["generation"]) is int and
            1 <= row["generation"] <= 999999 and isinstance(row["launch"], str) and
            re.fullmatch(UUID, row["launch"].lower()) is not None and
            row["identityNamespace"] == "same-item-render-launch-local" and approved_url(row["url"]), "locator_rejected")
    return row["url"]


class Redirects(HTTPRedirectHandler):
    def __init__(self, deadline):
        self.deadline, self.hops = deadline, 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.hops += 1
        require(self.hops <= 3 and time.monotonic() < self.deadline, "redirect_limit")
        require(approved_url(newurl), "redirect_rejected")
        require(not headers.get("Set-Cookie") and not headers.get("WWW-Authenticate"), "credentials_rejected")
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result is not None:
            result.timeout = min(5, max(0.001, self.deadline - time.monotonic()))
        return result


@contextmanager
def absolute_network_budget():
    # macOS CI: this also interrupts a blocked open/redirect/read at 35 seconds.
    available = hasattr(signal, "setitimer") and threading.current_thread() is threading.main_thread()
    previous = None
    if available:
        previous = signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(Inconclusive("network_deadline")))
        signal.setitimer(signal.ITIMER_REAL, 35)
    try:
        yield
    finally:
        if available:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)


def fetch(url, path, opener=None, clock=time.monotonic):
    require(approved_url(url), "locator_rejected")
    deadline = clock() + 35
    opener = opener or build_opener(ProxyHandler({}), Redirects(deadline))
    digest, count = hashlib.sha256(), 0
    with absolute_network_budget():
        with opener.open(Request(url, headers=HEADERS), timeout=5) as response:
            require(clock() < deadline, "network_deadline")
            require(approved_url(response.geturl()), "redirect_rejected")
            headers = response.headers
            # Ambiguous response framing is not evidence of one complete object.
            if hasattr(headers, "get_all"):
                for name in ("Content-Length", "Content-Range", "Content-Type", "Content-Encoding"):
                    require(len(headers.get_all(name, [])) <= 1, "range_rejected")
            require(not headers.get("Set-Cookie") and not headers.get("WWW-Authenticate"), "credentials_rejected")
            require(headers.get("Content-Encoding", "identity").lower() == "identity", "encoding_rejected")
            require(headers.get("Content-Type", "").split(";", 1)[0].strip().lower() in
                    {"video/mp4", "application/mp4"}, "mime_rejected")
            length = headers.get("Content-Length", "")
            require(re.fullmatch(r"[0-9]{1,10}", length) is not None and 0 < int(length) <= CAP, "response_size_rejected")
            length = int(length)
            status = response.status
            if status == 206:
                match = re.fullmatch(r"bytes 0-([0-9]{1,10})/([0-9]{1,10})", headers.get("Content-Range", ""))
                require(match is not None, "range_rejected")
                end, total = map(int, match.groups())
                require(0 < total <= CAP and end == total - 1 and length == total, "range_rejected")
            else:
                require(status == 200, "http_rejected")
                require(headers.get("Content-Range") is None, "range_rejected")
            # Caller created the namespace; exclusive creation is also a no-overwrite guard.
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            with os.fdopen(os.open(path, flags, 0o600), "wb") as output:
                while True:
                    require(clock() < deadline, "network_deadline")
                    # urllib's socket is additionally bounded; fake test transports need no socket.
                    sock = getattr(getattr(getattr(response, "fp", None), "raw", None), "_sock", None)
                    if sock is not None:
                        sock.settimeout(min(5, max(0.001, deadline - clock())))
                    chunk = response.read1(min(65536, CAP - count + 1))
                    require(clock() < deadline, "network_deadline")
                    if not chunk:
                        break
                    count += len(chunk)
                    require(count <= CAP and count <= length, "response_size_rejected")
                    output.write(chunk)
                    digest.update(chunk)
            require(count == length, "incomplete_transfer")
    return {"bytes": count, "sha256": digest.hexdigest()}


class MP4:
    """Small closed nonfragmented H264/AAC grammar; never a permissive MP4 probe."""
    def __init__(self, data):
        require(8 <= len(data) <= CAP, "mp4_structure")
        self.data, self.boxes, self.entries = data, 0, 0
        self.spans = []

    def spend(self, count):
        self.entries += count
        require(0 <= count <= 500000 and self.entries <= 1500000, "mp4_budget")

    def children(self, start, end, depth=0):
        require(depth <= 8, "mp4_budget")
        result = []
        while start < end:
            self.boxes += 1
            require(self.boxes <= 10000 and end - start >= 8, "mp4_budget")
            size, kind = struct.unpack_from(">I4s", self.data, start)
            header = 8
            if size == 1:
                require(end - start >= 16, "mp4_structure")
                size, header = struct.unpack_from(">Q", self.data, start + 8)[0], 16
            require(size >= header and size <= end - start, "mp4_structure")
            require(kind not in {b"uuid", b"moof", b"mvex", b"mfra", b"sidx", b"rmra", b"rdrf", b"tref", b"meta"}, "mp4_unsupported")
            result.append((kind, start + header, start + size))
            start += size
        require(start == end, "mp4_structure")
        return result

    def mapping(self, start, end, allowed, required, depth):
        result = {}
        for kind, first, last in self.children(start, end, depth):
            require(kind in allowed and kind not in result, "mp4_unsupported")
            result[kind] = (first, last)
        require(required <= result.keys(), "mp4_structure")
        return result

    def full(self, box, versions=(0,), flags=(0,)):
        first, last = box
        require(last - first >= 4, "mp4_structure")
        version, value = self.data[first], int.from_bytes(self.data[first + 1:first + 4], "big")
        require(version in versions and value in flags, "mp4_unsupported")
        return first + 4, last, version

    def timing(self, box, movie=False):
        first, last, version = self.full(box, (0, 1))
        require(last - first == ((96 if movie else 20) if version == 0 else (108 if movie else 32)), "mp4_structure")
        scale = struct.unpack_from(">I", self.data, first + (8 if version == 0 else 16))[0]
        duration = int.from_bytes(self.data[first + (12 if version == 0 else 20):first + (16 if version == 0 else 28)], "big")
        require(scale > 0 and 0 < duration < (1 << 63), "mp4_timeline")
        return scale, duration

    def table(self, box, width, versions=(0,)):
        first, last, version = self.full(box, versions)
        require(last - first >= 4, "mp4_structure")
        count = struct.unpack_from(">I", self.data, first)[0]
        self.spend(count)
        require(last - first == 4 + count * width, "mp4_structure")
        return first + 4, count, version

    def descriptors(self, first, last, allowed):
        result = {}
        while first < last:
            tag = self.data[first]; first += 1
            size = 0
            for i in range(4):
                require(first < last, "mp4_structure")
                value = self.data[first]; first += 1
                size = size * 128 + (value & 127)
                if not value & 128:
                    break
            else:
                raise Inconclusive("mp4_structure")
            require(tag in allowed and tag not in result and size <= last - first, "mp4_unsupported")
            result[tag] = (first, first + size)
            first += size
        return result

    def sample_description(self, box, kind):
        first, last, _ = self.full(box)
        require(last - first >= 4 and struct.unpack_from(">I", self.data, first)[0] == 1, "mp4_unsupported")
        entries = self.children(first + 4, last, 6)
        require(len(entries) == 1, "mp4_structure")
        codec, begin, end = entries[0]
        require(end - begin >= 8 and self.data[begin:begin + 6] == b"\0" * 6 and
                struct.unpack_from(">H", self.data, begin + 6)[0] == 1, "mp4_external_reference")
        if kind == b"vide":
            require(codec == b"avc1" and end - begin >= 78, "mp4_unsupported")
            require(struct.unpack_from(">HH", self.data, begin + 24) == (1280, 720), "mp4_source_precondition")
            children = self.mapping(begin + 78, end, {b"avcC", b"pasp", b"btrt", b"colr"}, {b"avcC"}, 7)
            pos, stop = children[b"avcC"]
            require(stop - pos >= 7 and self.data[pos] == 1, "mp4_structure")
            require(self.data[pos + 4] & 3 in (0, 1, 3), "mp4_unsupported")
            n = self.data[pos + 5] & 31; pos += 6
            require(0 < n <= 31, "mp4_structure")
            for group in range(2):
                for _ in range(n):
                    require(stop - pos >= 2, "mp4_structure")
                    size = struct.unpack_from(">H", self.data, pos)[0]; pos += 2
                    require(size > 0 and size <= stop - pos, "mp4_structure"); pos += size
                if group == 0:
                    require(pos < stop, "mp4_structure")
                    n = self.data[pos]; pos += 1
                    require(n > 0, "mp4_structure")
            # High-profile AVC extension is supported only in its fixed bounded form.
            if pos < stop:
                require(stop - pos >= 4 and self.data[children[b"avcC"][0] + 1] in (100, 110, 122, 144), "mp4_unsupported")
                n = self.data[pos + 3]; pos += 4
                for _ in range(n):
                    require(stop - pos >= 2, "mp4_structure")
                    size = struct.unpack_from(">H", self.data, pos)[0]; pos += 2
                    require(0 < size <= stop - pos, "mp4_structure"); pos += size
            require(pos == stop, "mp4_structure")
            for name in (b"pasp", b"btrt"):
                if name in children:
                    p, q = children[name]; require(q - p == (8 if name == b"pasp" else 12), "mp4_structure")
            if b"colr" in children:
                p, q = children[b"colr"]
                require((self.data[p:p + 4] == b"nclx" and q - p == 11) or
                        (self.data[p:p + 4] == b"nclc" and q - p == 10), "mp4_unsupported")
        else:
            require(codec == b"mp4a" and end - begin >= 28 and self.data[begin + 8:begin + 16] == b"\0" * 8, "mp4_unsupported")
            children = self.mapping(begin + 28, end, {b"esds", b"btrt"}, {b"esds"}, 7)
            p, q, _ = self.full(children[b"esds"])
            descriptors = self.descriptors(p, q, {3})
            require(set(descriptors) == {3}, "mp4_structure")
            p, q = descriptors[3]
            require(q - p >= 3 and self.data[p + 2] == 0, "mp4_external_reference")
            descriptors = self.descriptors(p + 3, q, {4, 6})
            require(set(descriptors) == {4, 6}, "mp4_structure")
            p, q = descriptors[6]; require(self.data[p:q] == b"\x02", "mp4_unsupported")
            p, q = descriptors[4]
            require(q - p >= 13 and self.data[p] == 0x40 and self.data[p + 1] >> 2 == 5, "mp4_unsupported")
            descriptors = self.descriptors(p + 13, q, {5})
            require(set(descriptors) == {5}, "mp4_structure")
            p, q = descriptors[5]; require(2 <= q - p <= 64, "mp4_unsupported")
            if b"btrt" in children:
                p, q = children[b"btrt"]; require(q - p == 12, "mp4_structure")

    def track(self, box, mdats):
        first, last = box
        row = self.mapping(first, last, {b"tkhd", b"mdia", b"edts"}, {b"tkhd", b"mdia"}, 2)
        p, q, version = self.full(row[b"tkhd"], (0, 1), (3, 7))
        require(q - p == (80 if version == 0 else 92), "mp4_structure")
        trackid = struct.unpack_from(">I", self.data, p + (8 if version == 0 else 16))[0]
        duration = int.from_bytes(self.data[p + (16 if version == 0 else 24):p + (20 if version == 0 else 32)], "big")
        matrix = p + (36 if version == 0 else 48)
        require(struct.unpack_from(">9I", self.data, matrix) == (65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824), "mp4_unsupported")
        require(trackid > 0 and duration > 0, "mp4_structure")
        if b"edts" in row:
            edits = self.mapping(*row[b"edts"], {b"elst"}, {b"elst"}, 3)
            pos, count, ver = self.table(edits[b"elst"], 12 if self.data[edits[b"elst"][0]] == 0 else 20, (0, 1))
            require(count == 1, "mp4_timeline")
            size = 4 if ver == 0 else 8
            segment = int.from_bytes(self.data[pos:pos + size], "big")
            media = int.from_bytes(self.data[pos + size:pos + size * 2], "big", signed=True)
            require(segment == duration and media == 0 and self.data[pos + size * 2:pos + size * 2 + 4] == b"\0\x01\0\0", "mp4_timeline")
        mdia = self.mapping(*row[b"mdia"], {b"mdhd", b"hdlr", b"minf"}, {b"mdhd", b"hdlr", b"minf"}, 3)
        scale, duration = self.timing(mdia[b"mdhd"])
        p, q, _ = self.full(mdia[b"hdlr"])
        require(q - p >= 20, "mp4_structure")
        kind = self.data[p + 4:p + 8]
        require(kind in {b"vide", b"soun"}, "mp4_unsupported")
        minf = self.mapping(*mdia[b"minf"], {b"vmhd", b"smhd", b"dinf", b"stbl"}, {b"dinf", b"stbl"}, 4)
        require((kind == b"vide" and b"vmhd" in minf and b"smhd" not in minf) or
                (kind == b"soun" and b"smhd" in minf and b"vmhd" not in minf), "mp4_structure")
        p, q, _ = self.full(minf[b"vmhd" if kind == b"vide" else b"smhd"], flags=(1,) if kind == b"vide" else (0,))
        require(q - p == (8 if kind == b"vide" else 4), "mp4_structure")
        dinf = self.mapping(*minf[b"dinf"], {b"dref"}, {b"dref"}, 5)
        p, q, _ = self.full(dinf[b"dref"])
        require(q - p >= 4 and struct.unpack_from(">I", self.data, p)[0] == 1, "mp4_external_reference")
        references = self.children(p + 4, q, 6)
        require(len(references) == 1 and references[0][0] == b"url ", "mp4_external_reference")
        p, q = references[0][1:]
        require(self.data[p:q] == b"\0\0\0\x01", "mp4_external_reference")
        tables = self.mapping(*minf[b"stbl"], {b"stsd", b"stts", b"ctts", b"stsc", b"stsz", b"stco", b"co64", b"stss", b"sdtp"},
                              {b"stsd", b"stts", b"stsc", b"stsz"}, 5)
        require((b"stco" in tables) != (b"co64" in tables), "mp4_structure")
        self.sample_description(tables[b"stsd"], kind)
        p, q, _ = self.full(tables[b"stsz"])
        require(q - p >= 8, "mp4_structure")
        fixed, count = struct.unpack_from(">II", self.data, p)
        self.spend(count)
        require(0 < count <= 500000 and (fixed == 0 or 0 < fixed <= CAP) and
                q - p == 8 + (count * 4 if fixed == 0 else 0), "mp4_structure")
        sizes = None if fixed else struct.unpack_from(f">{count}I", self.data, p + 8)
        require(sizes is None or all(0 < n <= CAP for n in sizes), "mp4_structure")
        p, n, _ = self.table(tables[b"stts"], 8)
        timed, ticks, decoding_runs = 0, 0, []
        for index in range(n):
            amount, delta = struct.unpack_from(">II", self.data, p + index * 8)
            require(amount > 0 and delta > 0, "mp4_timeline")
            timed += amount; ticks += amount * delta
            decoding_runs.append((amount, delta))
        require(timed == count and ticks == duration, "mp4_timeline")
        composition_runs = [(count, 0)]
        if b"ctts" in tables:
            p, n, ver = self.table(tables[b"ctts"], 8, (0, 1))
            total, composition_runs = 0, []
            for index in range(n):
                amount, offset = struct.unpack_from(">Ii" if ver == 1 else ">II", self.data, p + index * 8)
                require(amount > 0, "mp4_timeline"); total += amount
                composition_runs.append((amount, offset))
            require(total == count, "mp4_timeline")
        # A zero media edit is insufficient if composition timestamps themselves
        # start elsewhere. Join run tables without expanding an unbounded timeline.
        a = b = dts = 0
        left_a, delta = decoding_runs[0]
        left_b, offset = composition_runs[0]
        minimum = duration
        while a < len(decoding_runs) and b < len(composition_runs):
            amount = min(left_a, left_b)
            minimum = min(minimum, dts + offset)
            require(0 <= dts + offset and dts + (amount - 1) * delta + offset < duration, "mp4_timeline")
            dts += amount * delta
            left_a -= amount; left_b -= amount
            if left_a == 0:
                a += 1
                if a < len(decoding_runs): left_a, delta = decoding_runs[a]
            if left_b == 0:
                b += 1
                if b < len(composition_runs): left_b, offset = composition_runs[b]
        require(minimum == 0, "mp4_timeline")
        if b"stss" in tables:
            p, n, _ = self.table(tables[b"stss"], 4)
            indices = struct.unpack_from(f">{n}I", self.data, p)
            require(all(0 < value <= count and (i == 0 or value > indices[i - 1]) for i, value in enumerate(indices)), "mp4_structure")
        if b"sdtp" in tables:
            p, q, _ = self.full(tables[b"sdtp"]); require(q - p == count, "mp4_structure")
        wide = b"co64" in tables
        p, chunks, _ = self.table(tables[b"co64" if wide else b"stco"], 8 if wide else 4)
        require(0 < chunks <= 200000, "mp4_budget")
        offsets = struct.unpack_from(f">{chunks}{'Q' if wide else 'I'}", self.data, p)
        p, n, _ = self.table(tables[b"stsc"], 12)
        require(0 < n <= chunks, "mp4_structure")
        runs = [struct.unpack_from(">III", self.data, p + index * 12) for index in range(n)]
        require(runs[0][0] == 1 and all(0 < start <= chunks and amount > 0 and desc == 1 and
                (i == 0 or start > runs[i - 1][0]) for i, (start, amount, desc) in enumerate(runs)), "mp4_structure")
        sample, run = 0, 0
        for index, offset in enumerate(offsets, 1):
            if run + 1 < n and runs[run + 1][0] == index:
                run += 1
            amount = runs[run][1]
            require(amount <= count - sample, "mp4_sample_span")
            length = fixed * amount if fixed else sum(sizes[sample:sample + amount])
            end = offset + length
            require(length > 0 and any(begin <= offset < end <= stop for begin, stop in mdats), "mp4_sample_span")
            self.spans.append((offset, end)); sample += amount
        require(sample == count, "mp4_sample_span")
        return kind, trackid, Fraction(duration, scale)

    def validate(self):
        top = self.children(0, len(self.data))
        require(all(kind in {b"ftyp", b"moov", b"mdat", b"free", b"skip", b"wide"} for kind, _, _ in top), "mp4_unsupported")
        require(sum(kind == b"ftyp" for kind, _, _ in top) == 1 and sum(kind == b"moov" for kind, _, _ in top) == 1, "mp4_structure")
        ftyp = next((p, q) for k, p, q in top if k == b"ftyp")
        p, q = ftyp
        require(q - p >= 8 and (q - p) % 4 == 0 and self.data[p:p + 4] in {b"isom", b"iso2", b"mp41", b"mp42", b"avc1"}, "mp4_unsupported")
        mdats = [(p, q) for k, p, q in top if k == b"mdat"]
        require(bool(mdats) and len(mdats) <= 16, "mp4_structure")
        p, q = next((p, q) for k, p, q in top if k == b"moov")
        children = self.children(p, q, 1)
        require(all(k in {b"mvhd", b"trak"} for k, _, _ in children) and
                sum(k == b"mvhd" for k, _, _ in children) == 1, "mp4_unsupported")
        scale, duration = self.timing(next((p, q) for k, p, q in children if k == b"mvhd"), movie=True)
        require(Fraction(duration, scale) > 600, "mp4_source_precondition")
        tracks = [self.track((p, q), mdats) for k, p, q in children if k == b"trak"]
        require(len(tracks) == 2 and {k for k, _, _ in tracks} == {b"vide", b"soun"} and
                len({i for _, i, _ in tracks}) == 2 and next(d for k, _, d in tracks if k == b"vide") > 600, "mp4_source_precondition")
        spans = sorted(self.spans)
        require(all(spans[i - 1][1] <= spans[i][0] for i in range(1, len(spans))), "mp4_sample_span")
        return {"videoTracks": 1, "audioTracks": 1, "width": 1280, "height": 720,
                "selfContained": True, "identityTimeline": True}


def validate_mp4(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_nlink == 1 and path.stat().st_size <= CAP, "source_unavailable")
    return MP4(path.read_bytes()).validate()


def identity(path, root, expected=None):
    path = safe_path(path, root)
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and 0 < before.st_size <= CAP and
            (os.name == "nt" or stat.S_IMODE(before.st_mode) == 0o400), "source_unavailable")
    digest = hashlib.sha256()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as stream:
        require(os.fstat(stream.fileno()) == before, "source_changed")
        while chunk := stream.read(65536):
            digest.update(chunk)
    after = path.lstat()
    fields = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_mode, s.st_nlink)
    require(fields(before) == fields(after), "source_changed")
    result = (*fields(after), digest.hexdigest())
    require(expected is None or result == expected, "source_changed")
    return result


def file_claim(signature):
    return {"bytes": signature[2], "sha256": signature[-1]}


def manifest(row):
    require(isinstance(row, dict) and set(row) == {"schema", "nonce", "bytes", "sha256"} and
            type(row["schema"]) is int and row["schema"] == 1 and isinstance(row["nonce"], str) and
            re.fullmatch(UUID, row["nonce"]) is not None and type(row["bytes"]) is int and
            0 < row["bytes"] <= CAP and isinstance(row["sha256"], str) and re.fullmatch(SHA, row["sha256"]) is not None, "manifest_rejected")
    return row


def stop_group(child):
    if child is None:
        return
    if os.name == "posix":
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(child.pid, sig)
            except ProcessLookupError:
                break
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.killpg(child.pid, 0)
                except ProcessLookupError:
                    return
                time.sleep(0.05)
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            return
        raise Inconclusive("process_group_unverified")
    if child.poll() is None:
        child.kill()
    child.wait(timeout=5)


def private_process(command, private, stem, budget=35, output_cap=4 * 1024 * 1024, allow_failure=False):
    """Bounded pipe drains prevent a fast child from filling disk between polls."""
    out, err = private / (stem + ".stdout"), private / (stem + ".stderr")
    events = queue.Queue(maxsize=4)
    child = None
    threads = []
    stop = threading.Event()
    active = private / "host-active"
    with active.open("xb") as marker: marker.write(b"1")
    def drain(stream, index):
        try:
            while not stop.is_set():
                chunk = os.read(stream.fileno(), 65536)
                while not stop.is_set():
                    try:
                        events.put((index, chunk), timeout=0.1)
                        break
                    except queue.Full:
                        continue
                if not chunk:
                    return
        finally:
            stream.close()
    try:
        kwargs = {"start_new_session": True} if os.name == "posix" else {}
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 stdin=subprocess.DEVNULL, **kwargs)
        for index, stream in enumerate((child.stdout, child.stderr)):
            thread = threading.Thread(target=drain, args=(stream, index), daemon=True)
            thread.start(); threads.append(thread)
        deadline, counts, done = time.monotonic() + budget, [0, 0], set()
        with out.open("xb") as stdout, err.open("xb") as stderr:
            while len(done) < 2 or child.poll() is None:
                require(time.monotonic() < deadline, "process_deadline")
                try:
                    index, chunk = events.get(timeout=min(0.1, max(0.001, deadline - time.monotonic())))
                except queue.Empty:
                    continue
                if not chunk:
                    done.add(index); continue
                counts[index] += len(chunk)
                require(counts[index] <= (output_cap if index == 0 else 1024 * 1024), "process_output_limit")
                (stdout if index == 0 else stderr).write(chunk)
        require(allow_failure or (child.returncode == 0 and counts[1] == 0), "process_failed")
        return out, child.returncode
    finally:
        stop.set()
        try:
            stop_group(child)
            active.unlink()
        finally:
            for thread in threads:
                thread.join(timeout=1)


def capture_command(simulator, private):
    return ["xcodebuild", "test-without-building", "-project", "XinxinGarden.xcodeproj", "-scheme",
            "XinxinGardenCompleteObjectDiagnostics", "-destination", f"platform=iOS Simulator,id={simulator}",
            "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", "150", "-maximum-test-execution-time-allowance", "180",
            "-only-testing:GardenAppTests/NativePlaybackTests/testCompleteObjectSameBytesDecodedOutputControl",
            "-resultBundlePath", str(private / "CompleteObject.xcresult"), "CODE_SIGNING_ALLOWED=NO"]


def finite(value, low=0, high=1e12):
    return type(value) in (int, float) and math.isfinite(value) and low <= value <= high


def sanitize_result(row, expected):
    require(isinstance(row, dict) and row.get("schema") == 1 and
            row.get("scope") == "localCompleteObjectDecodedOutput" and row.get("nonce") == expected["nonce"] and
            row.get("fileBefore") == {k: expected[k] for k in ("bytes", "sha256")} and
            row.get("fileAfter") == {k: expected[k] for k in ("bytes", "sha256")} and
            row.get("sourceHashVerified") is True, "result_rejected")
    result = {"scope": "localCompleteObjectDecodedOutput", "frames": []}
    booleans = ("completed", "captureCompleted", "artifactsSucceeded", "sourceHashVerified", "exactPlainClasses",
                "sharedAssetObject", "controllerInWindow", "readyForDisplayAtSetup", "loaderReleased",
                "actualScreenCaptured", "productionPaused52BufferAvailable")
    for key in booleans:
        if key in row:
            require(type(row[key]) is bool, "result_rejected"); result[key] = row[key]
    for key in ("pngBytes", "rawBytes", "startedUptime", "endedUptime", "captureExitUptime", "exportStartedUptime",
                "exportEndedUptime", "playStartedUptime"):
        if row.get(key) is not None:
            require(finite(row[key]), "result_rejected"); result[key] = row[key]
    stages = {"load", "ready", "window", "playing", "capture", "capture-complete", "complete", "export-failed"}
    if row.get("stage") in stages:
        result["stage"] = row["stage"]
    frames = row.get("frames", [])
    require(isinstance(frames, list) and len(frames) <= 4, "result_rejected")
    seen = set()
    numeric = {"currentBeforeSeconds", "currentAfterSeconds", "requestedSeconds", "rateBefore", "rateAfter",
               "beforeUptime", "afterUptime", "copyStartedUptime", "copyEndedUptime", "exportStartedUptime",
               "exportEndedUptime", "width", "height", "sourceStride", "sourceAllocationBytes", "ownedStride",
               "rawBytes", "samples", "populatedColors", "largestBucket", "pngBytes", "pixelFormat", "controlBefore", "controlAfter"}
    for frame in frames:
        require(isinstance(frame, dict) and type(frame.get("targetSeconds")) in (int, float) and
                frame["targetSeconds"] in TARGETS and frame["targetSeconds"] not in seen, "result_rejected")
        target = int(frame["targetSeconds"]); seen.add(target)
        cleaned = {"targetSeconds": target}
        for key in numeric:
            if frame.get(key) is not None:
                require(finite(frame[key], -2 if key.startswith("rate") else 0), "result_rejected")
                cleaned[key] = frame[key]
        for key in ("paused", "readyForDisplay", "imageAttachmentsPreserved"):
            if key in frame:
                require(type(frame[key]) is bool, "result_rejected"); cleaned[key] = frame[key]
        if frame.get("state") in {"waiting", "first-buffer", "decoded-output-gates-passed"}:
            cleaned["state"] = frame["state"]
        if frame.get("exportState") in {"not-retained", "pending", "failed", "attached"}:
            cleaned["exportState"] = frame["exportState"]
        if "actualPTSValue" in frame:
            value, scale, flags, epoch = (frame.get(k) for k in ("actualPTSValue", "actualPTSTimescale", "actualPTSFlags", "actualPTSEpoch"))
            require(type(value) is int and -(1 << 63) <= value < (1 << 63) and type(scale) is int and
                    0 < scale < (1 << 31) and type(flags) is int and flags in (1, 3) and type(epoch) is int and epoch == 0 and
                    0 <= Fraction(value, scale) <= Fraction(107, 2), "returned_pts_invalid")
            cleaned.update(actualPTSValue=value, actualPTSTimescale=scale, actualPTSFlags=flags, actualPTSEpoch=epoch)
        result["frames"].append(cleaned)
    return result


def capture_gates(result):
    if not all(result.get(k) is True for k in ("completed", "captureCompleted", "artifactsSucceeded", "sourceHashVerified",
                                               "exactPlainClasses", "sharedAssetObject", "controllerInWindow")):
        return False
    frames = result["frames"]
    if [f["targetSeconds"] for f in frames] != [5, 15, 25, 52]:
        return False
    for frame in frames:
        target = frame["targetSeconds"]
        if frame.get("state") != "decoded-output-gates-passed" or frame.get("exportState") != "attached" or "actualPTSValue" not in frame:
            return False
        actual = Fraction(frame["actualPTSValue"], frame["actualPTSTimescale"])
        before, after, requested = (frame.get(k) for k in ("currentBeforeSeconds", "currentAfterSeconds", "requestedSeconds"))
        if not all(finite(v, target, target + 0.75) for v in (before, after)) or not finite(requested, 0, 54):
            return False
        rate, control = (0, 0) if target == 52 else (1.5, 2)
        if (abs(float(actual) - before) > 0.75 or abs(float(actual) - after) > 0.75 or abs(requested - before) > 0.75 or
                frame.get("rateBefore") != rate or frame.get("rateAfter") != rate or
                frame.get("controlBefore") != control or frame.get("controlAfter") != control or
                frame.get("paused") is not (target == 52) or frame.get("width") != 1280 or frame.get("height") != 720 or
                frame.get("imageAttachmentsPreserved") is not True or frame.get("samples", 0) <= 0 or
                frame.get("populatedColors", 0) < 16 or frame.get("largestBucket", 1e12) >= frame["samples"] * 9 // 10):
            return False
    return True


def validate_png(raw, strip_known_metadata=False):
    require(8 <= len(raw) <= PNG_CAP and raw[:8] == b"\x89PNG\r\n\x1a\n", "png_rejected")
    pos, seen, idat_ended = 8, [], False
    allowed = {b"IHDR", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"cHRM", b"sBIT", b"pHYs"}
    if strip_known_metadata:
        allowed |= {b"eXIf", b"iDOT"}
    while pos < len(raw):
        require(len(raw) - pos >= 12, "png_rejected")
        size, kind = struct.unpack_from(">I4s", raw, pos); pos += 8
        require(size <= len(raw) - pos - 4, "png_rejected")
        data = raw[pos:pos + size]; pos += size
        crc = struct.unpack_from(">I", raw, pos)[0]; pos += 4
        require(zlib.crc32(kind + data) & 0xffffffff == crc, "png_rejected")
        require(kind in allowed, "png_metadata_rejected")
        if kind == b"IHDR":
            require(not seen and size == 13 and struct.unpack_from(">II", data) == (1280, 720) and
                    data[8] == 8 and data[9] in (2, 6) and data[10:] == b"\0\0\0", "png_rejected")
        else:
            require(bool(seen) and seen[0] == b"IHDR", "png_rejected")
        if kind == b"IDAT":
            require(not idat_ended and size > 0, "png_rejected")
        elif b"IDAT" in seen:
            idat_ended = True
        if kind not in {b"IDAT"}:
            require(kind not in seen, "png_rejected")
        if kind not in {b"IHDR", b"IDAT", b"IEND", b"eXIf", b"iDOT"}:
            require(b"IDAT" not in seen, "png_rejected")
            lengths = {b"sRGB": 1, b"gAMA": 4, b"cHRM": 32, b"sBIT": 4 if raw[25] == 6 else 3, b"pHYs": 9}
            require(size == lengths[kind], "png_rejected")
            if kind == b"sRGB": require(data[0] <= 3, "png_rejected")
            if kind == b"pHYs": require(data[-1] <= 1, "png_rejected")
        seen.append(kind)
        if kind == b"IEND":
            require(size == 0 and b"IDAT" in seen and pos == len(raw), "png_rejected")
    require(bool(seen) and seen[-1] == b"IEND", "png_rejected")
    # Check image stream without rewriting its pixels or metadata. Limit expansion.
    compressed, pos = bytearray(), 8
    while pos < len(raw):
        size, kind = struct.unpack_from(">I4s", raw, pos)
        if kind == b"IDAT": compressed.extend(raw[pos + 8:pos + 8 + size])
        pos += size + 12
    channels = 4 if raw[25] == 6 else 3
    expected = 720 * (1 + 1280 * channels)
    try:
        inflater = zlib.decompressobj()
        pixels = inflater.decompress(compressed, expected + 1)
        require(len(pixels) == expected and inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail, "png_rejected")
        stride = 1 + 1280 * channels
        require(all(pixels[row * stride] <= 4 for row in range(720)), "png_rejected")
    except zlib.error:
        raise Inconclusive("png_rejected") from None
    return raw


def sanitize_png(raw):
    """Only remove the two independently observed Apple ancillary chunk types.

    All input CRC/structure/decoded-size checks precede publication. Copy complete
    encoded chunks verbatim: no orientation interpretation, pixel transform,
    recompression, replacement frame, or mutation of private/raw evidence.
    """
    validate_png(raw, strip_known_metadata=True)
    chunks, encoded_idat, published_idat = [raw[:8]], [], []
    pos = 8
    while pos < len(raw):
        size, kind = struct.unpack_from(">I4s", raw, pos)
        chunk = raw[pos:pos + size + 12]
        if kind == b"IDAT": encoded_idat.append(chunk)
        if kind not in {b"eXIf", b"iDOT"}:
            chunks.append(chunk)
            if kind == b"IDAT": published_idat.append(chunk)
        pos += size + 12
    cleaned = b"".join(chunks)
    validate_png(cleaned)
    require(encoded_idat == published_idat, "png_rejected")
    return cleaned, {"encodedSHA256": hashlib.sha256(raw).hexdigest(),
                     "publishedSHA256": hashlib.sha256(cleaned).hexdigest(),
                     "IDATBytesUnchanged": True, "metadataDisplayInterpretationApplied": False}


def png_file(path, root, with_proof=False):
    path = safe_path(path, root)
    require(path.is_file() and path.stat().st_nlink == 1 and path.stat().st_size <= PNG_CAP, "png_rejected")
    raw, proof = sanitize_png(path.read_bytes())
    return (raw, proof) if with_proof else raw


def decode(source, private, requested):
    probe, decoder = shutil.which("ffprobe"), shutil.which("ffmpeg")
    require(probe and decoder, "software_tools_unavailable")
    require(1 <= len(requested) <= 4, "returned_pts_invalid")
    entries = "stream=codec_name,width,height,time_base,start_pts:frame=pts,width,height"
    metadata, _ = private_process([probe, "-v", "error", "-err_detect", "explode", "-protocol_whitelist", "file",
                                 "-format_whitelist", "mov", "-f", "mov", "-select_streams", "v:0", "-read_intervals", "%+54",
                                 "-show_frames", "-show_streams", "-show_entries", entries, "-of", "json", str(source)], private, "probe")
    data = bounded_json(metadata, private, 4 * 1024 * 1024)
    streams, frames = data.get("streams"), data.get("frames")
    require(isinstance(streams, list) and len(streams) == 1 and isinstance(frames, list) and 0 < len(frames) <= 10000, "decode_metadata_unavailable")
    stream = streams[0]
    require(stream.get("codec_name") == "h264" and stream.get("width") == 1280 and stream.get("height") == 720 and
            str(stream.get("start_pts")) == "0" and re.fullmatch(r"[1-9][0-9]{0,9}/[1-9][0-9]{0,9}", stream.get("time_base", "")) is not None, "decode_unsupported")
    time_base = Fraction(stream["time_base"])
    timeline, previous = {}, None
    for index, frame in enumerate(frames):
        require(isinstance(frame, dict) and str(frame.get("pts", "")).lstrip("-").isdigit() and
                frame.get("width") == 1280 and frame.get("height") == 720, "decode_metadata_unavailable")
        ticks = int(frame["pts"])
        require(-(1 << 63) <= ticks < (1 << 63), "decode_metadata_unavailable")
        pts = ticks * time_base
        require(pts >= 0 and (previous is None or pts > previous), "decode_unsupported")
        previous = pts
        if pts < 54: timeline[pts] = (index, ticks)
    selected = []
    for row in requested:
        target = Fraction(row["actualPTSValue"], row["actualPTSTimescale"])
        require(target in timeline, "exact_pts_unavailable")
        index, ticks = timeline[target]
        selected.append({"targetSeconds": row["targetSeconds"], "frameIndex": index, "softwarePTS": ticks,
                         "softwareTimeBase": str(time_base), "actualPTSValue": row["actualPTSValue"],
                         "actualPTSTimescale": row["actualPTSTimescale"], "exactRationalPTSMatch": True})
    indices = sorted({row["frameIndex"] for row in selected})
    expression = "+".join(f"eq(n\\,{index})" for index in indices)
    private_process([decoder, "-nostdin", "-v", "error", "-hwaccel", "none", "-c:v", "h264", "-err_detect", "explode",
                     "-copyts", "-protocol_whitelist", "file", "-format_whitelist", "mov", "-f", "mov", "-i", str(source),
                     "-t", "54", "-an", "-sn", "-dn", "-map", "0:v:0", "-map_metadata", "-1", "-map_chapters", "-1",
                     "-vf", "select=" + expression, "-fps_mode", "passthrough", "-frames:v", str(len(indices)),
                     "-c:v", "png", "-fs", str(PNG_CAP), str(private / "software-%d.png")], private, "decode")
    images = {}
    for ordinal, index in enumerate(indices, 1):
        raw, proof = png_file(private / f"software-{ordinal}.png", private, with_proof=True)
        for row in selected:
            if row["frameIndex"] == index:
                images[f"software-{row['targetSeconds']:02d}.png"] = raw
                row["pngProvenance"] = dict(proof)
    require(len(images) == len(selected), "png_rejected")
    return {"timeBase": str(time_base), "frames": selected}, images


def bounded_tool(command, timeout=20, limit=1024 * 1024):
    # simctl outputs contain private paths and never go to stdout/stderr of this script.
    with tempfile.TemporaryDirectory(prefix="complete-object-simctl-") as name:
        path, code = private_process(command, Path(name), "simctl", budget=timeout, output_cap=limit, allow_failure=True)
        return code, path.read_bytes()


def valid_simulator(simulator):
    require(isinstance(simulator, str) and re.fullmatch(UUID, simulator.lower()) is not None, "simulator_unavailable")
    return simulator


def container_cache(simulator):
    valid_simulator(simulator)
    code, raw = bounded_tool(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"], limit=4096)
    require(code == 0, "container_unavailable")
    base = (Path.home() / "Library/Developer/CoreSimulator/Devices").resolve()
    try:
        container = safe_path(Path(raw.decode("utf-8").strip()), base)
    except UnicodeError:
        raise Inconclusive("container_rejected") from None
    relative = container.relative_to(base).parts
    require(len(relative) == 6 and relative[0].lower() == simulator.lower() and
            relative[1:5] == ("data", "Containers", "Data", "Application") and
            re.fullmatch(UUID, relative[5].lower()) is not None and container.is_dir(), "container_rejected")
    cache = safe_path(container / "Library/Caches", container)
    require(cache.is_dir(), "container_unavailable")
    return cache


def quiesce(simulator):
    valid_simulator(simulator)
    # already-Shutdown is accepted only from the exact subsequent state, not return code.
    bounded_tool(["xcrun", "simctl", "shutdown", simulator], timeout=20)
    code, raw = bounded_tool(["xcrun", "simctl", "list", "devices", "--json"], timeout=10)
    require(code == 0, "cleanup_unverified")
    data = unique_json(raw)
    require(isinstance(data, dict) and isinstance(data.get("devices"), dict), "cleanup_unverified")
    matches = []
    for devices in data["devices"].values():
        require(isinstance(devices, list) and len(devices) <= 1000, "cleanup_unverified")
        matches.extend(row for row in devices if isinstance(row, dict) and str(row.get("udid", "")).lower() == simulator.lower())
    require(len(matches) == 1 and matches[0].get("state") == "Shutdown", "cleanup_unverified")


def runner_root(value):
    require(isinstance(value, str) and bool(value) and Path(value).is_absolute(), "private_root_rejected")
    root = Path(value).absolute()
    require(root.is_dir() and not root.is_symlink(), "private_root_rejected")
    return root.resolve()  # trusted OS aliases only; descendants remain untrusted


def cleanup(cache, runner, private=None, fallback=False, owned=True):
    """Call only after process-group completion AND confirmed simulator Shutdown."""
    directory = safe_path(cache / NAMESPACE, cache)
    if fallback:
        # A SIGKILL'ed coordinator cannot prove ownership/wait of a surviving host
        # group. Never kill a recorded/reused PID or delete its potential output.
        # Normal finally already removes everything; only that state is provable.
        residual = [p for p in runner.iterdir() if re.fullmatch(PRIVATE_PREFIX + UUID, p.name)]
        require(not directory.exists() and not residual, "cleanup_unverified")
        return
    if private is not None:
        require(not (safe_path(private, runner) / "host-active").exists(), "cleanup_unverified")
    require(owned or not directory.exists(), "cleanup_unverified")
    if directory.exists():
        require(directory.is_dir(), "cleanup_unverified")
        # Never follow symlinks, even within an owned namespace.
        for current, dirs, files in os.walk(directory, followlinks=False):
            for leaf in (*dirs, *files): safe_path(Path(current) / leaf, cache)
        source = directory / "source.mp4"
        if source.exists():
            require(source.is_file(), "cleanup_unverified")
            source.chmod(0o600)  # deletion follows proven consumer quiescence
        shutil.rmtree(directory)
    candidates = [private] if private is not None else []
    for path in set(candidates):
        path = safe_path(path, runner)
        require(path.parent == runner and re.fullmatch(PRIVATE_PREFIX + UUID, path.name) is not None, "cleanup_unverified")
        if path.exists():
            require(path.is_dir(), "cleanup_unverified")
            for current, dirs, files in os.walk(path, followlinks=False):
                for leaf in (*dirs, *files): safe_path(Path(current) / leaf, runner)
            shutil.rmtree(path)
        require(not path.exists(), "cleanup_unverified")
    require(not directory.exists(), "cleanup_unverified")


def publish(report, images):
    require(report.get("cleanupVerified") is True, "cleanup_unverified")
    root = safe_path(Path.cwd() / "build/complete-object-control", Path.cwd())
    root.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="run-", dir=root))
    leaves = []
    try:
        for name, raw in sorted(images.items()):
            require(re.fullmatch(r"(?:avf|software)-(?:05|15|25|52)\.png", name) is not None, "export_failed")
            validate_png(raw)
            path = safe_path(output / name, output)
            with path.open("xb") as stream: stream.write(raw)
            leaves.append(path)
        destination = output / "report.json"
        raw = (json.dumps(report, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")
        require(len(raw) <= 65536, "export_failed")
        with destination.open("xb") as stream: stream.write(raw)
        leaves.insert(0, destination)
        if os.environ.get("GITHUB_OUTPUT"):
            names = [path.relative_to(Path.cwd()).as_posix() for path in leaves]
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
                stream.write("artifact_files<<COMPLETE_OBJECT_FILES\n" + "\n".join(names) + "\nCOMPLETE_OBJECT_FILES\n")
    except BaseException:
        shutil.rmtree(safe_path(output, Path.cwd()))
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description="Explicit private full-object diagnostic control")
    parser.add_argument("--cleanup-only", action="store_true")
    args = parser.parse_args(argv)
    if os.environ.get("COMPLETE_OBJECT_SAME_BYTES") != "true":
        print("COMPLETE_OBJECT_CONTROL INCONCLUSIVE not_enabled")
        return 0
    if os.environ.get("SAME_ITEM_RENDER_DIAGNOSTICS") != "true":
        print("COMPLETE_OBJECT_CONTROL INCONCLUSIVE opt_in_required")
        return 1
    report = {"schema": 1, "status": "INCONCLUSIVE", "reason": "private_operation_failed",
              "priorBytesEqualityEstablished": False, "sameNewObjectBytesEstablished": False,
              "actualAVFCaptureGatesPassed": False, "cleanupVerified": False, "partial": True}
    private = cache = runner = signature = source = expected = None
    images, capture_error, capture_code, cleaned = {}, None, None, False
    owned, shutdown_confirmed = False, False
    simulator = os.environ.get("SIMULATOR_ID")
    old_handlers = {}
    def cancelled(*_): raise Inconclusive("cancelled")
    for sig in (signal.SIGTERM, signal.SIGINT):
        old_handlers[sig] = signal.signal(sig, cancelled)
    try:
        require(os.environ.get("SAME_ITEM_RENDER_DIAGNOSTICS") == "true", "opt_in_required")
        valid_simulator(simulator)
        runner = runner_root(os.environ.get("RUNNER_TEMP", ""))
        cache = container_cache(simulator)
        if args.cleanup_only:
            quiesce(simulator)
            cleanup(cache, runner, fallback=True)
            cleaned = True
            report.update(reason="same_bytes_complete", cleanupVerified=True)
        else:
            url = locator_url(bounded_json(cache / LOCATOR, cache, 16384))  # read, never delete
            directory = safe_path(cache / NAMESPACE, cache)
            require(not directory.exists(), "namespace_exists")
            directory.mkdir(mode=0o700)
            owned = True
            nonce = str(uuid.uuid4())
            candidate = safe_path(runner / (PRIVATE_PREFIX + nonce), runner)
            candidate.mkdir(mode=0o700)
            private = candidate  # never own/delete an unsuccessfully created directory
            source = directory / "source.mp4"
            claim = fetch(url, source)
            report["container"] = validate_mp4(source)
            source.chmod(0o400)
            signature = identity(source, cache)
            require(file_claim(signature) == claim, "source_changed")
            expected = manifest({"schema": 1, "nonce": nonce, **claim})
            report["source"] = {**claim, "hostBeforeAVFVerified": True,
                                "hostAfterAVFVerified": False, "hostAfterSoftwareVerified": False}
            with (directory / "manifest.json").open("x", encoding="utf-8") as stream:
                json.dump(expected, stream, sort_keys=True)
            try:
                _, capture_code = private_process(capture_command(simulator, private), private, "capture",
                                                  budget=240, output_cap=8 * 1024 * 1024, allow_failure=True)
            except Inconclusive as error:
                capture_error = str(error)
                require(capture_error != "process_group_unverified", "process_group_unverified")
            # Normal/failure and fallback share the same simulator-quiescence primitive.
            quiesce(simulator)
            shutdown_confirmed = True
            identity(source, cache, signature)
            report["source"]["hostAfterAVFVerified"] = True
            result = sanitize_result(bounded_json(directory / "result.json", cache, 16384), expected)
            report["avf"] = result
            report["actualAVFCaptureGatesPassed"] = capture_gates(result)
            requested = []
            for frame in result["frames"]:
                if "actualPTSValue" in frame and frame.get("exportState") == "attached":
                    raw, proof = png_file(directory / TARGETS[frame["targetSeconds"]], cache, with_proof=True)
                    frame["pngProvenance"] = proof
                    images[f"avf-{frame['targetSeconds']:02d}.png"] = raw
                    requested.append(frame)
            require(requested, "returned_pts_invalid")
            try:
                software, software_images = decode(source, private, requested)
                report["software"] = software; images.update(software_images)
            finally:
                identity(source, cache, signature)
                report["source"]["hostAfterSoftwareVerified"] = True
            report["sameNewObjectBytesEstablished"] = True
            complete = report["actualAVFCaptureGatesPassed"] and len(requested) == 4 and capture_code == 0 and capture_error is None
            report.update(status="COMPLETE" if complete else "CONTROL_FAILED", reason="same_bytes_complete" if complete else
                          (capture_error or "capture_failed"), partial=not complete)
    except Inconclusive as error:
        reason = str(error) if str(error) in REASONS else "private_operation_failed"
        if capture_error is not None and reason in {"metadata_unavailable", "returned_pts_invalid"}:
            reason = capture_error
        report.update(status="CONTROL_FAILED" if capture_error is not None or (capture_code is not None and capture_code != 0) or
                      reason in {"source_changed", "cancelled", "process_group_unverified"} else "INCONCLUSIVE", reason=reason)
        if reason in {"source_changed", "process_group_unverified"}: images.clear()
    except BaseException:
        report.update(status="INCONCLUSIVE", reason="private_operation_failed")
    finally:
        try:
            if not cleaned:
                if not shutdown_confirmed: quiesce(simulator)
                # If the container could not be obtained initially, try only after shutdown.
                cache = cache or container_cache(simulator)
                runner = runner or runner_root(os.environ.get("RUNNER_TEMP", ""))
                if args.cleanup_only:
                    cleanup(cache, runner, fallback=True)
                else:
                    cleanup(cache, runner, private=private, owned=owned)
            report["cleanupVerified"] = True
        except BaseException:
            images.clear()
            report.update(status="CONTROL_FAILED", reason="cleanup_unverified", cleanupVerified=False)
        for sig, handler in old_handlers.items(): signal.signal(sig, handler)
    if not args.cleanup_only and report["cleanupVerified"]:
        try:
            publish(report, images)
        except BaseException:
            report.update(status="CONTROL_FAILED", reason="export_failed")
    print("COMPLETE_OBJECT_CONTROL " + report["status"] + " " + report["reason"])
    if args.cleanup_only:
        return 0 if report["cleanupVerified"] else 1
    return 0 if report["status"] == "COMPLETE" else 1


if __name__ == "__main__":
    raise SystemExit(main())
