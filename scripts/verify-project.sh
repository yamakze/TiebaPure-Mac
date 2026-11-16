#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import plistlib
import re

root = Path('.')
for name in ['TiebaPure', 'TiebaPure.xcodeproj', 'TiebaPureOpenIn', 'project.yml']:
    if (root / name).exists():
        raise SystemExit(f'Obsolete platform entry: {name}')
for path in Path('Sources').rglob('*.swift'):
    if re.search(r'import UIKit|#available\(iOS|#if os\(iOS\)', path.read_text()):
        raise SystemExit(f'iOS-only implementation: {path}')
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
expected_names = {
    'CFBundleName': 'TiebaPure-Mac',
    'CFBundleDisplayName': 'TiebaPure-Mac',
    'CFBundleExecutable': 'TiebaPureMac',
    'CFBundleIdentifier': 'io.github.yamakze.TiebaPureMac',
}
for key, expected in expected_names.items():
    if info.get(key) != expected:
        raise SystemExit(f'App naming differs from project policy: {key}')
if info['LSMinimumSystemVersion'] != '14.0':
    raise SystemExit('Update Package.swift and the deployment policy together.')
if not re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']):
    raise SystemExit('Expected a semantic app version.')
if not str(info['CFBundleVersion']).isdigit():
    raise SystemExit('Expected a numeric build version.')
manifest = Path('Package.swift').read_text()
if 'name: "TiebaPure-Mac"' not in manifest:
    raise SystemExit('SwiftPM package differs from the app name.')
if 'platforms: [.macOS(.v14)]' not in manifest:
    raise SystemExit('Package platform differs from app deployment policy.')
version = re.search(r'exact: "([^"]+)"', manifest).group(1)
generator = Path('scripts/generate-protos.sh').read_text()
if f'EXPECTED_SWIFT_PROTOBUF_VERSION="{version}"' not in generator:
    raise SystemExit('Protobuf generator/runtime versions differ.')
for name in ['LICENSE', 'NOTICE.md', 'LICENSES/SwiftProtobuf-Apache-2.0.txt']:
    if not Path(name).is_file():
        raise SystemExit(f'Missing attribution: {name}')
print('Native Mac project boundaries, versions, and notices verified.')
PY
