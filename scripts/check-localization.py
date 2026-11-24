#!/usr/bin/env python3
"""Validate localization resources syntax and keys consistency."""
import plistlib
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = root / "Resources"
strings_file = resources / "zh-Hans.lproj" / "InfoPlist.strings"

if not strings_file.is_file():
    raise SystemExit(f"Missing localization file: {strings_file}")

result = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(strings_file)], capture_output=True)
if result.returncode != 0:
    raise SystemExit(f"Invalid strings format: {(result.stderr or result.stdout).decode().strip()}")

info_plist = resources / "Info.plist"
if not info_plist.is_file():
    raise SystemExit(f"Missing Info.plist: {info_plist}")

info_data = plistlib.loads(info_plist.read_bytes())
if "CFBundleLocalizations" not in info_data or "zh-Hans" not in info_data["CFBundleLocalizations"]:
    raise SystemExit("Info.plist missing zh-Hans in CFBundleLocalizations")

localized = plistlib.loads(result.stdout)
for key, value in localized.items():
    if not isinstance(info_data.get(key), str):
        raise SystemExit(f"Localized Info.plist key has no base string: {key}")
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"Localized Info.plist value is empty or invalid: {key}")
if not localized:
    raise SystemExit("zh-Hans InfoPlist.strings is empty")
print("zh-Hans InfoPlist.strings syntax and base keys verified.")
