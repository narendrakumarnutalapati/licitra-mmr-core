param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("default","test","experiment")]
    [string]$mode
)

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if ($mode -eq "default") {
    Copy-Item .env.default .env -Force
    Write-Host "MMR mode set to DEFAULT (BLOCK_SIZE=1000, DEV_MODE=false)"
}

if ($mode -eq "test") {
    Copy-Item .env.test .env -Force
    Write-Host "MMR mode set to TEST (BLOCK_SIZE=1000, DEV_MODE=true)"
}

if ($mode -eq "experiment") {
    Copy-Item .env.experiment .env -Force
    Write-Host "MMR mode set to EXPERIMENT (BLOCK_SIZE=2, DEV_MODE=true)"
}