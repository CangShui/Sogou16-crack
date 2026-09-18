# offline_hardening.ps1 - native offline hardening
# 只在搜狗自己的注册表键内操作，不动 hosts / 防火墙 / DNS / 系统网络。
# 要点:
#   1) 同时写 32 位视图 (SOFTWARE\WOW6432Node\SogouInput) 和 64 位视图 (SOFTWARE\SogouInput)，
#      否则 SogouCloud/SGTool 读 HKLM\Software\SogouInput 会报"读注册表失败"。
#   2) 用 .NET SetValue('') 正确设置注册表默认值（安装路径），而不是 Set-ItemProperty '(default)'。
$ErrorActionPreference = "Continue"
$log = "C:\ProgramData\SogouOffline\hv16.log"
New-Item -ItemType Directory -Force -Path "C:\ProgramData\SogouOffline" | Out-Null
function W($m){ "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $log -Append -Encoding UTF8 }
W "=== hardening start (user=$env:USERNAME) ==="

# 杀残留 daemon（它们即使能起也无法联网；杀掉避免弹错误框）
foreach($n in @("SogouCloud","PinyinUp","SGDownload","userNetSchedule","SogouSvc","SogouExe","crashrpt","SGWebRender","SGBizLauncher","SGSmartAssistant","SGWangzai","SGWizard","screencapture","sgfeedbackhelper","SGIGuideHelper","SogouToolkits","SGKaomoji")){
  Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep 1
W "daemons stopped"

function Set-RegValue($hive, $key, $name, $value, $kind){
  $rk = $hive.OpenSubKey($key, $true)
  if(-not $rk){ $rk = $hive.CreateSubKey($key) }
  $rk.SetValue($name, $value, $kind)
  $rk.Close()
}

# SogouInput 完整官方值（32 位 + 64 位两个视图都写）
$dwords = @{
  'SendUserExperience'=0; 'UpUseBT'=0; 'UpdateInterval'=0; 'IsUdpate'=0;
  'EnableCloudInput'=0; 'CloudCand'=0; 'EnableSearchCand'=0; 'EnablePinyinCloud'=0;
  'ImeHint'=0; 'PatchFlag'=1;
}
$strings = @{
  'LastUpdateTime'='';
  'StartMenuFolder'='搜狗输入法';
  'Version'='16.8.0.4914';
  'Region'='1111_pinyin_guanwang_16.8';
  'VersionType'='Final';
  'HQBOVersion'='16.8.0.4914';
  'MIVersion'='16.8.0.4914';
  'CSVersion'='16.8.0.4914';
  'HSign'='T2Xv6ScvwzOzde6fd9K0PUBi/e9k8Ih0d9CZbDBgPUbSYX5caDB3DMR22AtxwSJOyvVBIW8ZNIr0IpS6TeowDA==';
  'BizVersion'='8.9';
  'BizPath'='C:\Program Files (x86)\SogouInput\Components\biz_center\1.0.0.3315\biz_helper.exe';
  'SExtVersion'='1.0.0.5';
  'cert_installed'='1';
  'certr3_installed'='1';
}
foreach($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)){
  $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
  $key = 'SOFTWARE\SogouInput'
  foreach($n in $dwords.Keys){ Set-RegValue $hive $key $n $dwords[$n] ([Microsoft.Win32.RegistryValueKind]::DWord) }
  foreach($n in $strings.Keys){ Set-RegValue $hive $key $n $strings[$n] ([Microsoft.Win32.RegistryValueKind]::String) }
  Set-RegValue $hive $key '' 'C:\Program Files (x86)\SogouInput' ([Microsoft.Win32.RegistryValueKind]::String)
  # SmartInfo 推送关闭
  foreach($n in @('SmartInfoSearchOption','SmartInfoWebOption','SmartInfoShoppingOption','SmartInfoSystemOption','SmartInfoOfficeOption','SmartInfoIMOption','CustomSmartInfoSearchEngine','EnableSearchSugg','EnableSugg','SmartInfoEnable')){
    Set-RegValue $hive $key $n 0 ([Microsoft.Win32.RegistryValueKind]::DWord)
  }
  $hive.Close()
}
W "HKLM SogouInput (32+64 views) installed-path default + full official values set"

# HKCU
$hkcu = 'HKCU:\Software\SogouInput'
New-Item -Path $hkcu -Force | Out-Null
foreach($n in $dwords.Keys){ Set-ItemProperty $hkcu -Name $n -Value $dwords[$n] -Type DWord -ErrorAction SilentlyContinue }
Set-ItemProperty $hkcu -Name 'LastUpdateTime' -Value '' -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $hkcu -Name 'Version' -Value '16.8.0.4914' -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $hkcu -Name 'Region' -Value '1111_pinyin_guanwang_16.8' -Type String -ErrorAction SilentlyContinue
foreach($n in @('SmartInfoSearchOption','SmartInfoWebOption','SmartInfoShoppingOption','SmartInfoSystemOption','SmartInfoOfficeOption','SmartInfoIMOption','CustomSmartInfoSearchEngine','EnableSearchSugg','EnableSugg','SmartInfoEnable')){
  Set-ItemProperty $hkcu -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
$store = 'HKCU:\Software\SogouInput.store.user'
New-Item -Path $store -Force | Out-Null
Set-ItemProperty $store -Name 'stats_report' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $store -Name 'TodayRunTimes' -Value 999 -Type DWord -ErrorAction SilentlyContinue
$beacon = "$store\large_model\ichat\beacon"
New-Item -Path $beacon -Force | Out-Null
foreach($n in @('pz_config','switch','enable')){ Set-ItemProperty $beacon -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue }
$upd = "$store\update"
New-Item -Path $upd -Force | Out-Null
Set-ItemProperty $upd -Name 'aipic_dict' -Value 0 -Type DWord -ErrorAction SilentlyContinue
W "HKCU telemetry/cloud/SmartInfo/update off"

# 服务 / 计划任务 / Run 清理（保留 SogouImeBroker 自启）
sc.exe config SogouSvc start= disabled | Out-Null
sc.exe stop SogouSvc | Out-Null
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Sogou|sogou' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
$runKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')
foreach($rk in $runKeys){
  if(Test-Path $rk){
    $ip=Get-ItemProperty $rk -ErrorAction SilentlyContinue
    if($ip){
      $ip.GetType().GetProperties() | ForEach-Object {
        $nm=$_.Name; if($nm -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')){return}
        $v=$ip.$nm
        if($v -is [string] -and $v -match 'Sogou|sogou' -and $nm -notmatch 'SogouImeBroker'){
          Remove-ItemProperty -Path $rk -Name $nm -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }
}
W "svc/task/run cleaned (SogouImeBroker Run kept)"

# 重启 broker
Get-Process SogouImeLoader,SogouImeBroker -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
Start-Process 'C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe' -ArgumentList '-RegServer' -ErrorAction SilentlyContinue
# SogouCloud.exe 已被替换为立即退出的 1KB 合法空 EXE（入口即 ExitProcess(0)），
# IME 核心仍会尝试拉起它，但进程瞬间正常退出，不再产生资源占用，也不崩溃。
# 不需要额外注册表配置；不要把 SogouCloud 加入任何自启。

W "broker restarted"
W "=== hardening done ==="

