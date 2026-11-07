#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/swift-env.sh"
cd "$ROSE_ROOT"
swift run "${ROSE_SWIFT_OPTIONS[@]}" RoseChecks "$@"
swift run "${ROSE_SWIFT_OPTIONS[@]}" RoseImagingChecks
bash "$ROSE_ROOT/scripts/check-interactions.sh"
