"""Compare the current Info.plist with the previous stable release on stdin."""

import plistlib
import re
import sys
from pathlib import Path


def build_number(info, release):
    value = str(info.get("CFBundleVersion", ""))
    if not re.fullmatch(r"[0-9]+", value):
        raise SystemExit(f"{release} CFBundleVersion must be numeric.")
    return int(value)


current = build_number(plistlib.loads(Path(sys.argv[1]).read_bytes()), "Current")
previous = build_number(plistlib.loads(sys.stdin.buffer.read()), "Previous")
if current <= previous:
    raise SystemExit(f"CFBundleVersion must increase from {previous}; found {current}.")
print(f"CFBundleVersion increased from {previous} to {current}.")
