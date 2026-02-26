# run_demo_big.ps1
# Commits 3000 events for org-big -> spans 3 full epochs -> verify + export

param(
    [string]$BaseUrl   = "http://localhost:8000",
    [int]   $EventCount = 3000,
    [string]$OrgId     = "org-big"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    $json = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json"
}

Write-Host "Resetting $OrgId ..." -ForegroundColor Yellow
Invoke-Api -Method POST -Path "/dev/reset/$OrgId" | Out-Null

Write-Host "Committing $EventCount events for $OrgId ..." -ForegroundColor Cyan
$start = Get-Date

for ($i = 1; $i -le $EventCount; $i++) {
    $payload = @{
        agent_id    = "agent-big"
        action_type = "write"
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        seq_hint    = $i
        description = "big demo event $i"
    } | ConvertTo-Json

    $propose = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id        = $OrgId
        agent_id      = "agent-big"
        proposed_json = $payload
    }

    if ($propose.status -eq "APPROVED") {
        Invoke-Api -Method POST -Path "/agent/commit/$($propose.staged_id)" | Out-Null
    }

    if ($i % 500 -eq 0) {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        Write-Host "  [$i / $EventCount] elapsed: $([math]::Round($elapsed,1))s" -ForegroundColor Green
    }
}

$elapsed = ((Get-Date) - $start).TotalSeconds
Write-Host "Done in $([math]::Round($elapsed,1))s" -ForegroundColor Green

$v = Invoke-Api -Method GET -Path "/verify/$OrgId"
Write-Host ""
Write-Host "Verification result:" -ForegroundColor Cyan
$v | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "Run export_artifacts.ps1 to generate evidence bundles." -ForegroundColor Yellow
