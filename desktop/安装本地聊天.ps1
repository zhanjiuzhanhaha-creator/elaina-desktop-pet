param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$resourceDir = Join-Path $PSScriptRoot 'local-chat'
$manifest = Get-Content -LiteralPath (Join-Path $resourceDir 'provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$downloadDir = Join-Path $resourceDir 'downloads'
$runtimeDir = Join-Path $resourceDir 'runtime'
$runtimeZip = Join-Path $downloadDir 'llama-b11718-bin-win-cpu-x64.zip'
$modelPath = Join-Path $resourceDir $manifest.model.file

function Test-DownloadHash([string]$Path, [string]$Hash) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Hash
}

function Get-VerifiedDownload([string]$Url, [string]$Path, [string]$Hash) {
    if (Test-DownloadHash $Path $Hash) { Write-Host ('Already verified: ' + [IO.Path]::GetFileName($Path)); return }
    $temporary = $Path + '.download'
    Write-Host ('Downloading: ' + [IO.Path]::GetFileName($Path))
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporary
    if (-not (Test-DownloadHash $temporary $Hash)) { throw ('SHA256 mismatch: ' + $temporary + '. Nothing has been installed from this download.') }
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

if ($VerifyOnly) {
    if (-not (Test-DownloadHash $modelPath $manifest.model.sha256)) { throw 'Model missing or SHA256 mismatch.' }
    if (-not (Test-Path -LiteralPath (Join-Path $runtimeDir 'llama-server.exe'))) { throw 'Runtime missing.' }
    Write-Host 'PASS: model SHA256 verified; llama-server.exe exists.'
    exit 0
}

if (-not [Environment]::Is64BitOperatingSystem) { throw 'This package requires 64-bit Windows.' }
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
Get-VerifiedDownload $manifest.runtime.url $runtimeZip $manifest.runtime.sha256
Get-VerifiedDownload $manifest.model.download_url $modelPath $manifest.model.sha256
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force
if (-not (Test-Path -LiteralPath (Join-Path $runtimeDir 'llama-server.exe'))) { throw 'Unexpected runtime archive layout: llama-server.exe was not found at runtime root.' }
Write-Host 'Ready. Restart the pet and open its chat window. Model inference stays on this computer.'
