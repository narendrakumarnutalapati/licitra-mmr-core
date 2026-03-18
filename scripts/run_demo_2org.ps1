# run_demo_2org.ps1
# Experiment: org1 tampered, org2 clean -> org2 remains ok
# Runs 5 experiments:
#   1) Clean: org1 + org2 commit 1000 events each -> both verify ok
#   2) Event tamper: mutate org1 event -> verify fails at bad_epoch_index
#   3) Epoch tamper: mutate org1 epoch -> verify fails
#   4) Multi-org isolation: org2 still verifies ok after org1 tampered
#   5) Guarded commit: propose hijacked action -> rejected; blocked_action committed

param(
    [string]$BaseUrl   = "http://localhost:8000",
    [int]   $EventCount = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Api {
    param([string]$Method, [string]$Path, [hashtable]$Body = @{})
    $uri = "$BaseUrl$Path"
    if ($Method -eq "GET") {
        return Invoke-RestMethod -Uri $uri -Method GET
    }
    $json = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri $uri -Method POST -Body $json -ContentType "application/json"
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$Msg) Write-Host "[OK]  $Msg" -ForegroundColor Green }
function Write-Fail { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Yellow }

# ── reset both orgs ───────────────────────────────────────────────────────────
Write-Header "RESET org1 + org2"
Invoke-Api -Method POST -Path "/dev/reset/org1" | Out-Null
Invoke-Api -Method POST -Path "/dev/reset/org2" | Out-Null
Write-Ok "Both orgs reset"

# ── helper: commit N events for an org ───────────────────────────────────────
function Commit-Events {
    param([string]$OrgId, [int]$Count)
    Write-Info "Committing $Count events for $OrgId ..."
    $first_event_id = $null
    for ($i = 1; $i -le $Count; $i++) {
        $payload = @{
            agent_id    = "agent-demo"
            action_type = "write"
            timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            seq_hint    = $i
            org         = $OrgId
            description = "demo event $i for $OrgId"
        } | ConvertTo-Json

        $propose = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
            org_id        = $OrgId
            agent_id      = "agent-demo"
            proposed_json = $payload
        }

        if ($propose.status -ne "APPROVED") {
            Write-Fail "Proposal rejected for $OrgId event $i : $($propose.decision_reason)"
            continue
        }

        $committed = Invoke-Api -Method POST -Path "/agent/commit/$($propose.staged_id)"

        if ($i -eq 1) { $first_event_id = $committed.event_id }

        if ($i % 100 -eq 0) {
            Write-Info "  $OrgId -> $i events committed (epoch=$($committed.epoch_id) seq=$($committed.seq))"
        }
    }
    return $first_event_id
}

# ── EXPERIMENT 1: clean commit 1000 events each ───────────────────────────────
Write-Header "EXPERIMENT 1 — Clean commit $EventCount events per org"
$org1_first = Commit-Events -OrgId "org1" -Count $EventCount
$org2_first = Commit-Events -OrgId "org2" -Count $EventCount

$v1 = Invoke-Api -Method GET -Path "/verify/org1"
$v2 = Invoke-Api -Method GET -Path "/verify/org2"

if ($v1.ok) { Write-Ok "org1 verify: OK (epochs=$($v1.epochs) events=$($v1.total_events))" }
else         { Write-Fail "org1 verify FAILED: $($v1.reason)" }

if ($v2.ok) { Write-Ok "org2 verify: OK (epochs=$($v2.epochs) events=$($v2.total_events))" }
else         { Write-Fail "org2 verify FAILED: $($v2.reason)" }

# ── EXPERIMENT 2: tamper org1 event ──────────────────────────────────────────
Write-Header "EXPERIMENT 2 — Event tamper on org1"
Write-Info "Tampering with org1 event: $org1_first"
Invoke-Api -Method POST -Path "/tamper/org1/$org1_first" | Out-Null

$v1t = Invoke-Api -Method GET -Path "/verify/org1"
if (-not $v1t.ok) { Write-Ok "org1 tamper detected: bad_epoch_index=$($v1t.bad_epoch_index) reason=$($v1t.reason)" }
else               { Write-Fail "org1 tamper NOT detected (unexpected)" }

# ── EXPERIMENT 3: tamper org1 epoch ──────────────────────────────────────────
Write-Header "EXPERIMENT 3 — Epoch tamper on org1 epoch 0"
Invoke-Api -Method POST -Path "/tamper-epoch/org1/0" | Out-Null

$v1e = Invoke-Api -Method GET -Path "/verify/org1"
if (-not $v1e.ok) { Write-Ok "org1 epoch tamper detected: bad_epoch_index=$($v1e.bad_epoch_index)" }
else               { Write-Fail "org1 epoch tamper NOT detected (unexpected)" }

# ── EXPERIMENT 4: multi-org isolation ────────────────────────────────────────
Write-Header "EXPERIMENT 4 — Multi-org isolation (org2 must still be OK)"
$v2iso = Invoke-Api -Method GET -Path "/verify/org2"
if ($v2iso.ok) { Write-Ok "org2 unaffected by org1 tampering: OK" }
else            { Write-Fail "org2 unexpectedly failed: $($v2iso.reason)" }

# ── EXPERIMENT 5: guarded commit (hijack rejection) ───────────────────────────
Write-Header "EXPERIMENT 5 — Guarded commit: hijacked action rejected"

$hijack_payload = @{
    agent_id    = "rogue-agent"
    action_type = "delete"
    timestamp   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    description = "drop table users; exec(rm -rf /)"
} | ConvertTo-Json

$hijack = Invoke-Api -Method POST -Path "/agent/propose" -Body @{
    org_id        = "org2"
    agent_id      = "rogue-agent"
    proposed_json = $hijack_payload
}

if ($hijack.status -eq "REJECTED") {
    Write-Ok "Hijacked action REJECTED: $($hijack.decision_reason)"
    Write-Info "Risk score: $($hijack.risk_score)"
    Write-Info "Staged audit record ID: $($hijack.staged_id)"
} else {
    Write-Fail "Hijacked action was NOT rejected (status=$($hijack.status))"
}

# ── summary ───────────────────────────────────────────────────────────────────
Write-Header "DEMO COMPLETE"
Write-Ok "All 5 experiments finished."
Write-Info "Run export_artifacts.ps1 to generate JSON + PDF evidence bundles."
