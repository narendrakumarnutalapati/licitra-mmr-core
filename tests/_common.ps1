# _common.ps1 — source this file in every test script
# Usage: . (Join-Path $PSScriptRoot "_common.ps1")

$BASE = "http://localhost:8000"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BASE$Path"
    if ($Method -eq "GET") { return Invoke-RestMethod -Uri $uri -Method GET }
    return Invoke-RestMethod -Uri $uri -Method POST `
        -Body ($Body | ConvertTo-Json -Depth 10) -ContentType "application/json"
}

function Invoke-ApiRaw {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BASE$Path"
    try {
        if ($Method -eq "GET") {
            $r = Invoke-WebRequest -Uri $uri -Method GET -ErrorAction Stop
        } else {
            $r = Invoke-WebRequest -Uri $uri -Method POST `
                -Body ($Body | ConvertTo-Json -Depth 10) `
                -ContentType "application/json" -ErrorAction Stop
        }
        return @{ StatusCode = $r.StatusCode; Body = $r.Content }
    } catch {
        return @{ StatusCode = $_.Exception.Response.StatusCode.value__; Body = $_.ToString() }
    }
}

function Make-Payload {
    param([string]$AgentId, [string]$Action = "write", [string]$Desc = "test", [int]$Seq = 0)
    return (@{
        agent_id    = $AgentId
        action_type = $Action
        timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        seq_hint    = $Seq
        description = $Desc
    } | ConvertTo-Json -Compress -Depth 5)
}

function Propose-And-Commit {
    param([string]$OrgId, [string]$AgentId, [string]$PayloadJson)
    $p = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
        org_id        = $OrgId
        agent_id      = $AgentId
        proposed_json = $PayloadJson
    }
    if ($p.status -ne "APPROVED") { throw "Proposal not approved: $($p.decision_reason)" }
    return Invoke-Api -Method POST -Path "/agent/commit/$($p.staged_id)"
}

function Commit-N {
    param([string]$OrgId, [string]$AgentId, [int]$Count)
    $first = $null
    for ($i = 1; $i -le $Count; $i++) {
        $c = Propose-And-Commit -OrgId $OrgId -AgentId $AgentId `
                -PayloadJson (Make-Payload $AgentId "write" "event $i" $i)
        if ($i -eq 1) { $first = $c.event_id }
        if ($i % 500 -eq 0) { Write-Host "         $i / $Count committed" -ForegroundColor Gray }
    }
    return $first
}

function Reset-Org {
    param([string]$OrgId)
    try { Invoke-Api -Method POST -Path "/dev/reset/$OrgId" | Out-Null } catch {}
}

function Pass {
    param([string]$Check, [string]$Observed, [string]$Notes = "")
    Write-Host "  [PASS] $Check" -ForegroundColor Green
    Write-Host "         Observed : $Observed"
    if ($Notes) { Write-Host "         Notes    : $Notes" -ForegroundColor Gray }
    $global:T_PASS++
}

function Fail {
    param([string]$Check, [string]$Observed, [string]$Expected, [string]$Notes = "")
    Write-Host "  [FAIL] $Check" -ForegroundColor Red
    Write-Host "         Observed : $Observed"
    Write-Host "         Expected : $Expected"
    if ($Notes) { Write-Host "         Notes    : $Notes" -ForegroundColor Yellow }
    $global:T_FAIL++
}

function Test-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Footer {
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    if ($global:T_FAIL -eq 0) {
        Write-Host "  RESULT : PASS ($global:T_PASS checks passed)" -ForegroundColor Green
    } else {
        Write-Host "  RESULT : FAIL ($global:T_PASS passed / $global:T_FAIL failed)" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

$global:T_PASS = 0
$global:T_FAIL = 0
