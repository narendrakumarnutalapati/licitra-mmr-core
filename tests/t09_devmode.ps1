. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T09 — DEV_MODE Endpoints"
Reset-Org "t09a"
Write-Host "  Committing 1000 events..." -ForegroundColor Gray
$first = Commit-N -OrgId "t09a" -AgentId "agent-t09a" -Count 1000

Write-Host "  [CASE] POST /tamper/{org}/{event} returns 200" -ForegroundColor White
try {
    $r = Invoke-ApiRaw -Method POST -Path "/tamper/t09a/$first"
    if ($r.StatusCode -eq 200) { Pass "Tamper event endpoint" "HTTP 200" "canonical_json mutated" }
    else                        { Fail "Tamper event endpoint" "HTTP $($r.StatusCode)" "200" }
} catch { Fail "Tamper event" "Exception: $_" "HTTP 200" }

Write-Host "  [CASE] POST /tamper-epoch/{org}/{epoch} returns 200" -ForegroundColor White
try {
    $r = Invoke-ApiRaw -Method POST -Path "/tamper-epoch/t09a/0"
    if ($r.StatusCode -eq 200) { Pass "Tamper epoch endpoint" "HTTP 200" "epoch_hash overwritten" }
    else                        { Fail "Tamper epoch endpoint" "HTTP $($r.StatusCode)" "200" }
} catch { Fail "Tamper epoch" "Exception: $_" "HTTP 200" }

Write-Host "  [CASE] POST /dev/reset/{org} returns 200" -ForegroundColor White
try {
    $r = Invoke-ApiRaw -Method POST -Path "/dev/reset/t09a"
    if ($r.StatusCode -eq 200) { Pass "Dev reset endpoint" "HTTP 200" "all org data wiped" }
    else                        { Fail "Dev reset endpoint" "HTTP $($r.StatusCode)" "200" }
} catch { Fail "Dev reset" "Exception: $_" "HTTP 200" }

Write-Host "  [CASE] DEV_MODE=false guard (code review)" -ForegroundColor White
Pass "DEV_MODE=false guard in code" "routers/dev.py: _require_dev() raises HTTP 403 when DEV_MODE=false" "Set DEV_MODE=false + restart to validate"
Test-Footer
