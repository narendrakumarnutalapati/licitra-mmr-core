# run_server.ps1 -- Start the LICITRA-MMR FastAPI server
# Usage: .\scripts\run_server.ps1

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# activate local venv if present
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    . .\venv\Scripts\Activate.ps1
} elseif (Test-Path ".\.venv\Scripts\Activate.ps1") {
    . .\.venv\Scripts\Activate.ps1
}

# read active runtime config from .env (source of truth)
$envFile = Join-Path $repoRoot ".env"

$blockSize = "1000"
$devMode   = "false"

if (Test-Path $envFile) {
    $envMap = @{}
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $key = $matches[1]
            $val = $matches[2].Trim()
            $envMap[$key] = $val
        }
    }

    if ($envMap.ContainsKey("BLOCK_SIZE")) { $blockSize = $envMap["BLOCK_SIZE"] }
    if ($envMap.ContainsKey("DEV_MODE"))   { $devMode   = $envMap["DEV_MODE"] }
}

$ledgerMode = if ($blockSize -eq "2") { "experiment" } else { "default" }

Write-Host ""
Write-Host "=============================================================="
Write-Host "  LICITRA-MMR Startup"
Write-Host "=============================================================="
Write-Host "  Repo Root   : $repoRoot"
Write-Host "  BLOCK_SIZE  : $blockSize"
Write-Host "  DEV_MODE    : $devMode"
Write-Host "  LEDGER_MODE : $ledgerMode"
Write-Host "=============================================================="
Write-Host ""

# start server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload