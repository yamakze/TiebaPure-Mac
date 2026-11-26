"""Compute the next monotonically increasing integer CFBundleVersion for a release."""

import argparse
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def parse_build_number(raw: str, source: str) -> int:
    value = str(raw).strip()
    if not re.fullmatch(r"[0-9]+", value):
        raise SystemExit(f"{source} CFBundleVersion must be numeric; got {value!r}.")
    return int(value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("current_plist", type=Path, help="Path to current Resources/Info.plist")
    previous = parser.add_mutually_exclusive_group()
    previous.add_argument("--previous-appcast", action="store_true", help="Read previous appcast.xml from stdin")
    previous.add_argument("--previous-plist", action="store_true", help="Read previous Info.plist from stdin")
    args = parser.parse_args()

    current_info = plistlib.loads(args.current_plist.read_bytes())
    current_build = parse_build_number(current_info.get("CFBundleVersion", ""), str(args.current_plist))

    previous_build = 0
    if args.previous_appcast:
        version = ET.parse(sys.stdin.buffer).findtext("./channel/item/" + SPARKLE_NS + "version")
        previous_build = parse_build_number(version, "Previous appcast.xml")
    elif args.previous_plist:
        previous_info = plistlib.loads(sys.stdin.buffer.read())
        previous_build = parse_build_number(previous_info.get("CFBundleVersion", ""), "Previous Info.plist")

    print(max(current_build, previous_build + 1))


if __name__ == "__main__":
    main()
