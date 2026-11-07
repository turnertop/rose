$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
dotnet restore tests/Rose.Checks/Rose.Checks.csproj --locked-mode --disable-parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dotnet build tests/Rose.Checks/Rose.Checks.csproj --no-restore -c Release -m:1 -nr:false -p:UseSharedCompilation=false
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dotnet tests/Rose.Checks/bin/Release/net10.0/Rose.Checks.dll
exit $LASTEXITCODE
