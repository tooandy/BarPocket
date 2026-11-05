#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: Scripts/package.sh <version>}"
APP="$ROOT/dist/BarPocket.app"
ARCH="$(uname -m)"

if [[ ! -d "$APP" ]]; then
  echo "Missing app bundle: $APP (run ./build.sh first)" >&2
  exit 1
fi
if [[ "$ARCH" != "arm64" ]]; then
  echo "This release workflow currently targets Apple Silicon; got $ARCH" >&2
  exit 1
fi

ZIP="$ROOT/dist/BarPocket-${VERSION}-${ARCH}.zip"
DMG="$ROOT/dist/BarPocket-${VERSION}-${ARCH}.dmg"
(
  cd "$ROOT/dist"
  rm -f "$(basename "$ZIP")" "$(basename "$DMG")" SHA256SUMS
  ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP")" "$(basename "$ZIP")"
  hdiutil create -volname "BarPocket ${VERSION}" -srcfolder "$(basename "$APP")" -ov -format UDZO "$(basename "$DMG")"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS
)

echo "Created: $ZIP"
echo "Created: $DMG"
echo "Created: $ROOT/dist/SHA256SUMS"
