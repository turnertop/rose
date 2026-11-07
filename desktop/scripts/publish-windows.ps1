param([ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$version = ([xml](Get-Content Directory.Build.props -Raw)).Project.PropertyGroup.Version
$output = Join-Path (Get-Location) "artifacts/Rose-Windows-$version-$Architecture"
dotnet restore src/Rose.Desktop/Rose.Desktop.csproj -p:RuntimeIdentifier="win-$Architecture" -p:SelfContained=true --locked-mode --disable-parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dotnet publish src/Rose.Desktop/Rose.Desktop.csproj --no-restore -c Release -r "win-$Architecture" --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -p:UseSharedCompilation=false -m:1 -nr:false -o $output
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item README-Windows.txt "$output/README-Windows.txt"
Copy-Item ../LICENSE "$output/LICENSE.txt"
Copy-Item ../NOTICE "$output/NOTICE.txt"
Copy-Item THIRD-PARTY-NOTICES.txt "$output/THIRD-PARTY-NOTICES.txt"
$runtimeVersion = ([xml](Get-Content src/Rose.Desktop/Rose.Desktop.csproj -Raw)).Project.PropertyGroup.RuntimeFrameworkVersion
$packageRoot = ((dotnet nuget locals global-packages --list) -split ':', 2)[1].Trim()
$runtime = Join-Path $packageRoot "microsoft.netcore.app.runtime.win-$Architecture/$runtimeVersion"
if (Test-Path $runtime) {
    Get-ChildItem $runtime -File | Where-Object { $_.Name -match 'license|notice' } | ForEach-Object {
        Add-Content "$output/THIRD-PARTY-NOTICES.txt" (Get-Content $_.FullName -Raw)
    }
}
$files = [ordered]@{}
Get-ChildItem $output -Recurse -File | Where-Object { $_.Name -ne 'build-manifest.json' } | Sort-Object FullName | ForEach-Object {
    $files[$_.FullName.Substring($output.Length + 1).Replace('\', '/')] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$sourceCommit = if (Get-Command git -ErrorAction SilentlyContinue) { (git rev-parse HEAD).Trim() } else { 'unknown' }
@{ product = 'Rose for Windows'; version = "$version-preview"; sourceCommit = $sourceCommit; selfContained = $true; files = $files } |
    ConvertTo-Json -Depth 5 | Set-Content "$output/build-manifest.json" -Encoding UTF8
$archive = "$output.zip"
if (Test-Path $archive) { Remove-Item $archive }
Compress-Archive -Path $output -DestinationPath $archive
Get-FileHash $archive -Algorithm SHA256 | Format-List
"$((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant())  $(Split-Path $archive -Leaf)" | Set-Content "$archive.sha256" -Encoding ascii
Write-Output "Created $archive"
