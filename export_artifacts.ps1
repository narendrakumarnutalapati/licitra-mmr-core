#!/usr/bin/env pwsh
# export_artifacts.ps1
# Exports evidence bundles for all experiment orgs + demo orgs
# Outputs to ./demo/ folder

param([string]$BaseUrl = "http://localhost:8000")

$OutputDir = Join-Path $PSScriptRoot "demo"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

function Export-OrgEvidence {
    param(
        [string]$OrgId,
        [string]$Label,
        [string]$Filename
    )

    Write-Host "Exporting evidence for $OrgId ($Label) ..."

    # Export JSON evidence bundle
    try {
        $json = Invoke-RestMethod "$BaseUrl/evidence/$OrgId"
        $jsonPath = Join-Path $OutputDir "$Filename.json"
        $json | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8
        Write-Host "  [OK] JSON -> $jsonPath"
    } catch {
        Write-Host "  [SKIP] $OrgId not found or no events -- skipping JSON"
    }

    # Export PDF evidence bundle
    try {
        $pdfPath = Join-Path $OutputDir "$Filename.pdf"
        $bytes = Invoke-WebRequest "$BaseUrl/evidence/$OrgId/pdf"
        [System.IO.File]::WriteAllBytes($pdfPath, $bytes.Content)
        Write-Host "  [OK] PDF  -> $pdfPath"
    } catch {
        Write-Host "  [SKIP] $OrgId PDF not available -- skipping PDF"
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host " LICITRA-MMR Evidence Bundle Export"
Write-Host "============================================"
Write-Host ""

# --- EXPERIMENT ORGS (S01-S05) ---
Write-Host "--- Experiment Evidence Bundles ---"
Export-OrgEvidence -OrgId "exp-org1"  -Label "Clean Commit + Tamper Detection" -Filename "S01_S02_exp_org1"
Export-OrgEvidence -OrgId "exp-org3"  -Label "Epoch Hash Tamper"               -Filename "S03_exp_org3"
Export-OrgEvidence -OrgId "exp-org4a" -Label "Multi-Org Isolation (tampered)"  -Filename "S04_exp_org4a"
Export-OrgEvidence -OrgId "exp-org4b" -Label "Multi-Org Isolation (clean)"     -Filename "S04_exp_org4b"
Export-OrgEvidence -OrgId "exp-org5"  -Label "Guarded Commit"                  -Filename "S05_exp_org5"

Write-Host ""

# --- DEMO ORGS (original) ---
Write-Host "--- Demo Evidence Bundles ---"
Export-OrgEvidence -OrgId "org1"    -Label "Demo Org 1"   -Filename "evidence_org1"
Export-OrgEvidence -OrgId "org2"    -Label "Demo Org 2"   -Filename "evidence_org2"
Export-OrgEvidence -OrgId "org-big" -Label "Demo Org Big" -Filename "evidence_org-big"

Write-Host ""
Write-Host "============================================"
Write-Host " All artifacts exported to: $OutputDir"
Write-Host "============================================"
Write-Host "Files:"
Get-ChildItem $OutputDir | ForEach-Object { Write-Host "  $($_.Name)" }
