# Flicky Ashtray for Windows

这是 Flicky Ashtray 的原生 Windows 预览版。它不是网页套壳：系统托盘、透明桌宠、控制面板、本地数据和 PNG 周报都由 C# / WPF 实现。

## 第一次体验

1. 完整解压下载的 ZIP，不要直接在压缩包里双击。
2. 运行 `FlickyAshtray.exe`。
3. 先设置每日上限，点击“开始使用”。
4. 点击烟灰缸上的香烟，或便签右下角的同心圆，记录一根。
5. 悬停桌宠查看今日状态；拖动主体可以换位置，右键可以打开设置或隐藏桌宠。
6. 桌宠隐藏后，从任务栏右下角的托盘图标找回。

当前预览包自带 .NET 运行时，无需另外安装开发工具。它支持 Windows 10/11 x64。

## 首次启动提示

当前 GitHub 预览包尚未使用付费 Authenticode 证书签名，因此 Windows 可能显示“未知发布者”或 Microsoft Defender SmartScreen 提示。确认文件来自本仓库的 GitHub Release 并核对 SHA-256 后，可在“更多信息”中选择继续运行。

这只是预览发行边界，不代表应用需要管理员权限：Flicky Ashtray 以普通用户权限运行，不联网，也不会安装系统服务。

## 本地数据

记录位置：

```text
%LocalAppData%\Flicky Ashtray\store.json
```

同目录的 `store.json.bak` 是最后可用备份。删除程序文件不会自动删除你的记录；如需彻底移除，可在退出应用后手动删除整个 `Flicky Ashtray` 数据目录。

Windows 和 macOS 使用相同的 v8 JSON 数据结构。迁移数据前请先退出两端应用，并保留原文件备份。

## 这次请重点体验

- 烟灰缸与便签两种桌宠能否正常显示、缩放和拖动
- 点击一次只增加一根，快速双击不会重复记录
- 悬停状态卡、固定状态卡和托盘找回是否顺手
- 125%、150% 缩放以及多显示器下的位置是否合理
- 关闭控制面板后应用是否仍留在托盘
- 生成的 PNG 周报能否正常打开且中文没有缺字

发现问题时，请附上 Windows 版本、显示缩放比例、操作步骤和截图。

## 从源码构建

需要 .NET 10 SDK：

```powershell
dotnet run --project Windows/FlickyAshtray.Core.Tests/FlickyAshtray.Core.Tests.csproj -c Release
dotnet build Windows/FlickyAshtray.Windows/FlickyAshtray.Windows.csproj -c Release
dotnet publish Windows/FlickyAshtray.Windows/FlickyAshtray.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

源码与二进制只能按仓库许可证用于非商业目的。商业使用须事先取得版权所有者的书面许可。
