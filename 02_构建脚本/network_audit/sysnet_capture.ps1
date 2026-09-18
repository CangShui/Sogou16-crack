# ============================================================================
#  sysnet_capture.ps1 — 全系统出站网络连接抓取器（可配置时长）
# ----------------------------------------------------------------------------
#  用法:
#    powershell -NoProfile -ExecutionPolicy Bypass -File sysnet_capture.ps1
#      -Minutes 60            # 抓取时长（分钟），默认 30
#      -Interval 10           # 采样间隔（秒），默认 10
#      -OutDir C:\audit       # 输出目录，默认脚本所在目录\netout
#      -Name myrun            # 本次运行名（前缀），默认 sysnet_<时间戳>
#   例如超长抓取（12 小时）:
#    powershell -NoProfile -ExecutionPolicy Bypass -File sysnet_capture.ps1 -Minutes 720 -Interval 15
#
#  说明:
#   - 扫描全部 TCP 公网连接（跳过 127/10/192.168/172.16-31 内网段）
#   - 每次采样实时把原始行追加到 <Name>.raw.csv
#   - 结束自动生成汇总 <Name>.summary.csv（进程 | 远程 | 次数 | 状态 | 首次 | 末次）
#   - Ctrl+C 可提前结束；结束前同样生成汇总
#   - 不写 hosts、不碰防火墙、不依赖任何系统环境改动
# ============================================================================
param(
  [int]$Minutes = 30,
  [int]$Interval = 10,
  [string]$OutDir = '',
  [string]$Name = ''
)
$ErrorActionPreference = 'Continue'

if(-not $OutDir){ $OutDir = Join-Path $PSScriptRoot 'netout' }
if(-not $Name){ $Name = 'sysnet_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$raw   = Join-Path $OutDir "$Name.raw.csv"
$summary = Join-Path $OutDir "$Name.summary.csv"

# UTF-8 无 BOM 写入器（CSV 给 pandas/Excel 读，必须无 BOM 且表头第一行）
$rawWriter = New-Object System.IO.StreamWriter($raw, $false, (New-Object System.Text.UTF8Encoding($false)))
$rawWriter.WriteLine('sample_time,local_addr,remote_addr,state,pid,process_name')

$end = (Get-Date).AddMinutes($Minutes)
$samples = 0
$agg = @{}   # "proc|ip:port" -> count/states/first/last
$startTs = Get-Date -Format 'HH:mm:ss'
"=== capture start $startTs duration=${Minutes}min interval=${Interval}s out=$OutDir ===" | Out-File $summary -Encoding UTF8
Write-Host "capture start $startTs, ${Minutes} min, every ${Interval}s -> $raw" -ForegroundColor Green

while($true){
  $samples++
  $ts = Get-Date -Format 'HH:mm:ss'
  $conns = netstat -ano 2>$null
  $pidCache = @{}
  foreach($c in $conns){
    $m = $null
    if($c -match 'TCP\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\S+)\s+(\d+)\s*$'){
      $local=$matches[1]; $raddr=$matches[2]; $rport=[int]$matches[3]; $state=$matches[4]; $procId=[int]$matches[5]
    }
    elseif($c -match 'TCP\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\d+\.\d+\.\d+\.\d+):(\d+)\s+(\S+)\s+(\d+)\s*$'){
      $local=$matches[1]; $raddr=$matches[3]; $rport=[int]$matches[4]; $state=$matches[5]; $procId=[int]$matches[6]
    }
    else { continue }
    if($raddr -match '^(127\.|0\.0\.0\.0|224\.|239\.)' -or $raddr -eq '::' -or $raddr -eq '::1'){ continue }
    if($raddr -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){ continue }
    if($state -eq 'BOUND'){ continue }
    $pn = $null
    if($procId -eq 0){ $pn = 'System/Idle' }
    elseif($pidCache.ContainsKey($procId)){ $pn = $pidCache[$procId] }
    else {
      $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if($p){ $pn = $p.ProcessName }
      else {
        # 进程可能已退出或权限不足，用 CIM 兜底查一次
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
        $pn = if($ci){ $ci.Name -replace '\.exe$','' } else { "pid$procId" }
      }
      $pidCache[$procId] = $pn
    }
    # 实时写原始 CSV（进程名里逗号转义）
    $esc = $pn -replace ',','_'
    $rawWriter.WriteLine("$ts,$local,$raddr`:$rport,$state,$procId,$esc")
    $key = "$pn|$raddr`:$rport"
    if(-not $agg.ContainsKey($key)){
      $agg[$key] = @{ count=1; states=@($state); first=$ts; last=$ts; proc=$pn }
    } else {
      $agg[$key].count++
      $agg[$key].last = $ts
      if($agg[$key].states -notcontains $state){ $agg[$key].states += $state }
    }
  }
  Write-Host ("  sample {0} {1}  flows={2}" -f $samples,$ts,$agg.Count)
  if($Minutes -gt 0 -and (Get-Date) -ge $end){ break }
  Start-Sleep $Interval
}

$endTs = Get-Date -Format 'HH:mm:ss'
$rawWriter.Flush(); $rawWriter.Close()
"=== capture end $endTs samples=$samples uniqueFlows=$($agg.Count) ===" | Out-File $summary -Append -Encoding UTF8
"process`tremote`tcount`tstates`tfirst`tlast" | Out-File $summary -Append -Encoding UTF8
foreach($k in ($agg.Keys | Sort-Object)){
  $e = $agg[$k]
  "$($e.proc)`t$k`t$($e.count)`t$($e.states -join '/')`t$($e.first)`t$($e.last)" | Out-File $summary -Append -Encoding UTF8
}
Write-Host "capture done -> $raw  summary -> $summary" -ForegroundColor Green
