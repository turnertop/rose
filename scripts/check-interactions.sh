#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$ROSE_ROOT"
ROSE_INTERACTION_BUILD_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/rose-interaction-checks.XXXXXX")"
trap 'rm -rf "$ROSE_INTERACTION_BUILD_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
    Sources/Rose/LibraryPreferences.swift Sources/Rose/GalleryKeyboard.swift Sources/Rose/LibraryClickSelection.swift Sources/Rose/LibrarySearchField.swift Sources/Rose/ViewerScrollView.swift \
    Tests/RoseInteractionChecks/*.swift -o "$ROSE_INTERACTION_BUILD_DIR/RoseInteractionChecks"
"$ROSE_INTERACTION_BUILD_DIR/RoseInteractionChecks"
