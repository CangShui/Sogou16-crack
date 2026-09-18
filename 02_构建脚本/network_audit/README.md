# 全系统网络抓取工具（Network Audit Kit）

在你自己的虚拟机里再抓一次超长网络审计，用这个工具包。它和我刚才 30 分钟审计用的是同一套方法（每 10 秒 netstat 全系统采样 + PID→进程名 + 汇总），但你可以任意设置时长，结束自动导出 Excel。

## 文件
| 文件 | 作用 |
|---|---|
| `sysnet_capture.ps1` | 抓取器（PowerShell）。全系统公网 TCP 连接采样，实时写 CSV，结束生成汇总 |
| `analyze_net.py` | 分析器（Python）。把 raw.csv 转成 Excel：进程汇总 / 目标汇总 / 搜狗可疑标记 / 明细 |
| `run_capture.bat` | 一键：抓取 → 自动分析导出 Excel |
| `netout/` | 输出目录（自动创建）：`<名>.raw.csv`（原始）、`<名>.summary.csv`（汇总）、`<名>_analysis.xlsx`（Excel） |

## 快速使用（推荐）
```
run_capture.bat           默认抓 30 分钟
run_capture.bat 60        抓 60 分钟
run_capture.bat 720 15    抓 12 小时，每 15 秒采样
```
跑完后打开 `netout\*_analysis.xlsx` 即可。

## 手动使用（更灵活）
```
# 抓取（想抓多久都行；Ctrl+C 可提前结束并仍生成汇总）
powershell -NoProfile -ExecutionPolicy Bypass -File sysnet_capture.ps1 -Minutes 120 -Interval 10 -OutDir D:\audit -Name myrun

# 分析导出 Excel
python analyze_net.py D:\audit\myrun.raw.csv
```

## 参数
| 参数 | 默认 | 说明 |
|---|---|---|
| `-Minutes` | 30 | 抓取时长（分钟）。`-Minutes 0` = 无限，直到 Ctrl+C |
| `-Interval` | 10 | 采样间隔（秒） |
| `-OutDir` | `.\netout` | 输出目录 |
| `-Name` | 自动 | 运行名前缀 |

## Excel 工作表
- **总览-时间线**：每个采样时刻的连接数（可看出拨号的时间分布）
- **进程汇总**：每个进程的连接总数、独立目标数（排序后一眼看出谁在大量联网）
- **目标汇总**：每个远程服务器的总次数、涉及的进程、可疑分类
- **搜狗连接(可疑)**：搜狗/腾讯系 IP 段（116.130/16、123.125/16、220.194/16、111.206/16、218.61/16、123.6/16）自动筛出，方便你快速定位
- **明细**：全部原始记录（时间、本地、远程、状态、PID、进程名）

## 自动打字器（配合抓取，模拟真实输入法输入）
| 文件 | 作用 |
|---|---|
| `ime_typer.ps1` | 持续用搜狗输入法「真实组合打字」（切 0804 → 打拼音 → 空格上屏中文），制造真实 IME 输入事件 |
| `run_typer.bat` | 一键打字器：`run_typer.bat [分钟] [每轮间隔秒]`，`0`=无限（Ctrl+C 停） |
| `run_capture_and_type.bat` | 一键**同时**启动抓取 + 打字：`run_capture_and_type.bat [分钟] [采样间隔] [打字间隔]` |

说明：
- `ime_typer.ps1` 是**真实组合打字**（不是直接塞中文字符）——这满足验收里「中文必须由搜狗输入法产生、IME 核心要真正激活」的要求。
- 打字日志写到 `netout\<名>.typing.log`，每行 `round N : typed [中文]` 可确认每轮都组合出中文。
- 常用：
  - 想「边抓边打字」：`run_capture_and_type.bat 720 15 10`（抓 12 小时、每 15 秒采样、每 10 秒打一个词）。
  - 只想打字：`run_typer.bat 60`（打 60 分钟）。

## 注意事项
- 本工具**不写 hosts、不碰防火墙、不改任何系统环境**，纯观察。
- 抓取期间请正常使用（打字、点鼠标），这样最贴近真实。
- 在 VM 里抓建议用 `run_capture.bat`（SYSTEM 权限看到全部进程）；如用普通窗口，个别系统进程名可能显示为 pid<数字>。
- 分析器需要 Python：`pip install pandas openpyxl`（本机已装）。
