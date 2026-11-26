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

if len(sys.argv) != 3 or not re.fullmatch(r"v\d+\.\d+\.\d+", sys.argv[1]):
    raise SystemExit("Usage: scripts/release-assets.py vX.Y.Z <app bundle>")

tag, app = sys.argv[1], Path(sys.argv[2]).resolve()
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
    checksums = work / "SHA256SUMS.txt"
    with checksums.open("w") as manifest:
        for path in (archive, feed):
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest.write(f"{digest}  {path.name}\n")
    output.mkdir(exist_ok=True)
    notes_path.rename(output / "RELEASE_NOTES.md")
    for path in (archive, feed, checksums):
        path.replace(output / path.name)
print(output)
