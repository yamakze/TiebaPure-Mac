#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTPUT="${1:-$ROOT/screenshots/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
if [[ -e "$OUTPUT/Review.xcresult" ]]; then
    echo "Output already contains a review run: $OUTPUT" >&2
    exit 2
fi
scripts/build-app.sh debug
WORK="$ROOT/.build/screenshot-runner"
mkdir -p "$WORK"
APP="$WORK/TiebaPure-Mac-Screenshots.app"
if [[ -d "$APP" ]]; then rm -rf "$APP"; fi
ditto artifacts/macos/TiebaPure-Mac.app "$APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.yamakze.TiebaPureMac.Screenshots' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName TiebaPure-Mac-Screenshots' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName TiebaPure-Mac-Screenshots' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
# Generate a disposable standalone UI-test runner; SwiftPM remains the app's source of truth.
python3 "$ROOT/scripts/lib/screenshot-project.py" "$ROOT" "$APP"
xcodebuild test -project "$WORK/ScreenshotRunner.xcodeproj" -scheme Screenshots \
    -destination 'platform=macOS' -derivedDataPath "$WORK/DerivedData" \
    -resultBundlePath "$OUTPUT/Review.xcresult" \
    -parallel-testing-enabled NO CODE_SIGN_IDENTITY=-
xcrun xcresulttool export attachments --path "$OUTPUT/Review.xcresult" --output-path "$OUTPUT/attachments"
python3 - "$OUTPUT" <<'PY'
import json, pathlib, shutil, sys
output = pathlib.Path(sys.argv[1])
names = [f'{number:02}-{page}-{appearance}' for appearance in ['light', 'dark']
         for number, page in enumerate(['home', 'thread', 'subposts', 'forum-entry', 'forum', 'search-entry', 'search', 'login', 'settings'], 1)]
names += [f'10-home-{state}' for state in ['empty', 'error', 'loading']]
names += ['11-home-pagination-retry', '12-home-account', '13-account-profile']
names += ['14-forum-featured', '15-forum-search', '16-followed-forums', '17-favorites', '18-thread-author']
login_unavailable = []
for test in json.loads((output / 'attachments/manifest.json').read_text()):
    for attachment in test['attachments']:
        name = attachment['suggestedHumanReadableName'].split('_', 1)[0].removesuffix('.png')
        if name.startswith('login-form-unavailable-'):
            login_unavailable.append(name.removeprefix('login-form-unavailable-'))
        if name in names:
            shutil.copyfile(output / 'attachments' / attachment['exportedFileName'], output / (name + '.png'))
missing = [name for name in names if not (output / (name + '.png')).is_file()]
if missing:
    raise SystemExit('Missing screenshots: ' + ', '.join(missing))
(output / 'manifest.json').write_text(json.dumps({'screenshots': names, 'data': 'synthetic', 'login': 'live WebKit; network-dependent', 'loginFormUnavailable': login_unavailable}, indent=2))
navigation = '<nav>' + ' · '.join(f'<a href="#{name}">{name}</a>' for name in names) + '</nav>'
note = '<p>登录表单未完成加载：' + ', '.join(sorted(login_unavailable)) + '。截图保留当时的 WebKit 状态。</p>' if login_unavailable else ''
figures = ''.join(f'<figure id="{name}"><figcaption>{name}</figcaption><a href="{name}.png"><img src="{name}.png" loading="lazy"></a></figure>' for name in names)
(output / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>TiebaPure-Mac UI Review</title><style>body{font:16px system-ui;margin:24px;background:#eee}figure{margin:32px 0}img{max-width:100%;height:auto}figcaption{margin:10px 0}</style><h1>TiebaPure-Mac UI Review</h1><p>固定样例数据；登录页依赖百度网络。页面编号可用于反馈。</p>' + note + navigation + figures)
print(output / 'index.html')
PY
