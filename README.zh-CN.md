# BarPocket

**[简体中文](README.zh-CN.md) | [English](README.md)**

**一款轻量级 macOS 菜单栏整理工具，支持刘海屏感知管理和黑色刘海模式。**

BarPocket 帮助刘海屏 MacBook 释放菜单栏空间。它使用可拖动的分界线作为收纳区边界，提供一个可选的菜单栏管理器（读取 macOS Accessibility 暴露的菜单栏项目），还可以将顶部整行菜单栏背景变为黑色，让屏幕刘海自然融入其中。

> 当前发行版本面向 Apple Silicon（arm64），要求 macOS 13 或更高版本。应用使用 Ad-hoc 签名，**未经 Apple 公证**。下载前请阅读[安装与 Gatekeeper](#安装与-gatekeeper)。

## 功能特性

- **收起 / 展开：** 点击菜单栏中的开关，隐藏或显示被放入收纳区一侧的菜单栏项目。
- **手动整理：** 按住 `⌘`，将菜单栏项目拖过分界线。
- **菜单栏管理器：** 可选扫描正在运行的应用通过 `AXExtrasMenuBar` 暴露的菜单栏项目，支持搜索，并将项目分类为可见、被刘海遮挡或位于屏幕范围之外。
- **显式操作：** 对选中的项目尝试执行 `AXPress`；当 macOS 提供可用的位置时，也可以将可见项目移入收纳区，或恢复屏幕外的项目。
- **黑色刘海模式：** 在系统菜单栏窗口下方绘制一层横跨屏幕的黑色背景。该背景会忽略鼠标事件，因此原生菜单标题和状态栏项目仍可交互。
- **离线且轻量：** 不包含分析统计、遥测、网络服务、后台守护进程或第三方运行时依赖。

## 安装与 Gatekeeper

1. 打开 [GitHub Releases](https://github.com/tooandy/BarPocket/releases)，下载最新的 `BarPocket-*-arm64.dmg` 或 `.zip`。
2. 将 `BarPocket.app` 移动到 Applications（应用程序）目录，或 `~/Applications`。
3. 由于发行包**没有使用 Apple Developer ID 签名，也未经 Apple 公证**，macOS Gatekeeper 可能会阻止首次启动。如果 macOS 显示“无法验证开发者”之类的警告，可以在 Finder 中按住 Control 键点击应用并选择“打开”，或前往“系统设置 → 隐私与安全性”查看针对该应用的允许选项。具体提示会因 macOS 版本而异。
4. 基础分界线和黑色刘海模式不需要辅助功能权限。若要使用跨应用菜单栏管理器，请从 BarPocket 菜单中打开管理器，并在出现提示时授予辅助功能权限。

BarPocket 不会要求用户全局关闭 Gatekeeper。请只安装你信任的构建版本；源码和构建工作流均公开可供检查。

## 权限与安全

- **App Sandbox：** 未启用。当前沙盒配置不允许应用执行所需的跨进程辅助功能扫描。因此，应用进程拥有当前登录用户通常具备的文件和进程访问权限，并非被限制在独立容器中。
- **辅助功能（Accessibility）：** 可选。只有用户点击权限按钮后才会请求。用于读取菜单栏项目的描述和位置；用户明确触发操作时，可调用 `AXPress` 或模拟 Command 拖动。
- **不会请求：** 屏幕录制、输入监控、Apple Events 自动化、管理员权限或特权辅助进程。
- **网络：** 应用功能不使用网络连接。
- **签名：** 本地构建和公开发行包均使用 Ad-hoc 签名（`codesign --sign -`）。没有 Developer ID 身份、Apple 公证或装订的公证票据。

Ad-hoc 签名不提供稳定的 Developer ID 身份。因此，替换为新构建版本后，macOS 可能要求用户重新确认辅助功能权限。没有 Apple 开发者身份，就无法保证升级体验与 Developer ID 签名应用完全相同。

## 从源码构建

环境要求：Xcode Command Line Tools、Swift 编译器、macOS 13 或更高版本、Apple Silicon。

```sh
git clone https://github.com/tooandy/BarPocket.git
cd BarPocket
./build.sh
open dist/BarPocket.app
```

如需安装到 `~/Applications/BarPocket.app`：

```sh
./build.sh --install
```

构建脚本会运行内置布局自测、对应用进行 Ad-hoc 签名，并验证生成的应用包。不需要任何签名密钥或 Secrets。

## CI 与版本发布

- Pull Request 和推送到 `main` 分支时，会自动运行 macOS ARM64 构建、布局自测和代码签名验证。
- 推送 `v*` 格式的 Tag 时，会触发 Release 工作流：构建 Ad-hoc 签名应用，打包 ZIP 和 DMG，生成 `SHA256SUMS`，并发布 GitHub Release。
- 对公开仓库，GitHub 标准托管 Runner 在免费额度范围内可免费使用。不需要 Apple Developer 会员资格或签名 Secrets。

发布示例：

```sh
git tag v0.3.1
git push origin v0.3.1
```

Tag 版本必须与 `Info.plist` 中的 `CFBundleShortVersionString` 一致。

## 已知限制

- 管理器只能显示应用通过 `AXExtrasMenuBar` 暴露的菜单栏元素；部分应用和系统项目不会暴露这些信息。
- 由于不使用屏幕录制权限，列表显示的是所属应用的图标，而不是每个菜单栏图标的截图。
- macOS 没有公开 API 可以任意调整其他应用状态栏项目的顺序。移动操作采用由用户触发的 Command 拖动，属于尽力而为；部分应用或系统项目可能拒绝操作。
- 如果某个项目仍被刘海实体遮挡，在释放菜单栏空间之前，可能无法将它拖动出来。
- 黑色刘海背景依赖当前 Window Server 的菜单栏窗口层级关系。macOS 更新可能改变这一行为，需要在真实设备上验证。
- 当前黑色刘海模式并非主要针对外接显示器的菜单栏设计。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
