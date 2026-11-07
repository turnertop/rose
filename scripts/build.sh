#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$ROSE_ROOT"
ROSE_CONFIGURATION="${1:-release}"
ROSE_BUILD_OPTIONS=("${ROSE_SWIFT_OPTIONS[@]}")
if [ "$ROSE_CONFIGURATION" = release ]; then
    # Release debug/source records use a neutral root instead of a local username.
    ROSE_BUILD_OPTIONS+=(-Xswiftc -debug-prefix-map -Xswiftc "$ROSE_ROOT=/_/rose"
                        -Xswiftc -file-prefix-map -Xswiftc "$ROSE_ROOT=/_/rose")
fi
swift build "${ROSE_BUILD_OPTIONS[@]}" --configuration "$ROSE_CONFIGURATION" --product Rose
ROSE_BINARY_DIR="$(swift build "${ROSE_BUILD_OPTIONS[@]}" --configuration "$ROSE_CONFIGURATION" --show-bin-path)"
ROSE_APP="${ROSE_APP_PATH:-$ROSE_ROOT/build/Rose.app}"
mkdir -p "$ROSE_APP/Contents/MacOS" "$ROSE_APP/Contents/Resources"
cp "$ROSE_BINARY_DIR/Rose" "$ROSE_APP/Contents/MacOS/Rose"
if [ "$ROSE_CONFIGURATION" = release ]; then
    # The linker's debug map can still contain absolute object-file paths.
    strip -S "$ROSE_APP/Contents/MacOS/Rose"
fi
cp "$ROSE_ROOT/Resources/Info.plist" "$ROSE_APP/Contents/Info.plist"
cp "$ROSE_ROOT/LICENSE" "$ROSE_APP/Contents/Resources/LICENSE.txt"
cp "$ROSE_ROOT/NOTICE" "$ROSE_APP/Contents/Resources/NOTICE.txt"
if [ ! -f "$ROSE_ROOT/.build/Rose.icns" ]; then
    swift "$ROSE_ROOT/scripts/MakeIcon.swift" "$ROSE_ROOT/.build/Rose.iconset"
fi
cp "$ROSE_ROOT/.build/Rose.icns" "$ROSE_APP/Contents/Resources/Rose.icns"
codesign --force --sign - "$ROSE_APP"
printf '\nBuilt %s\n' "$ROSE_APP"
