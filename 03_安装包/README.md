# 03_安装包 — 构建产物（未随仓库提供）

因 GitHub 单文件 100MB 限制，最终安装包（约 147MB）**未纳入仓库**。

请通过以下任一方式获取：

1. **Releases 页面**：下载 `Sogou16-crack-cangshui.exe`（推荐）
2. **自行构建**：按 `00_复刻指南.md` §2~§8 从官方底包重新打包

构建产物的校验锚点：

```
文件名   : Sogou16-crack-cangshui.exe
大小     : 147,544,434 字节
SHA256   : f4281ba9029d1f4b7a7aca7ab678b0cbe37e0edce70d72a166f196cb5fe03ec6
```

> 注：payload 内容可 100% 字节复现；最终 `.exe` 的 SHA256 还取决于 NSIS 工具链版本
> （详见 `00_复刻指南.md` §8a）。功能与行为不受影响。
