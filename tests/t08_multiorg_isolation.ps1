. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T08 — Multi-Org Isolation"
Reset-Org "t08a"; Reset-Org "t08b"

try {
    Write-Host "  Committing 1000 events to t08a and t08b..." -ForegroundColor Gray
    $first_a = Commit-N -OrgId "t08a" -AgentId "agent-t08a" -Count 1000
    Commit-N -OrgId "t08b" -AgentId "agent-t08b" -Count 1000 | Out-Null
    $va = Invoke-Api -Method GET -Path "/verify/t08a"
    $vb = Invoke-Api -Method GET -Path "/verify/t08b"
    if ($va.ok -and $vb.ok) {
        Pass "Baseline: both orgs ok" "t08a ok=true t08b ok=true" ""
    } else {
        Fail "Baseline both ok" "t08a=$($va.ok) t08b=$($vb.ok)" "Both true"
    }
    Write-Host "  Tampering t08a event + epoch..." -ForegroundColor Gray
    Invoke-Api -Method POST -Path "/tamper/t08a/$first_a" | Out-Null
    Invoke-Api -Method POST -Path "/tamper-epoch/t08a/0" | Out-Null
    $va2 = Invoke-Api -Method GET -Path "/verify/t08a"
    $vb2 = Invoke-Api -Method GET -Path "/verify/t08b"
    if (-not $va2.ok) {
        Pass "t08a tamper detected" "ok=false bad_epoch=$($va2.bad_epoch_index)" ""
    } else {
        Fail "t08a tamper detected" "ok=true (not detected)" "ok=false"
    }
    if ($vb2.ok) {
        Pass "t08b unaffected" "ok=true epochs=$($vb2.epochs) events=$($vb2.total_events)" "Per-org isolation enforced"
    } else {
        Fail "t08b unaffected" "ok=$($vb2.ok)" "ok=true"
    }
} catch { Fail "Multi-org isolation" "Exception: $_" "t08a fail t08b ok" }
Test-Footer
