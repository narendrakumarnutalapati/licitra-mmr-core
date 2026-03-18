"""
main.py -- FastAPI application entry point.
"""

from datetime import datetime, timezone

from fastapi import FastAPI
from app.database import engine, Base
from app.routers  import agent, query, dev
from app.config import BLOCK_SIZE, DEV_MODE, LEDGER_VERSION, LEDGER_MODE, validate_runtime_mode

# create all tables on startup (MVP — use Alembic for production)
Base.metadata.create_all(bind=engine)

validate_runtime_mode()

app = FastAPI(
    title       = "LICITRA-MMR",
    description = "Production-grade cryptographic runtime integrity layer for agentic systems",
    version     = "0.1.0",
)

# ── routers ───────────────────────────────────────────────────────────────────
app.include_router(agent.router)
app.include_router(query.router)
app.include_router(dev.router)


# ── health ────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["health"])
def health():
    return {
        "status": "ok",
        "service": "licitra-mmr",
        "version": "0.1.0",
        "ledger_version": LEDGER_VERSION,
        "block_size": BLOCK_SIZE,
        "dev_mode": DEV_MODE,
        "ledger_mode": LEDGER_MODE,
        "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
