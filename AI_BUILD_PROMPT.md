# 给 AI 的构建提示词

这份提示词用于让 Codex、Claude Code 或其他代码 Agent 帮助个人用户非商业地构建、检查或修改 Flicky Ashtray。普通用户不需要使用它，直接下载 GitHub Release 即可。

## 可直接复制

```text
你正在协助我维护 Flicky Ashtray，一个完全本地运行的 macOS / Windows 桌面吸烟记录工具。

开始前请完整阅读仓库根目录 README.md、LICENSE、assets/LICENSE.md，以及目标平台对应的源码和测试。遵守 PolyForm Noncommercial 1.0.0 与 CC BY-NC 4.0；不要移除署名、放宽许可或把代码/素材用于商业项目。

本次目标：在当前电脑上构建一个可以实际运行的 Flicky Ashtray，并在必要时修复构建问题。先识别操作系统和芯片，不要假设 Mac 命令可以直接生成 Windows 原生体验，也不要把编译成功冒充实机体验通过。

必须保留的产品行为：
- 所有数据只保存在本机，不增加账号、联网、分析或云同步。
- 每日上限 1–60，计数日起点 0–23 点。
- 每个计数日最多撤销一次，快速双击只记一根。
- 烟灰缸与桌面便签两种桌宠；可缩放、拖动、隐藏并从菜单栏/托盘找回。
- 最近 7 个计数日趋势、7 天正向目标、PNG 周报和有审计记录的双确认重置。
- 主记录与最后可用备份同时提交；损坏或未来版本数据不得被静默覆盖。

macOS 路线：运行 npm install、npm test、npm run build:mac。公开分发包必须区分 ad-hoc 本地构建与 Developer ID 签名、Apple 公证的正式 DMG。

Windows 路线：先运行 Windows/FlickyAshtray.Core.Tests，再构建 Windows/FlickyAshtray.Windows；公开体验包使用 win-x64 self-contained publish。Windows 界面必须在真实 Windows 10/11 上检查托盘、透明窗口、多屏、125%/150% 缩放、中文字体和 SmartScreen 边界。

修改时以现有测试和行为为真源，只做完成本次目标所需的最小完整改动。完成后告诉我：改了什么、哪些测试实际通过、成品的绝对路径、SHA-256，以及还有哪些只能在目标系统实测的边界。
```

如果只是想在源码基础上做自己的非商业小版本，可以在最后补一句具体变化，例如：“保留所有数据规则，只把桌宠视觉换成我提供的原创素材。”
