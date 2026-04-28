param(
    [switch] $Firmware,
    [switch] $IosPreflight,
    [switch] $OfflineVision,
    [switch] $SkipPubGet
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "==> Credential scan" -ForegroundColor Cyan
$secretMatches = git grep -n -I -E "AIza[0-9A-Za-z_-]{20,}|sk-[0-9A-Za-z_-]{20,}|BEGIN (RSA|OPENSSH|PRIVATE) KEY" -- . ":(exclude).env" ":(exclude)SECRETS.md"
if ($LASTEXITCODE -eq 0) {
    $secretMatches
    throw "Potential credential material found."
}
if ($LASTEXITCODE -ne 1) {
    throw "Credential scan failed with exit code $LASTEXITCODE"
}

Write-Host "==> Targeted tests" -ForegroundColor Cyan
flutter test --no-pub test/services/scene_description_service_test.dart test/models/home_view_model_test.dart test/protocol/ble_protocol_test.dart
if ($LASTEXITCODE -ne 0) {
    throw "Targeted tests failed with exit code $LASTEXITCODE"
}

$verifyArgs = @()
if ($SkipPubGet) { $verifyArgs += "-SkipPubGet" }
if ($Firmware) { $verifyArgs += "-Firmware" }
if ($IosPreflight) { $verifyArgs += "-IosPreflight" }
if ($OfflineVision) { $verifyArgs += "-OfflineVision" }

Write-Host "==> Full agent verification" -ForegroundColor Cyan
& .\scripts\agent_verify.ps1 @verifyArgs
if ($LASTEXITCODE -ne 0) {
    throw "Agent verification failed with exit code $LASTEXITCODE"
}

Write-Host "Agent preflight completed." -ForegroundColor Green
