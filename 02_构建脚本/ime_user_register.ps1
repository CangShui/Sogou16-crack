# ime_user_register.ps1 — 当前交互用户的搜狗 IME 激活（必须由该用户上下文执行，不能是 SYSTEM）
# 作用：语言列表加入 zh-Hans-CN + 搜狗 TIP；UserProfile 键搜狗=1 微软拼音=0；TSF Enable；InputMethodOverride；Preload
$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\SogouOffline\ime_user_register.log'
New-Item -ItemType Directory -Force -Path 'C:\ProgramData\SogouOffline' | Out-Null
function W($m){ "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File $log -Append -Encoding UTF8 }
W "=== ime_user_register start (user=$env:USERNAME) ==="

$sgCLSID = '{E7EA138E-69F8-11D7-A6EA-00065B844310}'
$sgProf  = '{E7EA138F-69F8-11D7-A6EA-00065B844311}'
$msCLSID = '{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}'
$msProf  = '{FA550B04-5AD7-411F-A5AC-CA038EC515D7}'
$sgTip   = "0804:$sgCLSID$sgProf"
$msTip   = "0804:$msCLSID$msProf"

# ---- 0) 拒绝在 SYSTEM 下运行（用户级注册无意义）----
if($env:USERNAME -ieq 'SYSTEM' -or [Environment]::UserName -ieq 'SYSTEM'){
  W "ABORT: running as SYSTEM, must run as interactive user"
  exit 0
}

# ---- 1) 语言列表：加入 zh-Hans-CN（en-US 保留），确保 zh 语言存在 ----
try {
  $list = Get-WinUserLanguageList
  $hasZh = $list | Where-Object { $_.LanguageTag -like 'zh*' } | Select-Object -First 1
  if(-not $hasZh){
    $newList = New-WinUserLanguageList en-US
    $zh = New-WinUserLanguageList zh-CN
    $newList += $zh
    Set-WinUserLanguageList $newList -Force | Out-Null
    W "added zh-CN to language list"
  } else {
    W "zh already in list: $($hasZh.LanguageTag)"
  }
} catch { W "langlist err: $_" }

# ---- 2) 注册表直写（权威生效手段，规避 Set-WinUserLanguageList 重置为微软拼音）----
$upZh = "HKCU:\Control Panel\International\User Profile\zh-Hans-CN"
# zh-CN 与 zh-Hans-CN 两种标签都处理
foreach($tag in @('zh-Hans-CN','zh-CN')){
  $k = "HKCU:\Control Panel\International\User Profile\$tag"
  if(Test-Path $k){
    # 启用搜狗
    New-ItemProperty -LiteralPath $k -Name $sgTip -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    # 禁用微软拼音
    if($tag -eq 'zh-Hans-CN'){
      New-ItemProperty -LiteralPath $k -Name $msTip -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    }
    W "wrote $k : sg=1 ms=0"
  }
}
# 若两个 tag 都不存在，尝试创建 zh-Hans-CN（由 Set-WinUserLanguageList 已创建）
if(-not (Test-Path $upZh)){
  New-Item -Force -Path $upZh | Out-Null
  New-ItemProperty -LiteralPath $upZh -Name $sgTip -Value 1 -PropertyType DWord -Force | Out-Null
  W "created zh-Hans-CN with sg=1"
}

# ---- 3) HKCU TSF LanguageProfile Enable ----
$kSg = "HKCU:\Software\Microsoft\CTF\TIP\$sgCLSID\LanguageProfile\0x00000804\$sgProf"
New-Item -Force -Path $kSg | Out-Null
New-ItemProperty -LiteralPath $kSg -Name 'Enable' -Value 1 -PropertyType DWord -Force | Out-Null
$kMs = "HKCU:\Software\Microsoft\CTF\TIP\$msCLSID\LanguageProfile\0x00000804\$msProf"
if(Test-Path $kMs){ New-ItemProperty -LiteralPath $kMs -Name 'Enable' -Value 0 -PropertyType DWord -Force | Out-Null }
W "TSF enable: sg=1 ms=0"

# ---- 4) InputMethodOverride（新窗口默认中文=搜狗）----
$up = 'HKCU:\Control Panel\International\User Profile'
New-ItemProperty -LiteralPath $up -Name 'InputMethodOverride' -Value "0804:$sgCLSID$sgProf" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
W "InputMethodOverride set"

# ---- 5) Preload ----
$pre = 'HKCU:\Keyboard Layout\Preload'
New-Item -Force -Path $pre | Out-Null
New-ItemProperty -LiteralPath $pre -Name '1' -Value '00000804' -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $pre -Name '2' -Value '00000409' -PropertyType String -Force | Out-Null
W "Preload set 1=0804 2=0409"

# ---- 5.5) CTF Assemblies / SortOrder：zh-CN(0x0804) 的默认 TSF 装配指向搜狗（官方安装关键步骤）----
# 缺失时新窗口默认激活微软拼音(已禁用) profile → 输入英文直通
$asmKey  = 'HKCU:\Software\Microsoft\CTF\Assemblies\0x00000804\{34745C63-B2F0-4784-8B67-5E12C8701A31}'
$sortKey = 'HKCU:\Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\{34745C63-B2F0-4784-8B67-5E12C8701A31}'
New-Item -Force -Path $asmKey | Out-Null
New-ItemProperty -LiteralPath $asmKey -Name 'Default' -Value $sgCLSID -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $asmKey -Name 'Profile' -Value $sgProf -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $asmKey -Name 'KeyboardLayout' -Value 0x08040804 -PropertyType DWord -Force | Out-Null
# SortOrder 00000000 = 微软拼音(与官方一致), 00000001 = 搜狗
$msSort = "$sortKey\00000000"; New-Item -Force -Path $msSort | Out-Null
New-ItemProperty -LiteralPath $msSort -Name 'CLSID' -Value $msCLSID -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $msSort -Name 'Profile' -Value $msProf -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $msSort -Name 'KeyboardLayout' -Value 0 -PropertyType DWord -Force | Out-Null
$sgSort = "$sortKey\00000001"; New-Item -Force -Path $sgSort | Out-Null
New-ItemProperty -LiteralPath $sgSort -Name 'CLSID' -Value $sgCLSID -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $sgSort -Name 'Profile' -Value $sgProf -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $sgSort -Name 'KeyboardLayout' -Value 0 -PropertyType DWord -Force | Out-Null
W "CTF Assemblies/SortOrder: zh-CN default -> Sogou"

# ---- 6) 确认语言列表最终状态 ----
try {
  Get-WinUserLanguageList | ForEach-Object { W ("  lang=" + $_.LanguageTag + " tips=[" + ($_.InputMethodTips -join ';') + "]") }
} catch {}
W "=== ime_user_register done ==="