cd C:\pleya-test
foreach ($d in "win-test","win-restore") {
  Copy-Item "$d\pleya_server\.env" "$d.env.keep"
  Remove-Item -Recurse -Force "$d\pleya_server\internal","$d\pleya_server\cmd"
  tar -xf src.tar -C $d
  Copy-Item "$d.env.keep" "$d\pleya_server\.env"; Remove-Item "$d.env.keep"
  (Get-Content "$d\pleya_server\Dockerfile") | Where-Object { $_ -notmatch "^# syntax=" } | Set-Content "$d\pleya_server\Dockerfile.local"
  $y = Get-Content compose.windows-test.yaml -Raw
  $y = $y -replace "(services:\r?\n  pleya-server:\r?\n)","`$1    build:`n      context: .`n      dockerfile: Dockerfile.local`n"
  Set-Content "$d\pleya_server\compose.windows-test.yaml" $y
}
foreach ($p in @(@("win-test","pleya-win-test",18832),@("win-restore","pleya-win-restore",18833))) {
  cd "C:\pleya-test\$($p[0])\pleya_server"
  $c = @("-p",$p[1],"-f","compose.yaml","-f","compose.windows-test.yaml")
  docker compose @c build --pull=false 2>&1 | Select-Object -Last 1
  docker compose @c up -d 2>&1 | Select-Object -Last 1
  for ($i=0; $i -lt 45; $i++) { try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 "http://127.0.0.1:$($p[2])/readyz"; if ($r.StatusCode -eq 200) { "$($p[1]) ready"; break } } catch {}; Start-Sleep 2 }
  docker inspect $p[1] --format "{{.Image}}"
}
docker logs pleya-win-restore 2>&1 | Select-String "Setupcode" | Select -Last 1
