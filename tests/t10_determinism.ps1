. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T10 — Determinism & Constraints"
Reset-Org "t10a"; Reset-Org "t10b"; Reset-Org "t10c"

Write-Host "  [CASE] Per-org monotonic seq enforced by DB" -ForegroundColor White
try {
    Commit-N -OrgId "t10a" -AgentId "agent-t10a" -Count 5 | Out-Null
    $seqs = (Invoke-Api -Method GET -Path "/evidence/t10a").last_20_events |
            ForEach-Object { $_.seq } | Sort-Object
    $mono = $true
    for ($i = 1; $i -lt $seqs.Count; $i++) {
        if ($seqs[$i] -le $seqs[$i-1]) { $mono = $false }
    }
    if ($mono -and $seqs.Count -eq 5) {
        Pass "Seq strictly monotonic" "seqs=$($seqs -join ', ')" "DB-assigned, no in-app counters"
    } else {
        Fail "Seq monotonic" "seqs=$($seqs -join ', ') mono=$mono" "1,2,3,4,5"
    }
} catch { Fail "Monotonic seq" "Exception: $_" "Strictly increasing" }

Write-Host ""
Write-Host "  [CASE] Deterministic canonicalization" -ForegroundColor White
try {
    # Same logical payload, different key order — both are valid proposals
    $payload_a = '{"action_type":"read","agent_id":"agent-canon","description":"determinism test","seq_hint":1,"timestamp":"2026-01-01T00:00:00Z"}'
    $payload_b = '{"timestamp":"2026-01-01T00:00:00Z","seq_hint":1,"agent_id":"agent-canon","description":"determinism test","action_type":"read"}'
    $ca = Propose-And-Commit "t10b" "agent-canon" $payload_a
    $cb = Propose-And-Commit "t10b" "agent-canon" $payload_b
    if ($ca.leaf_hash -eq $cb.leaf_hash) {
        Pass "Canon deterministic" "leaf_hash=$($ca.leaf_hash)" "sorted-key JSON same SHA256 always"
    } else {
        Fail "Canon deterministic" "a=$($ca.leaf_hash.Substring(0,16))... b=$($cb.leaf_hash.Substring(0,16))..." "Identical"
    }
} catch { Fail "Canonical determinism" "Exception: $_" "Identical leaf_hash" }

Write-Host ""
Write-Host "  [CASE] Epoch hash deterministic across verify calls" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    Commit-N -OrgId "t10c" -AgentId "agent-t10c" -Count 1000 | Out-Null
    $v1 = Invoke-Api -Method GET -Path "/verify/t10c"
    $v2 = Invoke-Api -Method GET -Path "/verify/t10c"
    if ($v1.ok -and $v2.ok -and $v1.last_epoch_hash -eq $v2.last_epoch_hash) {
        Pass "Epoch hash deterministic" "hash=$($v1.last_epoch_hash.Substring(0,16))... identical both calls" "SHA256 fully deterministic"
    } else {
        Fail "Epoch hash deterministic" "v1=$($v1.last_epoch_hash) v2=$($v2.last_epoch_hash)" "Identical"
    }
} catch { Fail "Epoch hash determinism" "Exception: $_" "Same hash on re-verify" }
Test-Footer
