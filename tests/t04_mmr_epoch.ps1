. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T04 — MMR + Epoch Behavior"
Reset-Org "t04a"; Reset-Org "t04b"; Reset-Org "t04c"

Write-Host "  [CASE] Exactly 1000 events -> epoch finalized" -ForegroundColor White
try {
    Write-Host "         Committing 1000 events..." -ForegroundColor Gray
    Commit-N -OrgId "t04a" -AgentId "agent-t04a" -Count 1000 | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t04a"
    $e = Invoke-Api -Method GET -Path "/evidence/t04a"
    $epoch = $e.epochs | Select-Object -First 1
    if ($v.ok -and $v.epochs -eq 1 -and $v.total_events -eq 1000) {
        Pass "Epoch finalized at BLOCK_SIZE=1000" "ok=true epochs=1 total_events=1000" "epoch row persisted"
    } else {
        Fail "Epoch finalized" "ok=$($v.ok) epochs=$($v.epochs) events=$($v.total_events)" "ok=true epochs=1 events=1000"
    }
    if ($epoch.mmr_root.Length -eq 64 -and $epoch.epoch_hash.Length -eq 64) {
        Pass "mmr_root and epoch_hash valid" "mmr_root=$($epoch.mmr_root.Substring(0,16))... epoch_hash=$($epoch.epoch_hash.Substring(0,16))..." "64-char hex"
    } else {
        Fail "mmr_root and epoch_hash valid" "lengths wrong" "Both 64-char hex"
    }
    if ($epoch.prev_epoch_hash -eq ("00" * 32)) {
        Pass "Genesis prev_epoch_hash is 00*32" "prev=$($epoch.prev_epoch_hash.Substring(0,16))..." "epoch_id=0 genesis sentinel"
    } else {
        Fail "Genesis prev_epoch_hash" "prev=$($epoch.prev_epoch_hash)" "64 zero hex"
    }
} catch { Fail "Exact BLOCK_SIZE epoch" "Exception: $_" "epoch finalized at 1000" }

Write-Host ""
Write-Host "  [CASE] 42 events -> no epoch finalized, verify ok" -ForegroundColor White
try {
    Commit-N -OrgId "t04b" -AgentId "agent-t04b" -Count 42 | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t04b"
    $e = Invoke-Api -Method GET -Path "/evidence/t04b"
    if ($v.ok -and $e.epochs.Count -eq 0) {
        Pass "Partial epoch: no finalization, verify ok" "ok=true finalized_epochs=0 committed=42" "Epoch only finalizes at BLOCK_SIZE"
    } else {
        Fail "Partial epoch" "ok=$($v.ok) epochs=$($e.epochs.Count)" "ok=true epochs=0"
    }
} catch { Fail "Partial epoch" "Exception: $_" "ok=true no epoch row" }

Write-Host ""
Write-Host "  [CASE] 2500 events -> 2 full epochs + partial, chain intact" -ForegroundColor White
try {
    Write-Host "         Committing 2500 events (~2 min)..." -ForegroundColor Gray
    Commit-N -OrgId "t04c" -AgentId "agent-t04c" -Count 2500 | Out-Null
    $v = Invoke-Api -Method GET -Path "/verify/t04c"
    $e = Invoke-Api -Method GET -Path "/evidence/t04c"
    $epochs = $e.epochs
    if ($v.ok -and $epochs.Count -eq 2) {
        Pass "2 epochs finalized from 2500 events" "ok=true finalized=2 verified=$($v.total_events)" "epoch0+epoch1 finalized, partial open"
    } else {
        Fail "2 epochs from 2500" "ok=$($v.ok) epochs=$($epochs.Count)" "ok=true 2 finalized"
    }
    if ($epochs.Count -ge 2 -and $epochs[1].prev_epoch_hash -eq $epochs[0].epoch_hash) {
        Pass "prev_epoch_hash chain intact" "epoch[1].prev == epoch[0].hash confirmed" "append-only chain"
    } else {
        Fail "Chain intact" "link broken or < 2 epochs" "epoch[1].prev == epoch[0].hash"
    }
} catch { Fail "Multi-epoch chain" "Exception: $_" "2 epochs + chain" }
Test-Footer
