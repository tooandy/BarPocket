#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
OUT="$ROOT/dist/BarPocket.app"
INSTALL="${HOME}/Applications/BarPocket.app"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$ROOT/Info.plist" "$OUT/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -framework AppKit -framework ServiceManagement -framework ApplicationServices -framework CoreGraphics -o "$OUT/Contents/MacOS/MenuBarPocket" "$ROOT"/Sources/*.swift
"$OUT/Contents/MacOS/MenuBarPocket" --self-test
codesign --force --sign - "$OUT"
codesign --verify --strict "$OUT"
if [[ "${1:-}" == "--install" ]]; then
  if /usr/bin/pgrep -f "^$INSTALL/Contents/MacOS/MenuBarPocket$" >/dev/null; then
    echo "Please quit existing BarPocket before installing an update" >&2
    exit 1
  fi
  mkdir -p "${HOME}/Applications"
  /usr/bin/ditto "$OUT" "$INSTALL"
  codesign --verify --strict "$INSTALL"
  echo "Installed at: $INSTALL"
else
  echo "Built at: $OUT"
fi
