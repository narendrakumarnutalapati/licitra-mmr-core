. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T03 — Canonicalization + Hashing"
Reset-Org "t03a"; Reset-Org "t03b"

Write-Host "  [CASE] Same JSON different key order -> identical leaf_hash" -ForegroundColor White
try {
    $payload_a = '{"action_type":"read","agent_id":"agent-canon","description":"canon test","seq_hint":1,"timestamp":"2026-01-01T00:00:00Z"}'
    $payload_b = '{"timestamp":"2026-01-01T00:00:00Z","seq_hint":1,"agent_id":"agent-canon","description":"canon test","action_type":"read"}'
    $ca = Propose-And-Commit "t03a" "agent-canon" $payload_a
    $cb = Propose-And-Commit "t03a" "agent-canon" $payload_b
    if ($ca.leaf_hash -eq $cb.leaf_hash) {
        Pass "Canonical stability: identical leaf_hash" "leaf_hash=$($ca.leaf_hash)" "SHA256(sorted canonical JSON) is order-independent"
    } else {
        Fail "Canonical stability" "hash_a=$($ca.leaf_hash.Substring(0,16))... hash_b=$($cb.leaf_hash.Substring(0,16))..." "Identical"
    }
} catch { Fail "Canonical stability" "Exception: $_" "Identical leaf_hash" }

Write-Host ""
Write-Host "  [CASE] Tamper canonical_json -> verify detects SHA256 mismatch" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    $first = Commit-N -OrgId "t03b" -AgentId "agent-t03b" -Count 1000
    $vb = Invoke-Api -Method GET -Path "/verify/t03b"
    if ($vb.ok) { Pass "Pre-tamper verify ok" "ok=true epochs=$($vb.epochs)" "" }
    else        { Fail "Pre-tamper verify ok" "ok=$($vb.ok)" "ok=true" }
    Invoke-Api -Method POST -Path "/tamper/t03b/$first" | Out-Null
    $va = Invoke-Api -Method GET -Path "/verify/t03b"
    if (-not $va.ok -and $va.reason -like "*Leaf integrity*") {
        Pass "Post-tamper verify fails" "ok=false bad_epoch=$($va.bad_epoch_index) reason=$($va.reason.Substring(0,70))..." "SHA256 mismatch detected"
    } else {
        Fail "Post-tamper verify fails" "ok=$($va.ok) reason=$($va.reason)" "ok=false Leaf integrity"
    }
} catch { Fail "Tamper hash mismatch" "Exception: $_" "verify fails after mutation" }
Test-Footer
