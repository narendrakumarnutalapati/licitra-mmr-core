. D:\AI\licitra-mmr-core\tests\_common.ps1
Test-Header "T01 — Health & Wiring"
try {
    $h = Invoke-Api -Method GET -Path "/health"
    if ($h.status -eq "ok" -and $h.service -eq "licitra-mmr") {
        Pass "GET /health returns ok" "status=$($h.status) service=$($h.service) version=$($h.version)" "DB reachable, tables initialized"
    } else {
        Fail "GET /health returns ok" "$($h | ConvertTo-Json)" "status=ok service=licitra-mmr"
    }
} catch { Fail "GET /health" "Exception: $_" "HTTP 200 ok body" }
Test-Footer
