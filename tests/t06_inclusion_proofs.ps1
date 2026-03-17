. (Join-Path $PSScriptRoot "_common.ps1")
Test-Header "T06 — Inclusion Proofs"
Reset-Org "t06a"

Write-Host "  [CASE] Valid inclusion proof for committed event" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    Commit-N -OrgId "t06a" -AgentId "agent-t06a" -Count 1000 | Out-Null
    $bundle = Invoke-Api -Method GET -Path "/evidence/t06a"
    $sample = $bundle.last_20_events | Select-Object -First 1
    $proof  = Invoke-Api -Method GET -Path "/proof/t06a/$($sample.event_id)"
    if ($proof.leaf_hash.Length -eq 64)  { Pass "leaf_hash present (64 hex)"  "leaf_hash=$($proof.leaf_hash)" "" }
    else                                  { Fail "leaf_hash present"           "$($proof.leaf_hash)" "64-char hex" }
    if ($proof.mmr_root.Length -eq 64)   { Pass "mmr_root present (64 hex)"   "mmr_root=$($proof.mmr_root.Substring(0,16))..." "" }
    else                                  { Fail "mmr_root present"            "$($proof.mmr_root)" "64-char hex" }
    if ($proof.proof_path -ne $null)     { Pass "proof_path present"          "steps=$($proof.proof_path.Count)" "{hash,side} steps" }
    else                                  { Fail "proof_path present"          "null" "non-null list" }
    if ($proof.epoch_hash.Length -eq 64) { Pass "epoch_hash present (64 hex)" "epoch_hash=$($proof.epoch_hash.Substring(0,16))..." "" }
    else                                  { Fail "epoch_hash present"          "$($proof.epoch_hash)" "64-char hex" }
    if ($proof.leaf_hash -eq $sample.leaf_hash) {
        Pass "leaf_hash matches events table" "proof.leaf_hash == evidence.leaf_hash" ""
    } else {
        Fail "leaf_hash consistent" "proof=$($proof.leaf_hash) evidence=$($sample.leaf_hash)" "Equal"
    }
} catch { Fail "Valid proof" "Exception: $_" "proof with all fields" }

Write-Host ""
Write-Host "  [CASE] Non-existent event -> 404" -ForegroundColor White
try {
    $raw = Invoke-ApiRaw -Method GET -Path "/proof/t06a/does-not-exist-000000000"
    if ($raw.StatusCode -eq 404) {
        Pass "Non-existent event returns 404" "HTTP 404" "clear error, no crash"
    } else {
        Fail "Non-existent event 404" "HTTP $($raw.StatusCode)" "HTTP 404"
    }
} catch { Fail "Non-existent proof 404" "Exception: $_" "HTTP 404" }
Test-Footer
