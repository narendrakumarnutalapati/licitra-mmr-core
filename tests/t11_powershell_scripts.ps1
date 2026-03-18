. (Join-Path $PSScriptRoot "_common.ps1")
Test-Header "T11 — PowerShell Workflow Scripts"

$root = Split-Path -Parent $PSScriptRoot

$required = @(
    "scripts\run_server.ps1",
    "scripts\run_demo_2org.ps1",
    "scripts\run_demo_big.ps1",
    "scripts\export_artifacts.ps1",
    "scripts\run_all_experiments.ps1",
    "experiments\powershell\exp1_clean_commit.ps1",
    "experiments\powershell\exp2_event_tamper.ps1",
    "experiments\powershell\exp3_epoch_tamper.ps1",
    "experiments\powershell\exp4_multiorg_isolation.ps1",
    "experiments\powershell\exp5_guarded_commit.ps1"
)

foreach ($script in $required) {
    $path = Join-Path $root $script
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Pass "$script exists" "path=$path size=$size bytes" ""
    } else {
        Fail "$script exists" "NOT FOUND: $path" "File must be present"
    }
}

Test-Footer
