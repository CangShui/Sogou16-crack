$ErrorActionPreference='Continue'
$root='C:\Windows\Temp\netaudit2'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$status="$root\status.txt"
$connCsv="$root\conns.csv"
$dnsLog="$root\dns.log"
$procLog="$root\procs.log"
function W($m){ "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $status -Append -Encoding UTF8 }
Remove-Item $status,$connCsv,$dnsLog,$procLog,"$root\DONE.txt" -ErrorAction SilentlyContinue
Remove-Item "$root\*.etl" -ErrorAction SilentlyContinue
W "ORCH2 START"
$sw = New-Object System.IO.StreamWriter($connCsv,$false,(New-Object System.Text.UTF8Encoding($false)))
$sw.WriteLine('ts,pid,process,local,remote,state')
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Sogou|SGTool|sogou|Pinyin|QQPinyin' } | ForEach-Object { "$(Get-Date -Format 'HH:mm:ss')|$($_.ProcessId)|$($_.Name)|$($_.ExecutablePath)|$($_.CommandLine)" } | Out-File $procLog -Append -Encoding UTF8
pktmon stop 2>&1 | Out-Null
pktmon filter remove * 2>&1 | Out-Null
pktmon filter add SYNs -t TCP SYN 2>&1 | Out-File $status -Append -Encoding UTF8
pktmon filter add UDPs -t UDP 2>&1 | Out-File $status -Append -Encoding UTF8
pktmon start --capture --pkt-size 512 --file-name "$root\cap.etl" --file-size 256 --log-mode multi-file 2>&1 | Out-File $status -Append -Encoding UTF8
W "PKTMON STARTED"
$end=(Get-Date).AddMinutes(240)
$pidCache=@{}
$n=0
$lastDns=(Get-Date).AddMinutes(-10)
$missPkt=0
while((Get-Date) -lt $end){
  $n++
  $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $conns = netstat -ano 2>$null
  foreach($c in $conns){
    if($c -match '^\s*TCP\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\S+)\s+(\d+)\s*$'){ $local=$matches[1]; $raddr=$matches[2]; $rport=$matches[3]; $state=$matches[4]; $procId=[int]$matches[5] }
    elseif($c -match '^\s*TCP\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\S+)\s+(\d+)\s*$'){ $local=$matches[1]; $raddr=$matches[3]; $rport=$matches[4]; $state=$matches[5]; $procId=[int]$matches[6] }
    else { continue }
    if($raddr -match '^(127\.|0\.0\.0\.0|224\.|239\.|255\.)'){ continue }
    if($raddr -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){ continue }
    if($state -eq 'BOUND'){ continue }
    if($procId -eq 0){ $pn='System/Idle' }
    elseif($pidCache.ContainsKey($procId)){ $pn=$pidCache[$procId] }
    else {
      $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if($p){ $pn=$p.ProcessName }
      else { $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue; $pn = if($ci){ $ci.Name } else { "pid$procId" } }
      $pidCache[$procId]=$pn
    }
    $pnEsc = $pn -replace ',','_'
    $sw.WriteLine("$ts,$procId,$pnEsc,$local,$raddr`:$rport,$state")
  }
  $sw.Flush()
  if(((Get-Date)-$lastDns).TotalMinutes -ge 5){
    $lastDns=Get-Date
    Get-DnsClientCache -ErrorAction SilentlyContinue | ForEach-Object { "$(Get-Date -Format 'HH:mm:ss')|$($_.Entry)|$($_.Data)|$($_.Status)" } | Out-File $dnsLog -Append -Encoding UTF8
    Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Sogou|SGTool|sogou|Pinyin|QQPinyin' } | ForEach-Object { "$(Get-Date -Format 'HH:mm:ss')|$($_.ProcessId)|$($_.Name)|$($_.ExecutablePath)" } | Out-File $procLog -Append -Encoding UTF8
  }
  if($n % 60 -eq 0){
    $st = pktmon status 2>&1 | Out-String
    if($st -notmatch 'PktMon'){ $missPkt++; pktmon start --capture --pkt-size 512 --file-name "$root\cap.etl" --file-size 256 --log-mode multi-file 2>&1 | Out-File $status -Append -Encoding UTF8; W "PKTMON RESTARTED miss=$missPkt" }
    $sz = (Get-ChildItem "$root\*.etl" -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    W "sample $n etlBytes=$sz"
  }
  Start-Sleep 5
}
$sw.Flush(); $sw.Close()
pktmon stop 2>&1 | Out-File $status -Append -Encoding UTF8
Start-Sleep 3
W "PKTMON STOPPED"
Get-ChildItem "$root\*.etl" | ForEach-Object { "ETL $($_.Name) $($_.Length)" } | Out-File $status -Append -Encoding UTF8
W "ORCH2 DONE"
'DONE' | Out-File "$root\DONE.txt" -Encoding UTF8
