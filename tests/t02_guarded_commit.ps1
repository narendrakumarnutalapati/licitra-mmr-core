. (Join-Path $PSScriptRoot "_common.ps1")
Test-Header "T02 — Guarded Commit Pipeline"
Reset-Org "t02a"; Reset-Org "t02b"; Reset-Org "t02c"; Reset-Org "t02d"

Write-Host "  [CASE] Happy path: valid propose -> APPROVED -> commit" -ForegroundColor White
try {
    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id="t02a"; agent_id="agent-test"
        proposed_json=(Make-Payload "agent-test" "write" "happy path event")
    }
    if ($p.status -eq "APPROVED") {
        Pass "Propose returns APPROVED" "status=APPROVED risk=$($p.risk_score) staged_id=$($p.staged_id)" "staged_events row written"
    } else {
        Fail "Propose returns APPROVED" "status=$($p.status) reason=$($p.decision_reason)" "APPROVED"
    }
    $c = Invoke-Api -Method POST -Path "/agent/commit/$($p.staged_id)"
    if ($c.event_id -and $c.seq -eq 1 -and $c.leaf_hash.Length -eq 64) {
        Pass "Commit returns event row" "event_id=$($c.event_id.Substring(0,8))... seq=$($c.seq) epoch=$($c.epoch_id) leaf=$($c.leaf_hash.Substring(0,16))..." "events row + mmr_nodes updated"
    } else {
        Fail "Commit returns event row" "$($c | ConvertTo-Json)" "event_id seq=1 leaf_hash(64)"
    }
} catch { Fail "Happy path" "Exception: $_" "APPROVED + committed event" }

Write-Host ""
Write-Host "  [CASE] Reject path: policy violation -> REJECTED" -ForegroundColor White
try {
    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id="t02b"; agent_id="rogue"
        proposed_json=(Make-Payload "rogue" "delete" "drop all records")
    }
    if ($p.status -eq "REJECTED" -and $p.decision_reason) {
        Pass "Reject path: REJECTED with reason" "status=REJECTED reason=$($p.decision_reason) risk=$($p.risk_score)" "staged_events row written"
    } else {
        Fail "Reject path: REJECTED" "status=$($p.status)" "REJECTED + decision_reason"
    }
} catch { Fail "Reject path" "Exception: $_" "REJECTED staged event" }

Write-Host ""
Write-Host "  [CASE] Commit without approval -> HTTP 4xx" -ForegroundColor White
try {
    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id="t02c"; agent_id="rogue"
        proposed_json=(Make-Payload "rogue" "delete" "rejected proposal")
    }
    $raw = Invoke-ApiRaw -Method POST -Path "/agent/commit/$($p.staged_id)"
    if ($raw.StatusCode -ge 400) {
        Pass "Commit on REJECTED returns 4xx" "HTTP $($raw.StatusCode)" "No events row, no MMR update"
    } else {
        Fail "Commit on REJECTED returns 4xx" "HTTP $($raw.StatusCode)" "HTTP 4xx"
    }
} catch { Fail "Commit without approval" "Exception: $_" "HTTP 4xx" }

Write-Host ""
Write-Host "  [CASE] Uniqueness: distinct event_ids + monotonic seq" -ForegroundColor White
try {
    $c1 = Propose-And-Commit "t02d" "agent-test" (Make-Payload "agent-test" "write" "first")
    $c2 = Propose-And-Commit "t02d" "agent-test" (Make-Payload "agent-test" "write" "second")
    if ($c1.event_id -ne $c2.event_id) {
        Pass "Distinct event_ids enforced" "id1=$($c1.event_id.Substring(0,8))... id2=$($c2.event_id.Substring(0,8))..." "uq_events_org_event"
    } else {
        Fail "Distinct event_ids" "Both identical" "Distinct UUIDs"
    }
    if ($c1.seq -eq 1 -and $c2.seq -eq 2) {
        Pass "Monotonic seq DB-assigned" "seq_1=$($c1.seq) seq_2=$($c2.seq)" "uq_events_org_seq"
    } else {
        Fail "Monotonic seq" "seq_1=$($c1.seq) seq_2=$($c2.seq)" "1 then 2"
    }
} catch { Fail "Uniqueness" "Exception: $_" "Distinct IDs + monotonic seq" }
Test-Footer
