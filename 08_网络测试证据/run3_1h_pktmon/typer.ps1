$ErrorActionPreference='Continue'
$root='C:\Windows\Temp\netaudit3'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$log="$root\typing.log"
Remove-Item $log -ErrorAction SilentlyContinue
"=== typer3 start $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log -Encoding UTF8
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
public class TY3 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint idThread);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
function EnsureZh($h){
  [TY3]::ShowWindow($h,5) | Out-Null
  [TY3]::SetForegroundWindow($h) | Out-Null
  Start-Sleep -Milliseconds 700
  for($i=0;$i -lt 8;$i++){
    [TY3]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [TY3]::keybd_event(0x20,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [TY3]::keybd_event(0x20,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [TY3]::keybd_event(0x5B,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600
    $tid=0; [TY3]::GetWindowThreadProcessId($h,[ref]$tid) | Out-Null
    $hkl = [TY3]::GetKeyboardLayout($tid)
    if((($hkl.ToInt64() >> 16) -band 0xFFFF) -eq 0x0804){ return $true }
  }
  return $false
}
$np = Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if(-not $np){ Start-Process notepad.exe; Start-Sleep 6 }
$ws = New-Object -ComObject WScript.Shell
$round = 0
$end=(Get-Date).AddMinutes(58)
while((Get-Date) -lt $end){
  $round++
  $np = Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if(-not $np){ "round $round no notepad, reopen" | Out-File $log -Append -Encoding UTF8; Start-Process notepad.exe; Start-Sleep 6; continue }
  EnsureZh($np.MainWindowHandle) | Out-Null
  $w = $words[($round-1) % $words.Count]
  $ws.SendKeys('^a') | Out-Null; Start-Sleep -Milliseconds 150
  $ws.SendKeys('{DEL}') | Out-Null; Start-Sleep -Milliseconds 200
  $ws.SendKeys($w[0]) | Out-Null; Start-Sleep 2
  $ws.SendKeys(' ') | Out-Null; Start-Sleep 1
  "round $round : typed [$($w[1])] $(Get-Date -Format 'HH:mm:ss')" | Out-File $log -Append -Encoding UTF8
  Start-Sleep 5
}
"=== typer3 done rounds=$round $(Get-Date -Format 'HH:mm:ss') ===" | Out-File $log -Append -Encoding UTF8
