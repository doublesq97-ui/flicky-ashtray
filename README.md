# Flicky Ashtray

一个安静地常驻在 macOS 桌面的吸烟记录小组件。可以选择烟灰缸或桌面便签，点一下记一根，悬停查看今天状态；所有数据只保存在本机。

Flicky Ashtray is a quiet macOS desktop smoking log. Choose an ashtray or compact note, tap once to log, hover for today’s status, and keep all data on-device.

## 功能 / Features

- 可配置每日上限（1–60，默认 8）与日切时间
- 跨日间隔、每个计数日一次撤销、7 日趋势
- 7 天正向目标、花朵进度与自定义奖励约定
- 原生生成最近 7 个计数日的 PNG 小结
- 周报导出自动跟随系统外观：浅色白蓝、深色黑绿
- 写明原因并双重确认的历史重置，保留本机审计记录
- 悬停查看、点击固定、右键隐藏、菜单栏恢复
- 烟灰缸／桌面便签两种桌宠外观，支持 60%–100% 缩放
- 桌面便签使用同心圆点烟器记一根，并自动跟随 macOS 浅深色
- 浅色／深色系统主题与减少动态支持
- 全本地 JSON 存储，无账号、无联网、无分析

## 原生实现 / Native implementation

应用使用 Swift、AppKit 与 SwiftUI。桌面只常驻透明无边框小桌宠；记录、趋势和设置位于按需打开的原生控制面板。窗口、菜单栏、系统材质、系统浅深色、关闭与最小化行为均由 macOS 原生 API 提供；代码与构建不依赖 WebView 或 Tauri。

## 开发 / Development

```bash
npm install
npm test
npm run build:mac
```

构建产物位于 `dist/Flicky Ashtray.app` 与 `dist/Flicky-Ashtray-0.4.0-arm64.dmg`。

需要 macOS 13 或更高版本与 Apple Silicon Mac。当前本地构建使用 ad-hoc 签名且未公证；从网络传到另一台 Mac 后，首次打开可能需要在“隐私与安全性”中确认。

## 安装 / Install

打开 `.dmg`，把 `Flicky Ashtray.app` 拖入 `Applications`。使用 Developer ID 签名并经过 Apple 公证的 GitHub Release 可以直接按这一流程安装；本地或未公证的预览构建会受到 Gatekeeper 提示。

## 数据与隐私 / Data & privacy

数据保存在 `~/Library/Application Support/Flicky Ashtray/store.json`，不会离开你的电脑。

## 作者 / Author

Sukiea1008（[@doublesq97-ui](https://github.com/doublesq97-ui)）

## 源码使用边界 / Source availability

这个仓库公开源代码，方便个人学习、研究、非商业修改与分享；它不是允许任意商用的 OSI 开源项目。

The source is publicly available for personal study, research, and other noncommercial use. This is not an OSI-approved open-source project and does not grant unrestricted commercial rights.

- 源码与文档：PolyForm Noncommercial 1.0.0
- `assets/` 中的图像：CC BY-NC 4.0
- 任何商业使用、商业分发或商业产品集成，须事先取得版权所有者的书面许可

完整条款见 [`LICENSE`](LICENSE) 与 [`assets/LICENSE.md`](assets/LICENSE.md)。商业授权可通过作者的 GitHub 主页联系。
