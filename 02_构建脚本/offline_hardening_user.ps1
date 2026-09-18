# offline_hardening_user.ps1 - user-context HKCU hardening (run via RunOnce as interactive user)
# SYSTEM-run hardening cannot write the interactive user's HKCU; this script runs at first logon
# to disable the IME-core read paths: SmartInfo push, cloud candidate, telemetry, update.
$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\SogouOffline\hv_user.log'
New-Item -ItemType Directory -Force -Path 'C:\ProgramData\SogouOffline' | Out-Null
function W($m){ "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $log -Append -Encoding UTF8 }
W "=== hardening user start (user=$env:USERNAME) ==="

if($env:USERNAME -ieq 'SYSTEM' -or [Environment]::UserName -ieq 'SYSTEM'){
  W "ABORT: running as SYSTEM, must run as interactive user"
  exit 0
}

$keys = @(
  'HKCU:\Software\SogouInput',
  'HKCU:\Software\SogouInput.store.user'
)
foreach($k in $keys){ New-Item -Force -Path $k | Out-Null }

$hkcu = 'HKCU:\Software\SogouInput'
foreach($n in @('SendUserExperience','UpUseBT','UpdateInterval','IsUdpate',
                'EnableCloudInput','CloudCand','EnableSearchCand','EnablePinyinCloud',
                'ImeHint')){
  Set-ItemProperty $hkcu -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Set-ItemProperty $hkcu -Name 'LastUpdateTime' -Value '' -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $hkcu -Name 'PatchFlag' -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $hkcu -Name 'Version' -Value '16.8.0.4914' -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $hkcu -Name 'Region' -Value '1111_pinyin_guanwang_16.8' -Type String -ErrorAction SilentlyContinue

# SmartInfo push (IME core 读 HKCU，浏览器搜索场景建立 wss push 长连接的开关)
foreach($n in @('SmartInfoSearchOption','SmartInfoWebOption','SmartInfoShoppingOption',
                'SmartInfoSystemOption','SmartInfoOfficeOption','SmartInfoIMOption',
                'CustomSmartInfoSearchEngine','EnableSearchSugg','EnableSugg',
                'SmartInfoEnable')){
  Set-ItemProperty $hkcu -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue
}

$store = 'HKCU:\Software\SogouInput.store.user'
Set-ItemProperty $store -Name 'stats_report' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $store -Name 'TodayRunTimes' -Value 999 -Type DWord -ErrorAction SilentlyContinue
$beacon = "$store\large_model\ichat\beacon"
New-Item -Force -Path $beacon | Out-Null
foreach($n in @('pz_config','switch','enable')){ Set-ItemProperty $beacon -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue }
$upd = "$store\update"
New-Item -Force -Path $upd | Out-Null
Set-ItemProperty $upd -Name 'aipic_dict' -Value 0 -Type DWord -ErrorAction SilentlyContinue

W "=== hardening user done ==="