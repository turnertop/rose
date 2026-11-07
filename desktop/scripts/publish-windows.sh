#!/usr/bin/env bash
set -euo pipefail
ROSE_DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROSE_DESKTOP_ROOT"
ROSE_ARCH="${1:-x64}"
case "$ROSE_ARCH" in x64|arm64) ;; *) printf 'Usage: bash scripts/publish-windows.sh [x64|arm64]\n' >&2; exit 2 ;; esac
ROSE_VERSION="$(python3 -c 'import xml.etree.ElementTree as E; print(E.parse("Directory.Build.props").findtext("PropertyGroup/Version"))')"
ROSE_OUTPUT="$ROSE_DESKTOP_ROOT/artifacts/Rose-Windows-$ROSE_VERSION-$ROSE_ARCH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export AVALONIA_TELEMETRY_OPTOUT=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER=1
# restore -r replaces RuntimeIdentifiers, narrowing the multi-platform lock graph.
# Set the singular property so development and publish share the same locks.
dotnet restore src/Rose.Desktop/Rose.Desktop.csproj -p:RuntimeIdentifier="win-$ROSE_ARCH" -p:SelfContained=true --locked-mode --disable-parallel
dotnet publish src/Rose.Desktop/Rose.Desktop.csproj --no-restore -c Release -r "win-$ROSE_ARCH" --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -p:UseSharedCompilation=false -m:1 -nr:false -o "$ROSE_OUTPUT"
cp README-Windows.txt "$ROSE_OUTPUT/README-Windows.txt"
python3 scripts/package.py "$ROSE_OUTPUT"
