# run_server.ps1 -- Start the LICITRA-MMR FastAPI server
# Usage: .\run_server.ps1

Set-Location D:\AI\licitra-mmr-core

# activate venv
.\.venv\Scripts\Activate.ps1

# start server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
