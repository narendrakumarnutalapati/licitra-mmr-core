. (Join-Path $PSScriptRoot "_common.ps1")
Test-Header "T05 — Verification"
Reset-Org "t05a"; Reset-Org "t05b"; Reset-Org "t05c"

Write-Host "  [CASE] Clean verify on 1000 events" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    Commit-N -OrgId "t05a" -AgentId "agent-t05a" -Count 1000 | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t05a"
    if ($v.ok -and $v.total_events -eq 1000) {
        Pass "Clean verify ok" "ok=true epochs=$($v.epochs) events=$($v.total_events) hash=$($v.last_epoch_hash.Substring(0,16))..." ""
    } else {
        Fail "Clean verify ok" "ok=$($v.ok) reason=$($v.reason)" "ok=true total_events=1000"
    }
} catch { Fail "Clean verify" "Exception: $_" "ok=true" }

Write-Host ""
Write-Host "  [CASE] Event tamper -> verify fails" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    $first = Commit-N -OrgId "t05b" -AgentId "agent-t05b" -Count 1000
    Invoke-Api -Method POST -Path "/tamper/t05b/$first" | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t05b"
    if (-not $v.ok -and $null -ne $v.bad_epoch_index) {
        Pass "Event tamper detected" "ok=false bad_epoch=$($v.bad_epoch_index) reason=$($v.reason.Substring(0,70))..." ""
    } else {
        Fail "Event tamper detected" "ok=$($v.ok)" "ok=false + bad_epoch_index"
    }
} catch { Fail "Event tamper verify" "Exception: $_" "ok=false bad_epoch_index" }

Write-Host ""
Write-Host "  [CASE] Epoch hash tamper -> verify fails at bad_epoch_index=0" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    Commit-N -OrgId "t05c" -AgentId "agent-t05c" -Count 1000 | Out-Null
    Invoke-Api -Method POST -Path "/tamper-epoch/t05c/0" | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t05c"
    if (-not $v.ok -and $v.bad_epoch_index -eq 0) {
        Pass "Epoch tamper detected" "ok=false bad_epoch_index=0 reason=$($v.reason)" ""
    } else {
        Fail "Epoch tamper detected" "ok=$($v.ok) bad_epoch=$($v.bad_epoch_index)" "ok=false bad_epoch_index=0"
    }
} catch { Fail "Epoch tamper verify" "Exception: $_" "ok=false bad_epoch_index=0" }
Test-Footer
