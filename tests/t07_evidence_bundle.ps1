. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T07 — Evidence Bundle"
Reset-Org "t07a"
Write-Host "  Committing 1000 events..." -ForegroundColor Gray
Commit-N -OrgId "t07a" -AgentId "agent-t07a" -Count 1000 | Out-Null

Write-Host "  [CASE] JSON evidence bundle structure and fields" -ForegroundColor White
try {
    $b = Invoke-Api -Method GET -Path "/evidence/t07a"
    $s = $b.summary
    if ($s.org_id -eq "t07a")             { Pass "summary.org_id"         "org_id=$($s.org_id)" "" }
    else                                   { Fail "summary.org_id"         "$($s.org_id)" "t07a" }
    if ($s.ledger_version -eq "mmr-v0.1") { Pass "summary.ledger_version" "$($s.ledger_version)" "" }
    else                                   { Fail "summary.ledger_version" "$($s.ledger_version)" "mmr-v0.1" }
    if ($s.hash_alg -eq "SHA256")         { Pass "summary.hash_alg"       "$($s.hash_alg)" "" }
    else                                   { Fail "summary.hash_alg"       "$($s.hash_alg)" "SHA256" }
    if ($s.block_size -eq 1000)           { Pass "summary.block_size"     "$($s.block_size)" "" }
    else                                   { Fail "summary.block_size"     "$($s.block_size)" "1000" }
    if ($s.bundle_sha256.Length -eq 64)   { Pass "summary.bundle_sha256"  "$($s.bundle_sha256.Substring(0,16))..." "self-checksum" }
    else                                   { Fail "summary.bundle_sha256"  "$($s.bundle_sha256)" "64-char hex" }
    if ($s.ok)                            { Pass "summary.ok = true"      "ok=true" "" }
    else                                   { Fail "summary.ok"             "ok=$($s.ok)" "true" }
    if ($b.last_20_events.Count -gt 0)    { Pass "last_20_events present" "count=$($b.last_20_events.Count)" "" }
    else                                   { Fail "last_20_events"         "0" "> 0" }
    if ($b.last_20_staged.Count -gt 0)    { Pass "last_20_staged present" "count=$($b.last_20_staged.Count)" "audit trail" }
    else                                   { Fail "last_20_staged"         "0" "> 0" }
    if ($b.proof_example -ne $null)       { Pass "proof_example present"  "epoch=$($b.proof_example.epoch_id) steps=$($b.proof_example.proof_path.Count)" "" }
    else                                   { Fail "proof_example"          "null" "non-null" }
    if ($b.epochs.Count -gt 0)            { Pass "epochs list present"    "count=$($b.epochs.Count)" "" }
    else                                   { Fail "epochs list"            "0" "> 0" }
} catch { Fail "JSON bundle" "Exception: $_" "Full bundle structure" }

Write-Host ""
Write-Host "  [CASE] PDF bundle returns HTTP 200" -ForegroundColor White
try {
    $raw = Invoke-ApiRaw -Method GET -Path "/evidence/t07a/pdf"
    if ($raw.StatusCode -eq 200) {
        Pass "PDF bundle HTTP 200" "HTTP 200 application/pdf" "summary+epochs+proof+staged"
    } else {
        Fail "PDF bundle HTTP 200" "HTTP $($raw.StatusCode)" "200"
    }
} catch { Fail "PDF bundle" "Exception: $_" "HTTP 200" }
Test-Footer
