# 搜狗输入法 16.8 断网绿化版（cangshui） — 交付物目录说明

本目录是「搜狗输入法 16.8 断网绿化版（cangshui）」的**完整可复刻交付物**。
下表中「对应要求」列把本目录的实际结构，映射到验收方要求的 7 项内容
（文件夹 / 原始安装包 / 修改安装包 / 无搜狗网络测试证据 /
功能完整性测试证据 / 修改源码 / 项目文档）。

> 项目主页 / 作者博客：<https://cangshui.net>

| 对应要求 | 本目录位置 | 说明 |
|---|---|---|
| **文件夹** | `Sogou16-crack-cangshui/` | 本交付目录（01~08 编号子目录 + 顶层文档） |
| **原始安装包** | `01_原始底包/pinyin_guanwang_16.8.exe` | 搜狗官方安装包，SHA256 = `cd889fa7...`（`04_校验/底包SHA256.txt`） |
| **修改安装包** | `03_安装包/Sogou16-crack-cangshui.exe` | 最终安装包，147,544,434 字节，SHA256 = `a7b33910...` |
| **无搜狗网络测试证据** | `08_网络测试证据/` | 4 次抓取（4h + 2h35m + 1h + 1h，约 8.5 小时）原始数据 + `网络测试汇总报告.md` |
| **功能完整性测试证据** | `05_测试证据/` | 设置面板/皮肤工具/皮肤安装/词库/UI 链接等截图与原始记录 |
| **修改源码** | `02_构建脚本/` + `06_工具源码/` | 见下方「修改源码清单」 |
| **项目文档** | `00_复刻指南.md` + `07_验收报告.md` | 复刻指南（与源码/文件夹一一对应）+ 完整验收报告 |

---

## 修改源码清单

### `02_构建脚本/`（修改/打包脚本）

| 文件 | 作用 |
|---|---|
| `build.py` | **一键构建**：pristine → payload（映射 + UPX + scrub + inject + SogouCloud/SGBizLauncher 桩 + 复制 assets/ps1） |
| `scrub5.py` | 去公网字面量（ASCII + UTF-16LE URL/域名，等长替换，跳过 IME 核心） |
| `inject_block.py` | `.nblk` 断网钩子注入器（IAT 改写，位置无关） |
| `inject.py` | 注入入口（仅 5 模块；用法 `inject.py <payload_root>`） |
| `mkstubexe.py` | 生成 1KB 合法空 EXE（SogouCloud / SGBizLauncher 合法退出桩，字节可复现） |
| `stub_cloud_ret_rejected.py` | 历史留存（被否决的裸 ret 桩，勿用） |
| `offline_hardening.ps1` | 安装期硬化（双视图注册表；无 hosts/防火墙） |
| `ime_user_register.ps1` | 用户级 TSF 注册（RunOnce） |
| `offline_hardening_user.ps1` | 用户级硬化 |
| `sogou16-crack-cangshui.nsi` | NSIS 打包脚本（SRC 可用 `/DSRC=...` 覆盖，输出可用 `/DOUT=...` 覆盖） |
| `upx_tool/` | UPX 4.2.4（解压被压缩模块） |
| `network_audit/` | 用户自用网络抓取工具包 |
| `assets/Components/` | **不可推导的构建素材**：官方皮肤控件 `SogouFlash/` + `ComponentConfig.ini` |
| `assets/Tools/` | 已编译好的 `搜狗皮肤词库工具.exe`（SHA256 `804d06d0...`） |
| `assets/nsis-plugins/` | 原始构建所用的 NSIS 插件（nsDialogs/nsExec/System），用于尽量贴近字节 |

### `06_工具源码/`（自研工具源码）

| 文件 | 作用 |
|---|---|
| `sogou_tool/main.go` | 离线皮肤/词库管理 GUI 工具源码（纯 Win32，含 `LockOSThread` 修复；UI 含两个可点击网址） |
| `sogou_tool/go.mod` | Go 模块定义（go 1.21） |
| `sogou_tool/编译说明.md` | 编译命令、产物哈希、稳定性要点 |

> 编译产物 `搜狗皮肤词库工具.exe` 已打进安装包（解包后位于 `Tools\`，
> SHA256 = `804d06d0...`，2,321,408 字节），随 `02_构建脚本/assets/Tools/` 提供。
>
> UI 说明：含「离线皮肤/词库下载地址（https://pinyin.sogou.com/windows/）」与
> 「作者博客（https://cangshui.net）」两个**可点击链接**（另有对应按钮），
> 点击均调用系统浏览器打开。

---

## 复刻入口

1. 读 `00_复刻指南.md`（含 §11 一键复刻检查单）。
2. 按 §2~§8 构建 payload 并 `makensis` 打包。
3. 与 `04_校验/` 中 SHA256 逐项比对。
4. 按 `07_验收报告.md` 与 `08_网络测试证据/网络测试汇总报告.md` 复验。

---

## 版本锚点（用于校验复刻是否成功）

| 对象 | SHA256 | 大小 |
|---|---|---|
| 官方底包 `pinyin_guanwang_16.8.exe` | `cd889fa70a0bec77a5bb4f5c1fdff7a42674a29cc1fb4fc4cf5f2b645ef18fc2` | — |
| 安装包 `Sogou16-crack-cangshui.exe` | `f4281ba9029d1f4b7a7aca7ab678b0cbe37e0edce70d72a166f196cb5fe03ec6` | 147,544,434 |
| `SogouCloud.exe`（1KB 桩） | `2e81602cef9515b04b7e9c2a9bb8ba49de94e6528962c3d154f1e2f658914bbd` | 1,024 |
| `SGBizLauncher.exe`（1KB 桩） | `2e81602cef9515b04b7e9c2a9bb8ba49de94e6528962c3d154f1e2f658914bbd` | 1,024 |
| `Tools\搜狗皮肤词库工具.exe` | `804d06d0dc02ff8ce0983854d5deec00c9afd0dfe4e76f752bfd0b5255a9280b3` | 2,321,408 |
| IME 核心 6 文件 | 见 `04_校验/IME核心文件官方SHA256.txt` | — |
| 5 个注入模块 | 见 `04_校验/修改文件清单.txt` | — |

> 注：payload 内容可 100% 字节复现；最终 `.exe` 的 SHA256 还取决于 NSIS 工具链版本
> （NSIS 自身插件与 install code/stub 会编入安装包），详见 `00_复刻指南.md` §8a。
