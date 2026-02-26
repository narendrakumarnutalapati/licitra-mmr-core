import json
import math
from typing import Any


def canonical_dumps(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def canonical_bytes(obj: Any) -> bytes:
    return canonical_dumps(obj).encode("utf-8")


def canonical_loads(s: str) -> Any:
    return json.loads(s)
