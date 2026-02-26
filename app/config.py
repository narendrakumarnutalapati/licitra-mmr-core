import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL: str = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/licitra_mmr")
BLOCK_SIZE: int = int(os.getenv("BLOCK_SIZE", "1000"))
DEV_MODE: bool = os.getenv("DEV_MODE", "false").lower() == "true"
EMIT_BLOCKED_ACTION: bool = os.getenv("EMIT_BLOCKED_ACTION", "true").lower() == "true"
POLICY_VERSION: str = os.getenv("POLICY_VERSION", "v0.1")
LEDGER_VERSION: str = "mmr-v0.1"
GENESIS_HASH: str = "00" * 32
