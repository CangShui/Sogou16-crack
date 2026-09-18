; Sogou16-crack-cangshui.nsi
; 搜狗输入法 16.8.0.4914 断网绿化一键安装包（cangshui）
; 变更要点:
;   - 注入范围回到 v5 已验证的 5 个 (SGTool/SGDownload/SGCurlHelper/networkbase/shiply)，不再全量注入(全量会破坏 SogouCloud)
;   - SogouInput 注册表 32 位 + 64 位两个视图都写 (修复 SogouCloud "读注册表失败")
;   - scrub 跳过 IME 核心 6 文件 (官方字节)
;   - 硬化脚本用 .NET SetValue('') 正确写默认值
SetCompressor /SOLID lzma
RequestExecutionLevel admin
ShowInstDetails hide
AutoCloseWindow true
Unicode true

Name "搜狗输入法16.8断网绿化版（cangshui）"
; OutFile: NSIS 的相对路径按【本 .nsi 所在目录】解析（不是 CWD）。
; 默认输出到仓库根 dist/；也可用 /DOUT=<绝对路径> 覆盖：
;   makensis /DSRC="...\payload" /DOUT="...\dist\Sogou16-crack-cangshui.exe" sogou16-crack-cangshui.nsi
!ifndef OUT
  !define OUT "${__FILEDIR__}\..\..\dist\Sogou16-crack-cangshui.exe"
!endif
OutFile "${OUT}"
InstallDir "$PROGRAMFILES32\SogouInput"

!include "MUI2.nsh"
!include "x64.nsh"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"

; SRC 指向已构建好的 payload 目录。
; 复刻时按实际位置修改，或用 /DSRC=... 在命令行覆盖:
;   makensis /DSRC="C:\path\to\payload" Sogou16-crack-cangshui/02_构建脚本/sogou16-crack-cangshui.nsi
!ifndef SRC
  !define SRC "work16/payload"
!endif
!define VER "16.8.0.4914"
!define CLSID "{E7EA138E-69F8-11D7-A6EA-00065B844310}"
!define PROF  "{E7EA138F-69F8-11D7-A6EA-00065B844311}"
!define TSFASM "{34745C63-B2F0-4784-8B67-5E12C8701A31}"

Section "Install" SecMain
  SetShellVarContext all

  ; ========== 0. 安装前清理：停掉占用文件的进程 + 删旧版残留 ==========
  ; 目的：解决“重装时报 无法打开要写入的文件 SogouImeBroker.exe”
  ;       （旧版 SogouImeBroker 由 Run 键自启并常驻，锁住文件）
  SetRegView 64
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SogouImeBroker"
  DeleteRegValue HKLM "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" "SogouImeBroker"
  nsExec::ExecToLog 'taskkill /F /IM SogouImeBroker.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouCloud.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGTool.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGDownload.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGMyInput.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouPY.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouTSF.exe'
  nsExec::ExecToLog 'taskkill /F /IM PinyinUp.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouWizard.exe'
  nsExec::ExecToLog 'taskkill /F /IM 搜狗皮肤词库工具.exe'
  nsExec::ExecToLog 'taskkill /F /IM 搜狗提示拦截.exe'
  Sleep 800

  ; ========== 1. Program Files ==========
  SetOutPath "$INSTDIR\${VER}"
  File /r "${SRC}\progfiles\SogouInput\16.8.0.4914\*.*"
  SetOutPath "$INSTDIR\Components"
  File /r "${SRC}\progfiles\SogouInput\Components\*.*"
  SetOutPath "$INSTDIR\SogouExe"
  File /r "${SRC}\progfiles\SogouInput\SogouExe\*.*"

  ; ========== 2. 系统 IME 文件（官方字节）==========
  ; 防占用写法：先把新文件写到 $TEMP，再 Delete 目标 + Rename 就位。
  ; /REBOOTOK 兜底：若目标正被 IME 加载占用，则整个删除+改名排到重启后执行，
  ; 从而不会再弹“无法打开要写入的文件”错误框（重装失败的根因）。
  ; ${DisableX64FSRedirection}：让 32 位安装器写真正的 System32（否则被重定向）。
  SetRegView 64
  ${DisableX64FSRedirection}
  SetOutPath "$TEMP\sg16ime64"
  File "${SRC}\ime_system32\SogouPY.ime"
  File "${SRC}\ime_system32\SogouTSF.ime"
  Delete /REBOOTOK "C:\Windows\System32\SogouPY.ime"
  Delete /REBOOTOK "C:\Windows\System32\SogouTSF.ime"
  Rename /REBOOTOK "$TEMP\sg16ime64\SogouPY.ime" "C:\Windows\System32\SogouPY.ime"
  Rename /REBOOTOK "$TEMP\sg16ime64\SogouTSF.ime" "C:\Windows\System32\SogouTSF.ime"
  ${EnableX64FSRedirection}

  SetOutPath "$TEMP\sg16ime32"
  File "${SRC}\ime_syswow64\SogouPY.ime"
  File "${SRC}\ime_syswow64\SogouTSF.ime"
  Delete /REBOOTOK "C:\Windows\SysWOW64\SogouPY.ime"
  Delete /REBOOTOK "C:\Windows\SysWOW64\SogouTSF.ime"
  Rename /REBOOTOK "$TEMP\sg16ime32\SogouPY.ime" "C:\Windows\SysWOW64\SogouPY.ime"
  Rename /REBOOTOK "$TEMP\sg16ime32\SogouTSF.ime" "C:\Windows\SysWOW64\SogouTSF.ime"

  CreateDirectory "C:\Windows\SysWOW64\IME\SogouPY"
  SetOutPath "$TEMP\sg16broker"
  File "${SRC}\ime_broker\SogouImeBroker.exe"
  File "${SRC}\ime_broker\SogouWin10Setup.exe"
  Delete /REBOOTOK "C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe"
  Delete /REBOOTOK "C:\Windows\SysWOW64\IME\SogouPY\SogouWin10Setup.exe"
  Rename /REBOOTOK "$TEMP\sg16broker\SogouImeBroker.exe" "C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe"
  Rename /REBOOTOK "$TEMP\sg16broker\SogouWin10Setup.exe" "C:\Windows\SysWOW64\IME\SogouPY\SogouWin10Setup.exe"

  ; ========== 3. TSF 注册 ==========
  SetRegView 64
  WriteRegStr HKLM "SOFTWARE\Classes\CLSID\${CLSID}" "" "搜狗拼音输入法"
  WriteRegStr HKLM "SOFTWARE\Classes\CLSID\${CLSID}\InProcServer32" "" "C:\WINDOWS\system32\SogouTSF.ime"
  WriteRegStr HKLM "SOFTWARE\Classes\CLSID\${CLSID}\InProcServer32" "ThreadingModel" "Apartment"
  WriteRegStr HKLM "SOFTWARE\Classes\Wow6432Node\CLSID\${CLSID}" "" "搜狗拼音输入法"
  WriteRegStr HKLM "SOFTWARE\Classes\Wow6432Node\CLSID\${CLSID}\InProcServer32" "" "C:\WINDOWS\SysWow64\SogouTSF.ime"
  WriteRegStr HKLM "SOFTWARE\Classes\Wow6432Node\CLSID\${CLSID}\InProcServer32" "ThreadingModel" "Apartment"

  SetRegView 64
  !define TIP64 "SOFTWARE\Microsoft\CTF\TIP\${CLSID}"
  !define TIP32 "SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\${CLSID}"

  WriteRegStr HKLM "${TIP64}\Category\Category\{046B8C80-1647-40F7-9B21-B93B81AABC1B}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{13A016DF-560B-46CD-947A-4C3AF1E0E35D}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{34745C63-B2F0-4784-8B67-5E12C8701A31}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{364215D9-75BC-11D7-A6EF-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{364215DA-75BC-11D7-A6EF-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Category\{CCF05DD7-4A87-11D7-A6E2-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{046B8C80-1647-40F7-9B21-B93B81AABC1B}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{13A016DF-560B-46CD-947A-4C3AF1E0E35D}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{34745C63-B2F0-4784-8B67-5E12C8701A31}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{364215D9-75BC-11D7-A6EF-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{364215DA-75BC-11D7-A6EF-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP64}\Category\Item\${CLSID}\{CCF05DD7-4A87-11D7-A6E2-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP64}\LanguageProfile\0x00000804\${PROF}" "Description" "搜狗拼音输入法"
  WriteRegStr HKLM "${TIP64}\LanguageProfile\0x00000804\${PROF}" "IconFile" "C:\WINDOWS\system32\SogouTSF.ime"
  WriteRegDWORD HKLM "${TIP64}\LanguageProfile\0x00000804\${PROF}" "IconIndex" 0
  WriteRegDWORD HKLM "${TIP64}\LanguageProfile\0x00000804\${PROF}" "Enable" 1

  WriteRegStr HKLM "${TIP32}\Category\Category\{046B8C80-1647-40F7-9B21-B93B81AABC1B}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{13A016DF-560B-46CD-947A-4C3AF1E0E35D}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{34745C63-B2F0-4784-8B67-5E12C8701A31}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{364215D9-75BC-11D7-A6EF-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{364215DA-75BC-11D7-A6EF-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Category\{CCF05DD7-4A87-11D7-A6E2-00065B84435C}\${CLSID}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{046B8C80-1647-40F7-9B21-B93B81AABC1B}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{13A016DF-560B-46CD-947A-4C3AF1E0E35D}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{34745C63-B2F0-4784-8B67-5E12C8701A31}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{364215D9-75BC-11D7-A6EF-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{364215DA-75BC-11D7-A6EF-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{49D2F9CE-1F5E-11D7-A6D3-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{49D2F9CF-1F5E-11D7-A6D3-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP32}\Category\Item\${CLSID}\{CCF05DD7-4A87-11D7-A6E2-00065B84435C}" "" ""
  WriteRegStr HKLM "${TIP32}\LanguageProfile\0x00000804\${PROF}" "Description" "搜狗拼音输入法"
  WriteRegStr HKLM "${TIP32}\LanguageProfile\0x00000804\${PROF}" "IconFile" "C:\WINDOWS\SysWow64\SogouTSF.ime"
  WriteRegDWORD HKLM "${TIP32}\LanguageProfile\0x00000804\${PROF}" "IconIndex" 0
  WriteRegDWORD HKLM "${TIP32}\LanguageProfile\0x00000804\${PROF}" "Enable" 1

  ; ========== 4. SogouInput 注册表：32 位 + 64 位两个视图都写 ==========
  ; 32 位视图（NSIS 默认 32 位进程）
  SetRegView 32
  WriteRegStr HKLM "SOFTWARE\SogouInput" "" "$INSTDIR"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "Version" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "VersionType" "Final"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "Region" "1111_pinyin_guanwang_16.8"
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "PatchFlag" 1
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "ImeHint" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "SendUserExperience" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "UpUseBT" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "UpdateInterval" 0
  WriteRegStr HKLM "SOFTWARE\SogouInput" "LastUpdateTime" ""
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "IsUdpate" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnableCloudInput" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "CloudCand" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnableSearchCand" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnablePinyinCloud" 0
  WriteRegStr HKLM "SOFTWARE\SogouInput" "StartMenuFolder" "搜狗输入法"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "HQBOVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "MIVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "CSVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "HSign" "T2Xv6ScvwzOzde6fd9K0PUBi/e9k8Ih0d9CZbDBgPUbSYX5caDB3DMR22AtxwSJOyvVBIW8ZNIr0IpS6TeowDA=="
  WriteRegStr HKLM "SOFTWARE\SogouInput" "BizVersion" "8.9"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "BizPath" "$INSTDIR\Components\biz_center\1.0.0.3315\biz_helper.exe"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "SExtVersion" "1.0.0.5"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "cert_installed" "1"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "certr3_installed" "1"
  ; 64 位视图（SogouCloud 等 64 位组件读 HKLM\Software\SogouInput）
  SetRegView 64
  WriteRegStr HKLM "SOFTWARE\SogouInput" "" "$INSTDIR"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "Version" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "VersionType" "Final"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "Region" "1111_pinyin_guanwang_16.8"
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "PatchFlag" 1
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "ImeHint" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "SendUserExperience" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "UpUseBT" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "UpdateInterval" 0
  WriteRegStr HKLM "SOFTWARE\SogouInput" "LastUpdateTime" ""
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "IsUdpate" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnableCloudInput" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "CloudCand" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnableSearchCand" 0
  WriteRegDWORD HKLM "SOFTWARE\SogouInput" "EnablePinyinCloud" 0
  WriteRegStr HKLM "SOFTWARE\SogouInput" "StartMenuFolder" "搜狗输入法"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "HQBOVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "MIVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "CSVersion" "${VER}"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "HSign" "T2Xv6ScvwzOzde6fd9K0PUBi/e9k8Ih0d9CZbDBgPUbSYX5caDB3DMR22AtxwSJOyvVBIW8ZNIr0IpS6TeowDA=="
  WriteRegStr HKLM "SOFTWARE\SogouInput" "BizVersion" "8.9"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "BizPath" "$INSTDIR\Components\biz_center\1.0.0.3315\biz_helper.exe"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "SExtVersion" "1.0.0.5"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "cert_installed" "1"
  WriteRegStr HKLM "SOFTWARE\SogouInput" "certr3_installed" "1"

  ; ========== 5. 用户级 TSF 启用 + 键盘布局 ==========
  SetRegView 64
  WriteRegDWORD HKCU "Software\Microsoft\CTF\TIP\${CLSID}\LanguageProfile\0x00000804\${PROF}" "Enable" 1
  WriteRegStr HKCU "Keyboard Layout\Preload" "1" "00000804"
  WriteRegStr HKCU "Keyboard Layout\Preload" "2" "00000409"
  WriteRegStr HKCU "Control Panel\International\User Profile" "InputMethodOverride" "0804:${CLSID}${PROF}"
  WriteRegStr HKCU "Software\Microsoft\CTF\Assemblies\0x00000804\${TSFASM}" "Default" "${CLSID}"
  WriteRegStr HKCU "Software\Microsoft\CTF\Assemblies\0x00000804\${TSFASM}" "Profile" "${PROF}"
  WriteRegDWORD HKCU "Software\Microsoft\CTF\Assemblies\0x00000804\${TSFASM}" "KeyboardLayout" 0x08040804
  WriteRegStr HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000000" "CLSID" "{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}"
  WriteRegStr HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000000" "Profile" "{FA550B04-5AD7-411F-A5AC-CA038EC515D7}"
  WriteRegDWORD HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000000" "KeyboardLayout" 0
  WriteRegStr HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000001" "CLSID" "${CLSID}"
  WriteRegStr HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000001" "Profile" "${PROF}"
  WriteRegDWORD HKCU "Software\Microsoft\CTF\SortOrder\AssemblyItem\0x00000804\${TSFASM}\00000001" "KeyboardLayout" 0

  ; ========== 5b. 用户级 IME 注册 + 硬化 (RunOnce) ==========
  SetOutPath "$INSTDIR"
  File "${SRC}\ime_user_register.ps1"
  File "${SRC}\offline_hardening_user.ps1"
  WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" "SogouImeUserRegister" '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\ime_user_register.ps1"'
  WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" "SogouImeUserHardening" '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\offline_hardening_user.ps1"'

  ; ========== 6. Broker 自启 + RegServer ==========
  WriteRegStr HKLM "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" "SogouImeBroker" "$\"C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe$\""
  nsExec::ExecToLog '"C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe" -RegServer'
  Sleep 500

  ; ========== 7. 安装期硬化 ==========
  SetOutPath "$TEMP\sg16offline"
  File "${SRC}\offline_hardening.ps1"
  nsExec::ExecToLog '"$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$TEMP\sg16offline\offline_hardening.ps1"'
  RMDir /r "$TEMP\sg16offline"

  ; ========== 7b. 部署离线导入工具 ==========
  SetOutPath "$INSTDIR\Tools"
  File "${SRC}\tools\搜狗皮肤词库工具.exe"
  ; 升级清理：早期版本曾部署过“提示弹窗拦截守护”，现已改为对 SGTool.exe 打补丁
  ; 从根源消除弹窗，不再需要常驻进程。这里清掉旧版残留（自启键 + exe）。
  SetRegView 32
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SogouNoticeGuard"
  SetRegView 64
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SogouNoticeGuard"
  Delete "$INSTDIR\Tools\搜狗提示拦截.exe"

  ; ========== 8. 快捷方式 ==========
  CreateDirectory "$SMPROGRAMS\搜狗输入法"
  CreateShortCut "$SMPROGRAMS\搜狗输入法\设置.lnk" "$INSTDIR\${VER}\SGTool.exe" "-line 0 -border --appid=config"
  CreateShortCut "$SMPROGRAMS\搜狗输入法\我的输入法.lnk" "$INSTDIR\${VER}\SGMyInput.exe" ""
  CreateShortCut "$SMPROGRAMS\搜狗输入法\输入法管理器.lnk" "$INSTDIR\${VER}\SGTool.exe" "-line 0 -border --appid=config /m"
  CreateShortCut "$DESKTOP\搜狗输入法快捷开关.lnk" "$INSTDIR\${VER}\SGMyInput.exe" ""
  CreateShortCut "$DESKTOP\皮肤词库管理工具.lnk" "$INSTDIR\Tools\搜狗皮肤词库工具.exe" ""
  CreateShortCut "$SMPROGRAMS\搜狗输入法\皮肤词库管理工具.lnk" "$INSTDIR\Tools\搜狗皮肤词库工具.exe" ""

  ; ========== 9. 卸载器 ==========
  WriteUninstaller "$INSTDIR\Uninstall-Sogou16-crack-cangshui.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\{B79C6B33-5FE9-4B1A-B8C7-C43C58D7F2C7}" "DisplayName" "搜狗输入法16.8断网绿化版（cangshui）"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\{B79C6B33-5FE9-4B1A-B8C7-C43C58D7F2C7}" "UninstallString" "$\"$INSTDIR\Uninstall-Sogou16-crack-cangshui.exe$\""

  SetRebootFlag true
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64

  ; ---- 1. 停掉所有占用文件的进程（否则文件删不掉）----
  nsExec::ExecToLog 'taskkill /F /IM SogouImeBroker.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouCloud.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGTool.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGDownload.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGMyInput.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouPY.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouTSF.exe'
  nsExec::ExecToLog 'taskkill /F /IM PinyinUp.exe'
  nsExec::ExecToLog 'taskkill /F /IM SogouWizard.exe'
  nsExec::ExecToLog 'taskkill /F /IM 搜狗皮肤词库工具.exe'
  nsExec::ExecToLog 'taskkill /F /IM SGBizLauncher.exe'
  nsExec::ExecToLog 'taskkill /F /IM 搜狗提示拦截.exe'
  Sleep 800

  ; ---- 2. 自启动 / RunOnce ----
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SogouImeBroker"
  DeleteRegValue HKLM "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" "SogouImeBroker"
  SetRegView 64
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "SogouNoticeGuard"
  DeleteRegValue HKLM "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" "SogouNoticeGuard"
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" "SogouImeUserRegister"
  DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" "SogouImeUserHardening"

  ; ---- 3. 系统 IME 文件（关键：之前完全没删，导致残留+重装失败）----
  ; 注意：32 位卸载器写 "C:\Windows\System32" 会被 WOW64 重定向到 SysWOW64，
  ; 必须 ${DisableX64FSRedirection} 才能删到真正的 System32，否则 System32 残留。
  ${DisableX64FSRedirection}
  Delete /REBOOTOK "C:\Windows\System32\SogouPY.ime"
  Delete /REBOOTOK "C:\Windows\System32\SogouTSF.ime"
  ${EnableX64FSRedirection}
  Delete /REBOOTOK "C:\Windows\SysWOW64\SogouPY.ime"
  Delete /REBOOTOK "C:\Windows\SysWOW64\SogouTSF.ime"
  Delete /REBOOTOK "C:\Windows\SysWOW64\IME\SogouPY\SogouImeBroker.exe"
  Delete /REBOOTOK "C:\Windows\SysWOW64\IME\SogouPY\SogouWin10Setup.exe"
  RMDir /REBOOTOK "C:\Windows\SysWOW64\IME\SogouPY"

  ; ---- 4. 注册表 ----
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\{B79C6B33-5FE9-4B1A-B8C7-C43C58D7F2C7}"
  DeleteRegKey HKLM "SOFTWARE\SogouInput"
  DeleteRegKey HKLM "SOFTWARE\WOW6432Node\SogouInput"
  DeleteRegKey HKLM "SOFTWARE\Microsoft\CTF\TIP\${CLSID}"
  DeleteRegKey HKLM "SOFTWARE\Wow6432Node\Microsoft\CTF\TIP\${CLSID}"
  DeleteRegKey HKLM "SOFTWARE\Classes\CLSID\${CLSID}"
  DeleteRegKey HKLM "SOFTWARE\Classes\Wow6432Node\CLSID\${CLSID}"
  DeleteRegKey HKLM "SOFTWARE\Classes\.scel"
  DeleteRegKey HKLM "SOFTWARE\Classes\SogouSkinFile"
  ; 用户级 TSF / 键盘布局
  DeleteRegValue HKCU "Software\Microsoft\CTF\TIP\${CLSID}\LanguageProfile\0x00000804\${PROF}" "Enable"
  DeleteRegKey HKCU "Software\Microsoft\CTF\TIP\${CLSID}"
  DeleteRegValue HKCU "Keyboard Layout\Preload" "1"
  DeleteRegValue HKCU "Keyboard Layout\Preload" "2"
  DeleteRegValue HKCU "Control Panel\International\User Profile" "InputMethodOverride"

  ; ---- 5. 程序目录（整个 SogouInput，含 Tools / ps1 / 版本目录）----
  RMDir /r /REBOOTOK "$INSTDIR"

  ; ---- 6. 快捷方式 ----
  RMDir /r "$SMPROGRAMS\搜狗输入法"
  Delete "$DESKTOP\搜狗输入法快捷开关.lnk"
  Delete "$DESKTOP\皮肤词库管理工具.lnk"

  ; ---- 7. 用户数据（皮肤/词库/配置）----
  ; 用 /REBOOTOK 兜底：卸载时 IME 仍在本会话运行，日志/皮肤文件可能被占用。
  RMDir /r /REBOOTOK "$PROFILE\AppData\LocalLow\SogouPY"
  RMDir /r /REBOOTOK "$APPDATA\SogouPY"

  SetRebootFlag true
SectionEnd
