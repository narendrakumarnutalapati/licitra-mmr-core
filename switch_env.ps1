param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("default","experiment")]
    [string]$mode
)

if ($mode -eq "default") {
    Copy-Item .env.default .env -Force
    Write-Host "MMR mode set to DEFAULT (BLOCK_SIZE=1000)"
}

if ($mode -eq "experiment") {
    Copy-Item .env.experiments .env -Force
    Write-Host "MMR mode set to EXPERIMENT (BLOCK_SIZE=2)"
}
