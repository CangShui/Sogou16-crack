# SGBizLauncher 反复崩溃：排查与修复

日期：2026-11-02

## 现象

Windows 事件日志 `Application` 中反复出现 `Application Error`：

- 应用程序：`SGBizLauncher.exe` 16.8.0.4914
- 异常代码：`0xc0000005`
- 事件类型：`BEX`
- 典型错误偏移：`0x002af9b8`
- 崩溃频率：每约 6 小时一次

统计范围 2026-10-20 至 2026-11-01：

- 崩溃 52 次
- 每天固定 4 次
- 每次崩溃前都创建对应的 `SGBizLauncher_ConfigUpdate_<pid>.log`
- 崩溃实例的 `SGBizLauncher_<pid>.log` 只有 90 字节，最后一行均为
  `GetDeviceGradeInfo failed`

## 组件性质

`SGBizLauncher.exe` 是搜狗输入法的 `business_promotion` 商业业务启动器，
负责节日弹窗、资讯窗口和推广页面，不参与拼音输入、候选词、皮肤或词库。

程序中可见的源码路径：

```text
src/src/apps/business_promotion/SGBizLauncher/...
```

包括 `config_update`、`imepop`、`skin_prom`、`tab_exp_update` 等商业模块。

## 崩溃原因判断

1. 崩溃是 `BEX` + `0xc0000005`，说明程序执行了不可执行地址，属于控制流/函数指针异常，
   不是普通配置读取失败。
2. WER 加载列表中有 `beacon_sdk.dll`、`qimei.dll`、`shiply.dll`；
   其中 `shiply.dll` 和 `networkbase.dll` 被离线版 `.nblk` 注入。
3. `SGBizLauncher.exe` 本身在离线构建中被 scrub，`Get-AuthenticodeSignature`
   显示 `HashMismatch`。
4. 常规的 65 分钟运行会写完整日志并退出；只有约 6 小时一次的 `ConfigUpdate`
   实例在初始化 `Shiply/TAB` 配置时崩溃。

结论：这是商业推广组件在离线改造环境下的 `ConfigUpdate` 路径崩溃。
由于它不参与输入法核心功能，最稳妥的处理是停用该组件，而不是继续修补它的网络逻辑。

## 修复

采用与 `SogouCloud.exe` 相同的方案：

```text
SGBizLauncher.exe -> 1KB 合法 32 位 EXE 桩
入口: ExitProcess(0)
SHA256: 2e81602cef9515b04b7e9c2a9bb8ba49de94e6528962c3d154f1e2f658914bbd
```

已修改：

- `02_构建脚本/build.py`：构建时同时生成 `SogouCloud.exe` 和 `SGBizLauncher.exe` 桩；
- `02_构建脚本/sogou16-crack-cangshui.nsi`：安装前增加 `taskkill SGBizLauncher.exe`；
- 本机已替换安装目录中的 `SGBizLauncher.exe`，原文件备份为：
  `SGBizLauncher.exe.bak-before-stub-20261102`

## 验证

- 桩文件大小 1,024 字节，哈希与 `SogouCloud` 桩一致。
- 手动运行桩程序：立即以退出码 0 结束，不生成 WER 报告。
- 原有 52 个历史 WER 报告保留，用于对照；替换后不再产生新的 SGBizLauncher 崩溃。
- 输入法、候选框、皮肤和词库功能均不依赖该组件。
