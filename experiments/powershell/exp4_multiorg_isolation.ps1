# =============================================================================
# LICITRA-MMR | Experiment 4 — Multi-Org Isolation
# =============================================================================
# Hypothesis:
#   Per-org ledger isolation is strictly enforced.
#   Tampering with org A's committed history has zero effect on org B.
#   Each org maintains a fully independent MMR and epoch hash chain.
#
# Method:
#   - Commit 1000 events each to exp-org4a and exp-org4b
#   - Verify both: expect ok=true
#   - Tamper exp-org4a event + epoch
#   - Verify exp-org4a: expect ok=false
#   - Verify exp-org4b: expect ok=true (unaffected)
#
# Expected result:
#   exp-org4a: ok=false (tampered)
#   exp-org4b: ok=true  (isolated, unaffected)
#
# Reproduces: Section 4.4 of LICITRA-MMR technical report
# =============================================================================

param([string]$BaseUrl = "http://localhost:8000")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OrgA = "exp-org4a"
$OrgB = "exp-org4b"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    return Invoke-RestMethod -Uri $uri -Method POST -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"
}

function Commit-1000 {
    param([string]$OrgId, [string]$AgentId)
    $first_event_id = $null
    for ($i = 1; $i -le 1000; $i++) {
        $payload = @{
            agent_id    = $AgentId
            action_type = "write"
            timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            seq_hint    = $i
            description = "isolation experiment event $i for $OrgId"
        } | ConvertTo-Json

        $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
            org_id        = $OrgId
            agent_id      = $AgentId
            proposed_json = $payload
        }
        $c = Invoke-Api -Method POST -Path "/agent/commit/$($p.staged_id)"

        if ($i -eq 1) { $first_event_id = $c.event_id }

        if ($i % 200 -eq 0) {
            Write-Host "       $i / 1000 committed ($OrgId)"
        }
    }
    return $first_event_id
}

Write-Host ""
Write-Host "EXPERIMENT 4 — Multi-Org Isolation" -ForegroundColor Cyan
Write-Host "OrgA: $OrgA | OrgB: $OrgB" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------"

Invoke-Api -Method POST -Path "/dev/reset/$OrgA" | Out-Null
Invoke-Api -Method POST -Path "/dev/reset/$OrgB" | Out-Null
Write-Host "[SETUP] both orgs reset"

Write-Host "[RUN]   committing 1000 events to $OrgA ..."
$orgA_first = Commit-1000 -OrgId $OrgA -AgentId "agent-4a"

Write-Host "[RUN]   committing 1000 events to $OrgB ..."
Commit-1000 -OrgId $OrgB -AgentId "agent-4b" | Out-Null

# baseline verify
$va = Invoke-Api -Method GET -Path "/verify/$OrgA"
$vb = Invoke-Api -Method GET -Path "/verify/$OrgB"
Write-Host "[SETUP] baseline: $OrgA ok=$($va.ok) epochs=$($va.epochs) | $OrgB ok=$($vb.ok) epochs=$($vb.epochs)"

# tamper orgA — event + epoch
Write-Host "[RUN]   tampering $OrgA event: $orgA_first"
Invoke-Api -Method POST -Path "/tamper/$OrgA/$orgA_first" | Out-Null

Write-Host "[RUN]   tampering $OrgA epoch 0"
Invoke-Api -Method POST -Path "/tamper-epoch/$OrgA/0" | Out-Null

# verify both after tamper
Write-Host "[VERIFY] calling GET /verify for both orgs ..."
$va2 = Invoke-Api -Method GET -Path "/verify/$OrgA"
$vb2 = Invoke-Api -Method GET -Path "/verify/$OrgB"

Write-Host ""
Write-Host "RESULT" -ForegroundColor White
Write-Host "  $OrgA ok: $($va2.ok) | bad_epoch_index: $($va2.bad_epoch_index) | reason: $($va2.reason)"
Write-Host "  $OrgB ok: $($vb2.ok) | epochs: $($vb2.epochs) | total_events: $($vb2.total_events)"
Write-Host ""

$orgA_fail = (-not $va2.ok)
$orgB_ok   = ($vb2.ok)

if ($orgA_fail -and $orgB_ok) {
    Write-Host "PASS — $OrgA tamper detected; $OrgB fully isolated and unaffected." -ForegroundColor Green
} else {
    if (-not $orgA_fail) { Write-Host "FAIL — $OrgA tamper not detected." -ForegroundColor Red }
    if (-not $orgB_ok)   { Write-Host "FAIL — $OrgB incorrectly affected by $OrgA tampering." -ForegroundColor Red }
    exit 1
}
