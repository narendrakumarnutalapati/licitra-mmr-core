. (Join-Path $PSScriptRoot "_common.ps1")
Test-Header "T11 — PowerShell Workflow Scripts"
$root = "D:\AI\licitra-mmr-core"
$required = @(
    "run_server.ps1","run_demo_2org.ps1","run_demo_big.ps1",
    "export_artifacts.ps1","run_all_experiments.ps1",
    "exp1_clean_commit.ps1","exp2_event_tamper.ps1",
    "exp3_epoch_tamper.ps1","exp4_multiorg_isolation.ps1",
    "exp5_guarded_commit.ps1"
)
foreach ($script in $required) {
    $path = "$root\$script"
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Pass "$script exists" "path=$path size=$size bytes" ""
    } else {
        Fail "$script exists" "NOT FOUND: $path" "File must be present"
    }
}
Test-Footer
