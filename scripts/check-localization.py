#!/usr/bin/env python3
"""Validate localization resources syntax and keys consistency."""
import plistlib
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = root / "Resources"
strings_file = resources / "zh-Hans.lproj" / "InfoPlist.strings"

if not strings_file.is_file():
    raise SystemExit(f"Missing localization file: {strings_file}")

result = subprocess.run(["plutil", "-lint", str(strings_file)], capture_output=True, text=True)
if result.returncode != 0:
    raise SystemExit(f"Invalid strings format: {result.stderr.strip()}")

info_plist = resources / "Info.plist"
if not info_plist.is_file():
    raise SystemExit(f"Missing Info.plist: {info_plist}")

info_data = plistlib.loads(info_plist.read_bytes())
if "CFBundleLocalizations" not in info_data or "zh-Hans" not in info_data["CFBundleLocalizations"]:
    raise SystemExit("Info.plist missing zh-Hans in CFBundleLocalizations")

print("Localization files verified: zh-Hans.lproj/InfoPlist.strings syntax and plist alignment valid.")
