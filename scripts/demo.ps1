param(
  [string]$Moon = "moon"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& $Moon run cmd/main -- check fixtures/compatible/base fixtures/compatible/head
if ($LASTEXITCODE -ne 0) {
  throw "Compatible fixture failed with exit code $LASTEXITCODE"
}

& $Moon run cmd/main -- check fixtures/demo/base fixtures/demo/head
if ($LASTEXITCODE -ne 1) {
  throw "Breaking fixture should exit with code 1, got $LASTEXITCODE"
}

Write-Host ""
Write-Host "MoonCompat demo passed: compatible exit 0, breaking exit 1."
