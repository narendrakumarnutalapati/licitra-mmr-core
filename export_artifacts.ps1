# export_artifacts.ps1
# Export JSON + PDF evidence bundles for all orgs into demo\

param(
    [string]$BaseUrl = "http://localhost:8000",
    [string[]]$Orgs  = @("org1", "org2", "org-big")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$demoDir = "D:\AI\licitra-mmr-core\demo"
if (-not (Test-Path $demoDir)) { New-Item -ItemType Directory $demoDir | Out-Null }

foreach ($org in $Orgs) {
    Write-Host "Exporting evidence for $org ..." -ForegroundColor Cyan

    # JSON
    try {
        $json = Invoke-RestMethod -Uri "$BaseUrl/evidence/$org" -Method GET
        $jsonPath = "$demoDir\evidence_$org.json"
        $json | ConvertTo-Json -Depth 20 | Out-File -FilePath $jsonPath -Encoding utf8
        Write-Host "  [OK] JSON -> $jsonPath" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] JSON for $org : $_" -ForegroundColor Yellow
    }

    # PDF
    try {
        $pdfPath = "$demoDir\evidence_$org.pdf"
        Invoke-WebRequest -Uri "$BaseUrl/evidence/$org/pdf" -OutFile $pdfPath
        Write-Host "  [OK] PDF  -> $pdfPath" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] PDF for $org : $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "All artifacts exported to $demoDir" -ForegroundColor Cyan
Write-Host "Files:" -ForegroundColor Cyan
Get-ChildItem $demoDir | ForEach-Object { Write-Host "  $($_.Name)" }
