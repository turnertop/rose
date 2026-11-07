#!/bin/bash
set -euo pipefail
ROSE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROSE_APP="${ROSE_APP_PATH:-$ROSE_ROOT/build/Rose.app}"
if pgrep -x Rose >/dev/null; then
    printf 'Quit the running Rose app before starting a diagnostic session.\n' >&2
    exit 1
fi
if [ ! -x "$ROSE_APP/Contents/MacOS/Rose" ]; then
    printf 'Build Rose first with ./scripts/build.sh.\n' >&2
    exit 1
fi
export ROSE_PERFORMANCE_LOG=1
exec "$ROSE_APP/Contents/MacOS/Rose" "$@"
