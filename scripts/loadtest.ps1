param(
  [int]$BookId = 1,
  [int]$Requests = 50
)

$Ports = @(8081, 8083, 8084)

Write-Host "== Load test =="
Write-Host "BookId=$BookId Requests=$Requests"
Write-Host "Ports=$($Ports -join ',')"
Write-Host ""

$jobs = @()

for ($i=1; $i -le $Requests; $i++) {
  $port = $Ports[$i % 3]
  $url = "http://localhost:$port/api/books/$BookId/borrow"

  $jobs += Start-Job -ScriptBlock {
    param($u, $p)
    try {
      $resp = Invoke-WebRequest -Uri $u -Method POST -UseBasicParsing
      [PSCustomObject]@{ Port=$p; Status=$resp.StatusCode; Body=$resp.Content }
    } catch {
      if ($_.Exception.Response -ne $null) {
        $status = $_.Exception.Response.StatusCode.value__
        $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
        [PSCustomObject]@{ Port=$p; Status=$status; Body=$body }
      } else {
        [PSCustomObject]@{ Port=$p; Status=-1; Body=$_.Exception.Message }
      }
    }
  } -ArgumentList $url, $port
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

$success  = ($results | Where-Object {$_.Status -eq 200}).Count
$conflict = ($results | Where-Object {$_.Status -eq 409}).Count
$other    = $Requests - $success - $conflict

Write-Host "== Résultats =="
Write-Host "Success (200):  $success"
Write-Host "Conflict (409): $conflict"
Write-Host "Other:          $other"
