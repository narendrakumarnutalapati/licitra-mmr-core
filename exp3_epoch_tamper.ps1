# =============================================================================
# LICITRA-MMR | Experiment 3 — Epoch Hash Tamper Detection
# =============================================================================
# Hypothesis:
#   Mutating the epoch_hash of any finalized epoch breaks the hash chain.
#   The verifier recomputes epoch_hash = SHA256(prev || mmr_root || SHA256(meta))
#   and detects any divergence from the stored value.
#
# Method:
#   - Uses a fresh org: exp-org3
#   - Commits 1000 events to finalize epoch 0
#   - Tampers epoch 0 via POST /tamper-epoch/exp-org3/0
#   - Verifies: expects ok=false, bad_epoch_index=0
#
# Expected result:
#   ok=false, bad_epoch_index=0, reason contains "epoch_hash mismatch"
#
# Reproduces: Section 4.3 of LICITRA-MMR technical report
# =============================================================================

param([string]$BaseUrl = "http://localhost:8000")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OrgId = "exp-org3"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    return Invoke-RestMethod -Uri $uri -Method POST -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"
}

Write-Host ""
Write-Host "EXPERIMENT 3 — Epoch Hash Tamper Detection" -ForegroundColor Cyan
Write-Host "Org: $OrgId | Tamper: epoch_hash overwrite" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------"

# reset and commit 1000 events
Invoke-Api -Method POST -Path "/dev/reset/$OrgId" | Out-Null
Write-Host "[SETUP] org reset: $OrgId"
Write-Host "[RUN]   committing 1000 events to finalize epoch 0 ..."

for ($i = 1; $i -le 1000; $i++) {
    $payload = @{
        agent_id    = "agent-exp3"
        action_type = "write"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        seq_hint    = $i
        description = "epoch tamper experiment event $i"
    } | ConvertTo-Json

    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id        = $OrgId
        agent_id      = "agent-exp3"
        proposed_json = $payload
    }
    Invoke-Api -Method POST -Path "/agent/commit/$($p.staged_id)" | Out-Null
    if ($i % 200 -eq 0) { Write-Host "       $i / 1000 committed" }
}

$v_before = Invoke-Api -Method GET -Path "/verify/$OrgId"
Write-Host "[SETUP] pre-tamper: ok=$($v_before.ok) epochs=$($v_before.epochs)"

# tamper epoch 0
Write-Host "[RUN]   POST /tamper-epoch/$OrgId/0"
$t = Invoke-Api -Method POST -Path "/tamper-epoch/$OrgId/0"
Write-Host "        original:    $($t.original)"
Write-Host "        replacement: $($t.replacement)"

# verify
Write-Host "[VERIFY] calling GET /verify/$OrgId ..."
$v = Invoke-Api -Method GET -Path "/verify/$OrgId"

Write-Host ""
Write-Host "RESULT" -ForegroundColor White
Write-Host "  ok:              $($v.ok)"
Write-Host "  bad_epoch_index: $($v.bad_epoch_index)"
Write-Host "  reason:          $($v.reason)"
Write-Host ""

if (-not $v.ok -and $v.bad_epoch_index -eq 0) {
    Write-Host "PASS — epoch hash tamper correctly detected at epoch 0." -ForegroundColor Green
} else {
    Write-Host "FAIL — epoch tamper was not detected." -ForegroundColor Red
    exit 1
}
