"""Export only the bounded app-owned test trace; missing diagnostics never mask test results."""
import os
from pathlib import Path
import subprocess

FILE_NAME = "player-transport.jsonl"
MAX_BYTES = 512 * 1024
BUNDLE_ID = "com.wm0104.xinxingarden"


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
        source = Path(result.stdout.strip()) / "Library" / "Caches" / FILE_NAME
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
