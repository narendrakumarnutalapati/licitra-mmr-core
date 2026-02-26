"""
policy.py -- Control-plane policy engine for the 2-Phase Commit gate.

IMPORTANT: These are heuristic/rule-based checks only.
They are NOT cryptographic guarantees.
Every decision is logged in staged_events regardless of outcome.
"""

import json
from dataclasses import dataclass
from typing import Any, Dict, Tuple
from app.config import POLICY_VERSION


@dataclass
class PolicyResult:
    status: str          # "APPROVED" | "REJECTED"
    reason: str
    risk_score: float    # 0.0 = clean, 1.0 = maximum risk


# ── hard rules (binary pass/fail) ────────────────────────────────────────────

def _rule_required_fields(payload: Dict) -> Tuple[bool, str]:
    required = {"agent_id", "action_type", "timestamp"}
    missing  = required - set(payload.keys())
    if missing:
        return False, f"Missing required fields: {sorted(missing)}"
    return True, ""


def _rule_max_payload_size(raw_json: str) -> Tuple[bool, str]:
    size = len(raw_json.encode("utf-8"))
    if size > 65_536:
        return False, f"Payload too large: {size} bytes (max 65536)"
    return True, ""


def _rule_no_delete_action(payload: Dict) -> Tuple[bool, str]:
    action = str(payload.get("action_type", "")).lower()
    if action == "delete":
        return False, "action_type=delete is blocked by policy"
    return True, ""


def _rule_no_empty_agent(payload: Dict) -> Tuple[bool, str]:
    if not str(payload.get("agent_id", "")).strip():
        return False, "agent_id must not be empty"
    return True, ""


HARD_RULES = [
    _rule_required_fields,
    _rule_no_empty_agent,
    _rule_no_delete_action,
]


# ── heuristic scorer (0.0–1.0, fallible) ─────────────────────────────────────

_HIGH_RISK_KEYWORDS = [
    "drop table", "truncate", "rm -rf", "format", "shutdown",
    "override", "bypass", "inject", "exec(", "eval(",
    "__import__", "os.system", "subprocess",
]


def _heuristic_score(raw_json: str, payload: Dict) -> float:
    score = 0.0
    lower = raw_json.lower()

    # keyword scan
    hits = sum(1 for kw in _HIGH_RISK_KEYWORDS if kw in lower)
    if hits:
        score += min(0.6, hits * 0.15)

    # unusually long action description
    action_desc = str(payload.get("description", ""))
    if len(action_desc) > 2000:
        score += 0.1

    # action_type flagged as high-risk but not blocked by hard rule
    risky_actions = {"modify_config", "escalate_privileges", "bulk_update", "export_data"}
    if str(payload.get("action_type", "")).lower() in risky_actions:
        score += 0.2

    # nested depth (proxy for obfuscation)
    def _depth(obj, d=0):
        if isinstance(obj, dict):
            return max((_depth(v, d+1) for v in obj.values()), default=d)
        if isinstance(obj, list):
            return max((_depth(v, d+1) for v in obj), default=d)
        return d
    if _depth(payload) > 6:
        score += 0.15

    return min(1.0, round(score, 4))


# ── main evaluate function ────────────────────────────────────────────────────

def evaluate(proposed_json_str: str) -> PolicyResult:
    """
    Run all policy checks against the proposed JSON string.
    Returns PolicyResult with status, reason, risk_score.
    Always call this before committing an event.
    """
    # parse
    try:
        payload = json.loads(proposed_json_str)
    except json.JSONDecodeError as e:
        return PolicyResult(status="REJECTED", reason=f"Invalid JSON: {e}", risk_score=1.0)

    if not isinstance(payload, dict):
        return PolicyResult(status="REJECTED", reason="Payload must be a JSON object", risk_score=1.0)

    # payload size rule (needs raw string)
    ok, msg = _rule_max_payload_size(proposed_json_str)
    if not ok:
        return PolicyResult(status="REJECTED", reason=msg, risk_score=1.0)

    # hard rules
    for rule in HARD_RULES:
        ok, msg = rule(payload)
        if not ok:
            return PolicyResult(status="REJECTED", reason=msg, risk_score=1.0)

    # heuristic score
    risk = _heuristic_score(proposed_json_str, payload)

    # threshold: risk >= 0.75 triggers soft rejection
    if risk >= 0.75:
        return PolicyResult(
            status="REJECTED",
            reason=f"Heuristic risk score too high: {risk:.4f} (threshold 0.75)",
            risk_score=risk,
        )

    return PolicyResult(status="APPROVED", reason="All policy checks passed", risk_score=risk)
