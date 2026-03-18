import os
from dotenv import load_dotenv

load_dotenv()


def _env_bool(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).strip().lower() == "true"


DATABASE_URL: str = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/licitra_mmr",
)

BLOCK_SIZE: int = int(os.getenv("BLOCK_SIZE", "1000"))
DEV_MODE: bool = _env_bool("DEV_MODE", "false")
EMIT_BLOCKED_ACTION: bool = _env_bool("EMIT_BLOCKED_ACTION", "true")
POLICY_VERSION: str = os.getenv("POLICY_VERSION", "v0.1")
LEDGER_VERSION: str = "mmr-v0.1"
GENESIS_HASH: str = "00" * 32

LEDGER_MODE: str = "experiment" if BLOCK_SIZE == 2 else "default"


def validate_runtime_mode() -> None:
    """
    Enforce clean, reviewer-friendly runtime modes.

    Supported intended modes:
      - default:    BLOCK_SIZE=1000, DEV_MODE=false
      - experiment: BLOCK_SIZE=2,    DEV_MODE=true

    Other combinations are allowed only with an explicit warning for now,
    because they may be useful during development, but they are not
    considered reviewer-ready baseline configurations.
    """
    if BLOCK_SIZE <= 0:
        raise ValueError(f"Invalid BLOCK_SIZE={BLOCK_SIZE}. BLOCK_SIZE must be > 0.")

    if LEDGER_MODE == "default" and DEV_MODE:
        print(
            "[WARN] LICITRA-MMR started in mixed mode: "
            "BLOCK_SIZE=1000-like default behavior with DEV_MODE=true. "
            "This is not reviewer-ready and exposes developer-only mutation endpoints."
        )

    if LEDGER_MODE == "experiment" and not DEV_MODE:
        print(
            "[WARN] LICITRA-MMR started in mixed mode: "
            "BLOCK_SIZE=2 experiment behavior with DEV_MODE=false. "
            "Some experiment workflows may not function as expected."
        )