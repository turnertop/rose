#!/bin/bash
set -euo pipefail
ROSE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$ROSE_ROOT/build/Rose.app" ]; then bash "$ROSE_ROOT/scripts/build.sh"; fi
open "$ROSE_ROOT/build/Rose.app" "$@"
