# =============================================================================
# LICITRA-MMR | Experiment 2 — Event Tamper Detection
# =============================================================================
# Hypothesis:
#   Mutating the canonical_json of any committed event is detectable.
#   SHA256(canonical_json) must equal the stored leaf_hash.
#   Any mismatch breaks verification at the epoch level.
#
# Method:
#   - Requires exp1 to have run first (exp-org1 has 1000 events)
#   - Tamper the first committed event via POST /tamper/exp-org1/{event_id}
#   - Call GET /verify/exp-org1
#
# Expected result:
#   ok=false, bad_epoch_index=0, reason contains "Leaf integrity failure"
#
# Reproduces: Section 4.2 of LICITRA-MMR technical report
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
Write-Host "EXPERIMENT 2 — Event Tamper Detection" -ForegroundColor Cyan
Write-Host "Org: $OrgId | Tamper: canonical_json mutation" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------"

# confirm org has events
$v_before = Invoke-Api -Method GET -Path "/verify/$OrgId"
if (-not $v_before.ok -or $v_before.total_events -eq 0) {
    Write-Host "[SETUP] exp-org1 has no committed events. Run exp1_clean_commit.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "[SETUP] pre-tamper verify: ok=$($v_before.ok) events=$($v_before.total_events)"

# get first event_id
$events_raw = Invoke-RestMethod -Uri "$BaseUrl/evidence/$OrgId" -Method GET
$first_event = $events_raw.last_20_events | Select-Object -Last 1
$event_id = $first_event.event_id
Write-Host "[SETUP] targeting event_id: $event_id (seq=$($first_event.seq))"

# tamper
Write-Host "[RUN]   POST /tamper/$OrgId/$event_id"
$t = Invoke-Api -Method POST -Path "/tamper/$OrgId/$event_id"
Write-Host "        action: $($t.action)"
Write-Host "        note:   $($t.note)"

# verify after tamper
Write-Host "[VERIFY] calling GET /verify/$OrgId ..."
$v = Invoke-Api -Method GET -Path "/verify/$OrgId"

Write-Host ""
Write-Host "RESULT" -ForegroundColor White
Write-Host "  ok:              $($v.ok)"
Write-Host "  bad_epoch_index: $($v.bad_epoch_index)"
Write-Host "  bad_event_id:    $($v.bad_event_id)"
Write-Host "  reason:          $($v.reason)"
Write-Host ""

if (-not $v.ok -and $v.bad_epoch_index -eq 0 -and $v.reason -like "*Leaf integrity*") {
    Write-Host "PASS — event tamper correctly detected at epoch 0." -ForegroundColor Green
} else {
    Write-Host "FAIL — tamper was not detected or wrong epoch flagged." -ForegroundColor Red
    exit 1
}
