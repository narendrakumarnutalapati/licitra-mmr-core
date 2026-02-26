# =============================================================================
# LICITRA-MMR | run_all_experiments.ps1
# Runs all 5 experiments in sequence. Use for CI or full demo.
# Each experiment is independently reproducible as a standalone script.
# =============================================================================

param([string]$BaseUrl = "http://localhost:8000")

$scripts = @(
    "exp1_clean_commit.ps1",
    "exp2_event_tamper.ps1",
    "exp3_epoch_tamper.ps1",
    "exp4_multiorg_isolation.ps1",
    "exp5_guarded_commit.ps1"
)

$results = @()
$total_start = Get-Date

foreach ($script in $scripts) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor DarkCyan
    Write-Host "  Running: $script" -ForegroundColor DarkCyan
    Write-Host "================================================================" -ForegroundColor DarkCyan

    $start = Get-Date
    try {
        & ".\$script" -BaseUrl $BaseUrl
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
        $results += [PSCustomObject]@{ Script = $script; Status = "PASS"; Elapsed = $elapsed }
    } catch {
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 2)
        $results += [PSCustomObject]@{ Script = $script; Status = "FAIL"; Elapsed = $elapsed }
        Write-Host "FAILED: $script" -ForegroundColor Red
    }
}

$total_elapsed = [math]::Round(((Get-Date) - $total_start).TotalSeconds, 2)

Write-Host ""
Write-Host "================================================================" -ForegroundColor White
Write-Host "  EXPERIMENT SUITE RESULTS" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White

foreach ($r in $results) {
    $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host ("  [{0}]  {1,-40} {2}s" -f $r.Status, $r.Script, $r.Elapsed) -ForegroundColor $color
}

Write-Host ""
$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
Write-Host "  $passed / $($results.Count) experiments passed | total time: $($total_elapsed)s" -ForegroundColor White

if ($failed -gt 0) { exit 1 }
