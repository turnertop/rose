#!/usr/bin/env bash
set -euo pipefail
ROSE_DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROSE_DESKTOP_ROOT"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export AVALONIA_TELEMETRY_OPTOUT=1
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER=1
dotnet restore tests/Rose.Checks/Rose.Checks.csproj --locked-mode --disable-parallel
dotnet build tests/Rose.Checks/Rose.Checks.csproj --no-restore -c Release -m:1 -nr:false -p:UseSharedCompilation=false
dotnet tests/Rose.Checks/bin/Release/net10.0/Rose.Checks.dll
