#!/bin/bash
# Keep compiler caches inside the project so sandboxed and regular builds behave alike.
set -euo pipefail
ROSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROSE_ROOT/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROSE_ROOT/.build/swift-module-cache}"
ROSE_SWIFT_OPTIONS=(--scratch-path "${ROSE_SCRATCH_PATH:-$ROSE_ROOT/.build/package}" --cache-path "$ROSE_ROOT/.build/cache" --config-path "$ROSE_ROOT/.build/config" --security-path "$ROSE_ROOT/.build/security" --disable-sandbox)
