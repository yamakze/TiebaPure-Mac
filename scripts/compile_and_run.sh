#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" == --help ]]; then
    echo "Usage: scripts/compile_and_run.sh [debug|release]"
    exit 0
fi
if (( $# > 1 )); then echo "Too many arguments; use --help." >&2; exit 2; fi
CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) echo "Use debug or release; see --help." >&2; exit 2 ;; esac
scripts/build-app.sh "$CONFIGURATION"

app_bundle="$ROOT/artifacts/macos/TiebaPure-Mac.app"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_bundle/Contents/Info.plist")"
app_executable="$app_bundle/Contents/MacOS/$executable_name"
# Match this checkout's complete executable path; other installations and the
# screenshot application have independent processes.
processes="$(ps -axo pid=,comm=)"
while read -r process_id executable; do
    if [[ "$executable" != "$app_executable" ]]; then continue; fi
    echo "停止旧 TiebaPure-Mac 进程：$process_id"
    kill -TERM "$process_id"
    stop_deadline=$((SECONDS + 5))
    while kill -0 "$process_id" 2>/dev/null && (( SECONDS < stop_deadline )); do
        sleep 0.1
    done
    if kill -0 "$process_id" 2>/dev/null; then
        echo "旧进程未退出，强制停止：$process_id"
        kill -KILL "$process_id"
    fi
done <<< "$processes"
launch_services=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$launch_services" -u "$app_bundle"
touch "$app_bundle"
"$launch_services" -f "$app_bundle"
open -n "$app_bundle"
echo "已启动：$app_bundle"
