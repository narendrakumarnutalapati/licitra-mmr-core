# run_server.ps1 -- Start the LICITRA-MMR FastAPI server
# Usage: .\run_server.ps1

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

# activate local venv if present
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    . .\venv\Scripts\Activate.ps1
} elseif (Test-Path ".\.venv\Scripts\Activate.ps1") {
    . .\.venv\Scripts\Activate.ps1
}

# start server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload