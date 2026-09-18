# ============================================================================
#  ime_typer.ps1 — 持续用搜狗输入法"真实组合打字"的自动打字器
# ----------------------------------------------------------------------------
#  配合 network_audit 抓取器使用：抓网络期间持续打字，制造真实 IME 输入事件。
#
#  为什么必须"真实组合"（不是 SendKeys 直接塞中文字符）：
#   验收规则要求确认中文输入由搜狗输入法产生，IME 核心必须被真正激活。
#   因此本脚本的做法是：
#     1) 打开记事本并置前台
#     2) Win+Space 循环切换，直到该线程键盘布局语言为 0804（搜狗拼音）
#     3) 用 SendKeys 发送"拼音"（如 zhongwen）
#     4) 按空格上屏首个候选，得到组合出的中文
#
#  用法:
#    powershell -NoProfile -ExecutionPolicy Bypass -File ime_typer.ps1
#      -Minutes 30        # 打字时长(分钟)；0 = 无限，直到按 Ctrl+C
#      -Interval 12       # 每轮打完一版拼音后的停顿(秒)，默认 8
#      -LogDir C:\audit   # 日志输出目录，默认脚本所在目录\netout
#      -Name myrun        # 运行名前缀(缺省自动)
# ============================================================================
param(
  [int]$Minutes = 30,
  [int]$Interval = 8,
  [string]$LogDir = '',
  [string]$Name = ''
)
$ErrorActionPreference = 'Continue'
if(-not $LogDir){ $LogDir = Join-Path $PSScriptRoot 'netout' }
if(-not $Name){ $Name = 'imetyper_' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$log = Join-Path $LogDir "$Name.typing.log"

# 词库：@(拼音, 期望组合出的中文)。拼音必须能被搜狗正常组合（真实 IME 事件）。
$words = @(
 @('anjiaoxingjiaonang','阿莫西林胶囊'),@('ganmaolingkeli','感冒灵颗粒'),
 @('lianhuaqingwenjiaonang','连花清瘟胶囊'),@('budaifenhuanshijia','布洛芬缓释片'),
 @('banlangenkeli','板蓝根颗粒'),@('renshoubaoxian','人寿保险'),
 @('zhongjixian','重疾险'),@('baiwanxiaoyiliao','百万医疗险'),
 @('chexianlipei','车险理赔'),@('pinganbaoxian','平安保险'),
 @('taipingyangbaoxian','太平洋保险'),@('yiwaiweihaixian','意外伤害险'),
 @('yanglaobaoxian','养老保险'),@('jiaoyujinbaoxian','教育金保险'),
 @('fenhongxingbaoxian','分红型保险'),@('hongtangjiangcha','红糖姜茶'),
 @('wuchangdami','五常大米'),@('qingdaopijiu','青岛啤酒'),
 @('maotaijiu','茅台酒'),@('longjingchaye','龙井茶叶'),
 @('huaweishouji','华为手机'),@('gelikongtiao','格力空调'),
 @('haierbingxiang','海尔冰箱'),@('xiaomidianshi','小米电视'),
 @('biyadiqiche','比亚迪汽车'),@('antianming','安宫牛黄丸'),
 @('ceshi','测试'),@('zhongwen','中文'),@('sougoushurufa','搜狗输入法')
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IME_TYPER {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint idThread);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

function Ensure-Zh([IntPtr]$h){
  [IME_TYPER]::ShowWindow($h, 5) | Out-Null
  [IME_TYPER]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 600
  for($i = 0; $i -lt 8; $i++){
    [IME_TYPER]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [IME_TYPER]::keybd_event(0x20,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [IME_TYPER]::keybd_event(0x20,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [IME_TYPER]::keybd_event(0x5B,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600
    $tid = 0; [IME_TYPER]::GetWindowThreadProcessId($h, [ref]$tid) | Out-Null
    $hkl = [IME_TYPER]::GetKeyboardLayout($tid)
    if(((($hkl.ToInt64()) -shr 16) -band 0xFFFF) -eq 0x0804){ return $true }
  }
  return $false
}

$startTs = Get-Date -Format 'HH:mm:ss'
"=== ime_typer start $startTs minutes=$Minutes interval=${Interval}s log=$log ===" | Out-File $log -Encoding UTF8

Start-Process notepad.exe
Start-Sleep 5
$ws = New-Object -ComObject WScript.Shell
$round = 0
$end = if($Minutes -gt 0){ (Get-Date).AddMinutes($Minutes) } else { $null }

while($true){
  $round++
  if($end -and (Get-Date) -ge $end){ break }
  $np = Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if(-not $np){
    "round $round : no notepad, reopening" | Out-File $log -Append -Encoding UTF8
    Start-Process notepad.exe
    Start-Sleep 6; continue
  }
  $h = $np.MainWindowHandle
  Ensure-Zh $h | Out-Null
  $w = $words[($round - 1) % $words.Count]
  $ws.SendKeys('^a') | Out-Null; Start-Sleep -Milliseconds 150
  $ws.SendKeys('{DEL}') | Out-Null; Start-Sleep -Milliseconds 200
  $ws.SendKeys($w[0]) | Out-Null; Start-Sleep 2
  $ws.SendKeys(' ') | Out-Null; Start-Sleep 1
  "round $round : typed [$($w[1])] $(Get-Date -Format 'HH:mm:ss')" | Out-File $log -Append -Encoding UTF8
  Start-Sleep $Interval
}
"=== ime_typer done rounds=$round $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log -Append -Encoding UTF8