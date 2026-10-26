"""Export only the bounded app-owned test trace; missing diagnostics never mask test results."""
import os
from pathlib import Path
import re
import subprocess

FILE_NAME = "player-transport.jsonl"
MAX_BYTES = 512 * 1024
BUNDLE_ID = "com.wm0104.xinxingarden"
RENDER_DIRECTORY = "same-item-render"
MAX_RENDER_SAMPLES = 8
MAX_RENDER_JSON = 8192
MAX_RENDER_PNG = 4 * 1024 * 1024


def export_render(cache):
    """Only fixed per-sample pairs, bounded independently of transport-trace availability."""
    source = cache / RENDER_DIRECTORY
    if not source.is_dir() or source.is_symlink():
        return
    samples = []
    for path in source.iterdir():
        if re.fullmatch(r"g[1-9][0-9]{0,5}-s[1-8]\.json", path.name):
            samples.append(path)
            if len(samples) > MAX_RENDER_SAMPLES:
                print("::warning::Same-item render sample count exceeds its bound; no export.")
                return
    for metadata in sorted(samples):
        if metadata.is_symlink() or not metadata.is_file() or metadata.stat().st_size > MAX_RENDER_JSON:
            continue
        with metadata.open("rb") as stream:
            data = stream.read(MAX_RENDER_JSON + 1)
        if not data or len(data) > MAX_RENDER_JSON:
            continue
        output = Path("build") / RENDER_DIRECTORY
        output.mkdir(parents=True, exist_ok=True)
        (output / metadata.name).write_bytes(data)
        png = metadata.with_suffix(".png")
        if not png.is_symlink() and png.is_file() and png.stat().st_size <= MAX_RENDER_PNG:
            with png.open("rb") as stream:
                image = stream.read(MAX_RENDER_PNG + 1)
            if image and len(image) <= MAX_RENDER_PNG:
                (output / png.name).write_bytes(image)
    if samples:
        print("Same-item render: exported bounded diagnostic pairs; inspect timestamps before interpreting.")


def main():
    simulator = os.environ.get("SIMULATOR_ID")
    if not simulator:
        print("Player transport trace: simulator unavailable; no export.")
        return 0
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "get_app_container", simulator, BUNDLE_ID, "data"],
            capture_output=True, text=True, timeout=20, check=False,
        )
        if result.returncode or not result.stdout.strip():
            print("Player transport trace: app container unavailable; no export.")
            return 0
        cache = Path(result.stdout.strip()) / "Library" / "Caches"
        export_render(cache)
        source = cache / FILE_NAME
        with source.open("rb") as stream:
            data = stream.read(MAX_BYTES + 1)
        if not data:
            print("Player transport trace: no records; no export.")
            return 0
        if len(data) > MAX_BYTES:
            print("::warning::Player transport trace exceeds its bound; no export.")
            return 0
        output = Path("build") / FILE_NAME
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        print("Player transport trace: exported bounded test artifact.")
    except (OSError, subprocess.SubprocessError):
        # Do not print simctl output, container paths, file contents or exception strings.
        print("Player transport trace: unavailable; original test result retained.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
