#!/usr/bin/env bash
# Extracts the CHANGELOG.md section for a version.
# Usage: scripts/release-notes.sh <version>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_VERSION="${1:?usage: release-notes.sh <version>}"
VERSION="${RAW_VERSION#mac-v}"
VERSION="${VERSION#v}"

SECTION="$(awk -v ver="$VERSION" '
  /^## / {
    if (found) exit
    if ($2 == ver) { found = 1; next }
  }
  found {
    if (!NF) {
      if (started) blanks++
      next
    }
    while (blanks > 0) { print ""; blanks-- }
    print
    started = 1
  }
' "$ROOT/CHANGELOG.md")"

if [ -z "$SECTION" ]; then
  echo "ERROR: CHANGELOG.md has no section for version $VERSION (expected '## $VERSION')" >&2
  exit 1
fi

printf '%s\n' "$SECTION"
