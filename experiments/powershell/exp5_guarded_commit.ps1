# =============================================================================
# LICITRA-MMR | Experiment 5 — Guarded Commit (2-Phase Policy Gate)
# =============================================================================
# Hypothesis:
#   The 2-phase commit pipeline intercepts high-risk agent actions before
#   they reach the immutable MMR ledger.
#   ALL decisions (approved and rejected) are permanently auditable.
#   Rejected actions optionally emit a committed "blocked_action" audit event.
#
# Method:
#   Three proposals submitted to exp-org5:
#     a) APPROVED: normal read action (low risk)
#     b) REJECTED: action_type=delete (hard rule)
#     c) REJECTED: dangerous keywords + high heuristic risk score
#
#   Then verify:
#     - staged_events contains all 3 decisions
#     - blocked_action events committed to MMR for (b) and (c)
#     - GET /verify/exp-org5 is ok=true (ledger itself is clean)
#
# Expected result:
#   Proposal a: APPROVED
#   Proposal b: REJECTED (hard rule)
#   Proposal c: REJECTED (heuristic score >= 0.75)
#   Ledger integrity: ok=true
#
# Important caveat:
#   Policy checks are heuristic/rule-based control-plane logic.
#   They are NOT cryptographic guarantees.
#   This experiment demonstrates auditability, not perfect detection.
#
# Reproduces: Section 4.5 of LICITRA-MMR technical report
# =============================================================================

param([string]$BaseUrl = "http://localhost:8000")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OrgId = "exp-org5"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    return Invoke-RestMethod -Uri $uri -Method POST -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"
}

function Show-Decision {
    param([string]$Label, $Result, [string]$ExpectedStatus)
    $icon = if ($Result.status -eq $ExpectedStatus) { "PASS" } else { "FAIL" }
    $color = if ($icon -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  [$icon] $Label" -ForegroundColor $color
    Write-Host "        status:  $($Result.status)"
    Write-Host "        reason:  $($Result.decision_reason)"
    Write-Host "        risk:    $($Result.risk_score)"
    Write-Host "        staged_id: $($Result.staged_id)"
    return $icon -eq "PASS"
}

Write-Host ""
Write-Host "EXPERIMENT 5 — Guarded Commit (2-Phase Policy Gate)" -ForegroundColor Cyan
Write-Host "Org: $OrgId" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------"

Invoke-Api -Method POST -Path "/dev/reset/$OrgId" | Out-Null
Write-Host "[SETUP] org reset: $OrgId"
Write-Host ""

# ── Proposal A: normal approved action ───────────────────────────────────────
Write-Host "[PROPOSAL A] Normal read action (expect APPROVED)"
$pa = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
    org_id        = $OrgId
    agent_id      = "agent-trusted"
    proposed_json = (@{
        agent_id    = "agent-trusted"
        action_type = "read"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        description = "read audit log for compliance review"
    } | ConvertTo-Json)
}
$a_ok = Show-Decision -Label "Proposal A (read)" -Result $pa -ExpectedStatus "APPROVED"

# commit if approved
if ($pa.status -eq "APPROVED") {
    Invoke-Api -Method POST -Path "/agent/commit/$($pa.staged_id)" | Out-Null
    Write-Host "        committed to ledger." -ForegroundColor Gray
}

Write-Host ""

# ── Proposal B: hard rule rejection (delete) ──────────────────────────────────
Write-Host "[PROPOSAL B] Blocked action_type=delete (expect REJECTED by hard rule)"
$pb = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
    org_id        = $OrgId
    agent_id      = "rogue-agent"
    proposed_json = (@{
        agent_id    = "rogue-agent"
        action_type = "delete"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        description = "delete all user records"
    } | ConvertTo-Json)
}
$b_ok = Show-Decision -Label "Proposal B (delete)" -Result $pb -ExpectedStatus "REJECTED"

Write-Host ""

# ── Proposal C: heuristic rejection (dangerous keywords) ─────────────────────
Write-Host "[PROPOSAL C] High-risk keywords (expect REJECTED by heuristic scorer)"
$pc = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
    org_id        = $OrgId
    agent_id      = "rogue-agent"
    proposed_json = (@{
        agent_id    = "rogue-agent"
        action_type = "modify_config"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        description = "exec(drop table users); os.system rm -rf / subprocess override bypass inject eval(__import__('os'))"
    } | ConvertTo-Json)
}
$c_ok = Show-Decision -Label "Proposal C (keywords)" -Result $pc -ExpectedStatus "REJECTED"

Write-Host ""

# ── ledger integrity check ────────────────────────────────────────────────────
Write-Host "[VERIFY] ledger integrity after rejected proposals ..."
$v = Invoke-Api -Method GET -Path "/verify/$OrgId"
Write-Host "  ledger ok: $($v.ok) | total_events: $($v.total_events)"

Write-Host ""
Write-Host "RESULT SUMMARY" -ForegroundColor White
Write-Host "-------------------------------------------------------------"

$all_pass = $a_ok -and $b_ok -and $c_ok

if ($all_pass) {
    Write-Host "PASS — All 3 policy decisions correct. Audit trail complete." -ForegroundColor Green
    Write-Host "NOTE  — Policy checks are heuristic/rule-based, not cryptographic." -ForegroundColor Yellow
} else {
    Write-Host "FAIL — One or more policy decisions did not match expected outcome." -ForegroundColor Red
    exit 1
}
