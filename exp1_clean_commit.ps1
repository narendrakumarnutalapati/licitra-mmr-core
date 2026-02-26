# =============================================================================
# LICITRA-MMR | Experiment 1 — Clean Commit
# =============================================================================
# Hypothesis:
#   1000 events committed via 2-phase pipeline produce a valid, verifiable
#   epoch with a correct MMR root and epoch hash chain.
#
# Method:
#   - Reset org: exp-org1
#   - Propose + commit 1000 events via POST /agent/propose + /agent/commit
#   - Call GET /verify/exp-org1 with MMR recompute enabled
#
# Expected result:
#   ok=true, epochs=1, total_events=1000
#
# Reproduces: Section 4.1 of LICITRA-MMR technical report
# =============================================================================

param([string]$BaseUrl = "http://localhost:8000")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OrgId = "exp-org1"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    return Invoke-RestMethod -Uri $uri -Method POST -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"
}

Write-Host ""
Write-Host "EXPERIMENT 1 — Clean Commit" -ForegroundColor Cyan
Write-Host "Org: $OrgId | Events: 1000 | Block size: 1000" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------"

# reset
Invoke-Api -Method POST -Path "/dev/reset/$OrgId" | Out-Null
Write-Host "[SETUP] org reset: $OrgId"

# commit 1000 events
Write-Host "[RUN]   committing 1000 events ..."
$start = Get-Date
for ($i = 1; $i -le 1000; $i++) {
    $payload = @{
        agent_id    = "agent-exp1"
        action_type = "write"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        seq_hint    = $i
        description = "clean commit experiment event $i"
    } | ConvertTo-Json

    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id        = $OrgId
        agent_id      = "agent-exp1"
        proposed_json = $payload
    }
    if ($p.status -ne "APPROVED") {
        Write-Host "[FAIL] Event $i rejected: $($p.decision_reason)" -ForegroundColor Red
        exit 1
    }
    Invoke-Api -Method POST -Path "/agent/commit/$($p.staged_id)" | Out-Null

    if ($i % 200 -eq 0) {
        Write-Host "       $i / 1000 events committed"
    }
}
$elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)

# verify
Write-Host "[VERIFY] calling GET /verify/$OrgId ..."
$v = Invoke-Api -Method GET -Path "/verify/$OrgId"

Write-Host ""
Write-Host "RESULT" -ForegroundColor White
Write-Host "  ok:           $($v.ok)"
Write-Host "  epochs:       $($v.epochs)"
Write-Host "  total_events: $($v.total_events)"
Write-Host "  last_epoch_hash: $($v.last_epoch_hash)"
Write-Host "  elapsed:      $($elapsed)s"
Write-Host ""

if ($v.ok -and $v.epochs -eq 1 -and $v.total_events -eq 1000) {
    Write-Host "PASS — epoch hash chain verified, MMR root valid, 1000 events committed." -ForegroundColor Green
} else {
    Write-Host "FAIL — unexpected result." -ForegroundColor Red
    exit 1
}
