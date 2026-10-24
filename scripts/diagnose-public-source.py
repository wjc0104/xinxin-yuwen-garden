"""Single-attempt playback gate and search diagnostics; search outages are warnings.

Log only safe numeric/boolean metadata, never media URLs. No retry or access bypass.
"""
import argparse
import json
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

HOST = "https://api.bilibili.com"
BVID = "BV1eUAieoEZd"
CID = 37155308866
HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://www.bilibili.com/"}


def request(stage, path, parameters, records):
    record = {"stage": stage, "path": path, "http": None, "code": None, "quality": None, "ok": False}
    records.append(record)
    try:
        with urlopen(Request(HOST + path + "?" + urlencode(parameters), headers=HEADERS), timeout=15) as response:
            record["http"] = response.status
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            record["reason"] = "oversized_response"
            return None
        payload = json.loads(raw)
        code = payload.get("code")
        record["code"] = code if isinstance(code, int) else None
        data = payload.get("data")
        quality = data.get("quality") if isinstance(data, dict) else None
        record["quality"] = quality if isinstance(quality, int) else None
        record["ok"] = record["http"] == 200 and code == 0
        if not record["ok"]:
            record["reason"] = "api_rejected"
        return data if record["ok"] else None
    except HTTPError as error:
        record["http"] = error.code
        record["reason"] = "http_rejected"
    except (URLError, TimeoutError, OSError):
        record["reason"] = "transport_error"
    except (ValueError, AttributeError, TypeError):
        record["reason"] = "invalid_json"
    return None


def allowed_media_host(host):
    return host in ("bilivideo.com", "upos-hz-mirrorakam.akamaized.net") or (host or "").endswith(".bilivideo.com")


def complete_source(data):
    if not isinstance(data, dict) or data.get("is_preview") is True or not str(data.get("format", "")).startswith("mp4"):
        return False
    segments = data.get("durl")
    if not isinstance(segments, list) or len(segments) != 1 or not isinstance(segments[0], dict):
        return False
    try:
        media = urlparse(segments[0].get("url", ""))
        return bool(media.scheme == "https" and media.username is None and media.password is None and allowed_media_host(media.hostname))
    except (TypeError, ValueError, AttributeError):
        return False


def source_shape(data):
    shape = {"data_object": isinstance(data, dict), "mp4_format": False, "is_preview": False,
             "segments_list": False, "segment_count": 0, "single_segment_object": False,
             "url_string": False, "url_parse_valid": False, "https": False, "allowed_host": False, "has_credentials": False}
    if not shape["data_object"]:
        return shape
    shape["mp4_format"] = str(data.get("format", "")).startswith("mp4")
    shape["is_preview"] = data.get("is_preview") is True
    segments = data.get("durl")
    shape["segments_list"] = isinstance(segments, list)
    shape["segment_count"] = len(segments) if shape["segments_list"] else 0
    shape["single_segment_object"] = shape["segment_count"] == 1 and isinstance(segments[0], dict)
    if shape["single_segment_object"]:
        url = segments[0].get("url", "")
        shape["url_string"] = isinstance(url, str)
        if not shape["url_string"]:
            return shape
        try:
            media = urlparse(url)
            shape["https"] = media.scheme == "https"
            shape["allowed_host"] = allowed_media_host(media.hostname)
            shape["has_credentials"] = media.username is not None or media.password is not None
            shape["url_parse_valid"] = True
        except (TypeError, ValueError, AttributeError):
            pass
    return shape


def diagnose():
    records = []
    parts = request("parts", "/x/player/pagelist", {"bvid": BVID}, records)
    part = next((part for part in parts if isinstance(part, dict) and part.get("cid") == CID), None) if isinstance(parts, list) else None
    if records[-1]["ok"] and part is None:
        records[-1].update(ok=False, reason="expected_cid_missing")
    if part:
        data = request("playurl", "/x/player/playurl", {"bvid": BVID, "cid": CID, "qn": 80, "fnval": 1, "fnver": 0, "fourk": 0}, records)
        records[-1]["source_shape"] = source_shape(data)
        if records[-1]["ok"]:
            records[-1]["ok"] = complete_source(data)
            if not records[-1]["ok"]:
                records[-1]["reason"] = "no_complete_direct_source"
    # Each distinct API is requested once; there are no retries after a rejection.
    for kind in ("video", "article"):
        data = request("search_" + kind, "/x/web-interface/search/type", {"search_type": kind, "keyword": "南安军 试讲", "page": 1}, records)
        if records[-1]["ok"]:
            results = data.get("result") if isinstance(data, dict) else None
            records[-1]["result_count"] = len(results) if isinstance(results, list) else 0
            valid = isinstance(results, list) and bool(results) and all(isinstance(item, dict) and isinstance(item.get("title"), str) and (isinstance(item.get("bvid"), str) if kind == "video" else isinstance(item.get("id"), int)) for item in results)
            records[-1]["ok"] = valid
            if not records[-1]["ok"]:
                records[-1]["reason"] = "no_results_or_invalid_search_schema"
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    records = diagnose()
    playback_ok = all(any(record["stage"] == stage and record["ok"] for record in records) for stage in ("parts", "playurl"))
    search_ok = all(any(record["stage"] == stage and record["ok"] for record in records) for stage in ("search_video", "search_article"))
    result = {"all_stages_ok": playback_ok and search_ok, "playback_ok": playback_ok, "search_ok": search_ok, "stages": records}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write("playback_ok=" + str(playback_ok).lower() + "\nsearch_ok=" + str(search_ok).lower() + "\n")
    for record in records:
        print("PUBLIC_SOURCE " + json.dumps(record, ensure_ascii=False, sort_keys=True), flush=True)
        if record["stage"].startswith("search_") and not record["ok"]:
            print("PUBLIC_SEARCH_WARNING stage=" + record["stage"] + " availability failed; partial refresh remains supported", flush=True)
    return 0 if playback_ok else 1


if __name__ == "__main__":
    sys.exit(main())
