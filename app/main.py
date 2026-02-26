"""
main.py -- FastAPI application entry point.
"""

from fastapi import FastAPI
from app.database import engine, Base
from app.routers  import agent, query, dev

# create all tables on startup (MVP — use Alembic for production)
Base.metadata.create_all(bind=engine)

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
    return {"status": "ok", "service": "licitra-mmr", "version": "0.1.0"}
