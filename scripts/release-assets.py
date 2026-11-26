#!/usr/bin/env python3
"""Package a Mac release and sign its archive and Sparkle feed."""

import hashlib
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

if (
    len(sys.argv) != 4
    or not re.fullmatch(r"v\d+\.\d+\.\d+", sys.argv[1])
    or sys.argv[3] not in {"adhoc", "notarized"}
):
    raise SystemExit("Usage: scripts/release-assets.py vX.Y.Z <app bundle> <adhoc|notarized>")

tag, app, signing_mode = sys.argv[1], Path(sys.argv[2]).resolve(), sys.argv[3]
version = tag.removeprefix("v")
root = Path(__file__).resolve().parents[1]
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if info["CFBundleShortVersionString"] != version:
    raise SystemExit("Release tag does not match the application version")
if not info.get("SUPublicEDKey") or not info.get("SURequireSignedFeed"):
    raise SystemExit("The release app must be configured for signed Sparkle updates")
private_key = os.environ.pop("SPARKLE_PRIVATE_KEY", "").strip()
if not private_key:
    raise SystemExit("SPARKLE_PRIVATE_KEY is required")

notes = subprocess.check_output([root / "scripts/release-notes.sh", tag], text=True)

tools = root / ".build/artifacts/sparkle/Sparkle/bin"
releases = info["SUFeedURL"].removesuffix("/latest/download/appcast.xml")
download_prefix = f"{releases}/download/{tag}/"
output = root / "artifacts/release" / tag
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix=".release.", dir=output.parent) as directory:
    work = Path(directory)
    archive = work / f"TiebaPure-Mac-{version}.zip"
    feed = work / "appcast.xml"
    notes_path = archive.with_suffix(".md")
    notes_path.write_text(notes)
    subprocess.run(["ditto", "-c", "-k", "--keepParent", app, archive], check=True)
    subprocess.run([
        tools / "generate_appcast", "--ed-key-file", "-", "--embed-release-notes",
        "--maximum-deltas", "0", "--download-url-prefix", download_prefix,
        "--link", f"{releases}/tag/{tag}", "--full-release-notes-url", releases,
        "-o", feed, work,
    ], input=private_key, text=True, check=True)
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    item = ET.parse(feed).find("./channel/item")
    enclosure = item.find("enclosure") if item is not None else None
    if enclosure is None or not enclosure.get(sparkle + "edSignature"):
        raise SystemExit("Missing update archive signature. Check the Sparkle key pair.")
    if (
        item.findtext(sparkle + "version") != info["CFBundleVersion"]
        or item.findtext(sparkle + "shortVersionString") != version
        or enclosure.get("url") != download_prefix + archive.name
        or enclosure.get("length") != str(archive.stat().st_size)
    ):
        raise SystemExit("Appcast metadata does not match the release archive")
    subprocess.run(
        [tools / "sign_update", "--verify", "--ed-key-file", "-", feed],
        input=private_key, text=True, check=True,
    )
    binary = app / "Contents" / "MacOS" / "TiebaPureMac"
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
    if signing_mode == "adhoc":
        signing_zh = "本版使用 ad-hoc 签名，未经 Apple 公证，首次打开受阻时可参阅 [Apple 支持](https://support.apple.com/zh-cn/102445)。"
        signing_en = "This build is ad-hoc signed and unnotarized. See [Apple Support](https://support.apple.com/en-us/102445) if macOS blocks the first launch."
    else:
        signing_zh = "本版已使用 Developer ID 签名并通过 Apple 公证。"
        signing_en = "This build is Developer ID signed and notarized."
    package_notes = work / "PACKAGE_NOTES.md"
    package_notes.write_text(
        "## 下载与升级 / Download and upgrade\n\n"
        f"- macOS 14+ (`{architectures}`) · `{archive.name}`\n"
        "- `SHA256SUMS.txt` · 下载校验 / Download checksums\n"
        "- `appcast.xml` · 已签名的 Sparkle 更新源 / Signed Sparkle update feed\n\n"
        f"{signing_zh}\n\n{signing_en}\n"
    )
    checksums = work / "SHA256SUMS.txt"
    with checksums.open("w") as manifest:
        for path in (archive, feed):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest.write(f"{digest}  {path.name}\n")
    output.mkdir(exist_ok=True)
    notes_path.rename(output / "RELEASE_NOTES.md")
    package_notes.rename(output / "PACKAGE_NOTES.md")
    for path in (archive, feed, checksums):
        path.replace(output / path.name)
print(output)
