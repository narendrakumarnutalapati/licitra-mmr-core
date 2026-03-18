# Preflight: require a running server with DEV_MODE enabled
$health = Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET

Write-Host "Test suite preflight..." -ForegroundColor Yellow
Write-Host "  status      : $($health.status)" -ForegroundColor Gray
Write-Host "  block_size  : $($health.block_size)" -ForegroundColor Gray
Write-Host "  dev_mode    : $($health.dev_mode)" -ForegroundColor Gray
Write-Host "  ledger_mode : $($health.ledger_mode)" -ForegroundColor Gray

if (-not $health.dev_mode) {
    Write-Host ""
    Write-Host "FAILED: test suite requires DEV_MODE=true because it pre-resets orgs and validates DEV endpoints." -ForegroundColor Red
    exit 1
}

$allOrgs = @(
    "t02a","t02b","t02c","t02d","t03a","t03b","t04a","t04b","t04c",
    "t05a","t05b","t05c","t06a","t07a","t08a","t08b","t09a",
    "t10a","t10b","t10c"
)

Write-Host ""
Write-Host "Pre-resetting all test orgs..." -ForegroundColor Yellow
foreach ($o in $allOrgs) {
    Invoke-RestMethod -Uri "http://localhost:8000/dev/reset/$o" -Method POST | Out-Null
    Write-Host "  reset $o" -ForegroundColor Gray
}
Write-Host "Done. Starting test suite.`n" -ForegroundColor Yellow

$tests = @(
    "t01_health.ps1",
    "t02_guarded_commit.ps1",
    "t03_canonicalization.ps1",
    "t04_mmr_epoch.ps1",
    "t05_verification.ps1",
    "t06_inclusion_proofs.ps1",
    "t07_evidence_bundle.ps1",
    "t08_multiorg_isolation.ps1",
    "t09_devmode.ps1",
    "t10_determinism.ps1",
    "t11_powershell_scripts.ps1"
)

$results = @()
$start   = Get-Date

foreach ($t in $tests) {
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

    $ts = Get-Date
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $t)
    $elapsed = [math]::Round(((Get-Date) - $ts).TotalSeconds, 2)

    if ($LASTEXITCODE -eq 0) {
        $results += [PSCustomObject]@{ Test = $t; Status = "PASS"; Elapsed = $elapsed }
    } else {
        $results += [PSCustomObject]@{ Test = $t; Status = "FAIL"; Elapsed = $elapsed }
    }
}

$total  = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor White
Write-Host "  LICITRA-MMR TEST RESULTS" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor White
Write-Host ""

foreach ($r in $results) {
    $c = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host ("  [{0}]  {1,-42}  {2}s" -f $r.Status, $r.Test, $r.Elapsed) -ForegroundColor $c
}

Write-Host ""
Write-Host ("  {0} / {1} suites passed  |  total time: {2}s" -f $passed, $results.Count, $total)
Write-Host ""

if ($failed -gt 0) {
    Write-Host "  INVARIANT VIOLATION DETECTED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ALL INVARIANTS SATISFIED" -ForegroundColor Green
}