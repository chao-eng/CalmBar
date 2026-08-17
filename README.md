# CalmBar 🌬️

> **macOS 全能系统增强套件** —— 硬件温控 · 菜单栏收纳 · 鼠标滚轮解耦 · 媒体启动拦截

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://apple.com/macos)
[![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-success.svg)](https://apple.com)
[![Language](https://img.shields.io/badge/language-Swift%206-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

---

## 📖 简介

**CalmBar** 是一款使用 **Swift 6 + SwiftUI + AppKit** 打造的轻量级 macOS 菜单栏综合增强套件。旨在解决日常 macOS 体验中的核心痛点：

1. **散热策略滞后**：官方 SMC 策略常常在撞温度墙后才大幅提速，CalmBar 提供实时硬件温度监控与灵活的温控加速曲线。
2. **菜单栏杂乱遮挡**：在刘海屏或小屏幕上，过多第三方图标容易溢出或被遮挡，CalmBar 提供一键折叠与自动收纳。
3. **鼠标与触控板手势绑定**：macOS 原生设置无法对外接鼠标与触控板分开设置滚动方向，CalmBar 完美解耦外接鼠标滚轮与原生触控板手势。
4. **Apple Music 流氓唤醒**：连接 AirPods / 蓝牙耳机或误触播放键时系统频繁强行弹出 Apple Music，CalmBar 毫秒级静默拦截并支持拉起替代音乐应用或网页。

---

## ✨ 核心功能

### 1. 🌡️ 硬件监控与智能风扇调控 (Thermal & Fan Control)
* **全芯片温度传感器覆盖**：原生适配 Apple Silicon（M1/M2/M3/M4 系列）及 Intel 芯片机型，实时读取 CPU 核心群簇、GPU 核心、电池与 SoC 模块温度。
* **三档调控模式**：
  * **自动 (Auto)**：重置为系统原生默认托管（SMC 官方策略）。
  * **自定义 (Manual)**：提供无级滑块，支持自由锁定指定转速百分比或 RPM。
  * **智能温控 (Smart Curve)**：基于起始加速温度与满速温度阈值，自动执行平滑插值加速曲线，高效静音散热。
* **多风扇控制策略**：双风扇机型支持“左右风扇联动调速”与“分别独立控制”。
* **故障安全机制 (Fail-Safe)**：软件退出、重启或异常崩溃时，自动将 SMC 控制权安全交还给 macOS 官方固件，绝不让硬件过热。

### 2. 🗂️ 菜单栏图标收纳 (Menu Bar Organizer)
* **优雅折叠与展开**：
  * 按住键盘 **Command (⌘)** 键，直接将需要隐藏的低频图标拖动到 **收纳分隔符 `/` 的左侧**。
  * 点击 **`<`** 箭头（或按下快捷键 `⌥ + ⌘ + H`），即可一键收起隐藏；再次点击即可展开。
* **开机静默收纳**：程序启动时默认保持折叠收纳状态，保持菜单栏清爽整洁。
* **自动化收纳**：支持配置“展开后无操作 N 秒自动折叠”与“鼠标悬停自动展开”。

### 3. 🖱️ 外接鼠标自然滚动解耦 (Scroll Reverser)
* **设备级独立配置**：
  * **外接鼠标**：强制反转垂直方向（Y 轴），恢复传统 Windows 风格滚轮滚动习惯。
  * **内建触控板 / Magic Mouse**：100% 保持 macOS 原生自然滚动方向、双指捏合缩放及惯性平滑滑动。
* **底层零延迟**：基于系统级 `CGEventTap` 与精确时序算法，平滑无卡顿。

### 4. 🎵 Apple Music / iTunes 启动拦截与替代 (noTunes)
* **静默拦截防御**：监听系统应用启动事件，瞬间强制终止 `com.apple.Music` 与 `com.apple.iTunes` 的自动唤起（如蓝牙耳机重连、媒体按键触碰等场景）。
* **无缝替代启动 (Replacement)**：
  * 支持自定义替代目标：拦截后自动拉起你指定的第三方音乐 App（如 Spotify、网易云音乐、QQ音乐、TIDAL、foobar2000 等）。
  * 支持配置网页版播放器（如 YouTube Music、Spotify Web、SoundCloud 等）。
* **零后台开销**：基于通知事件驱动，不轮询进程，0% CPU 占用。

---

## 🛠️ 技术架构

```text
CalmBar/
├── app/
│   ├── Package.swift                    # SPM 模块与依赖定义
│   ├── build_app.sh                     # 自动编译、签名与打包脚本
│   └── Sources/
│       ├── CalmBar/                     # 主 App 逻辑与 SwiftUI 界面
│       │   ├── AppDelegate.swift        # App 生命周期与菜单栏初始化
│       │   ├── MenuBar/                 # 菜单栏折叠与布局管理器
│       │   ├── Scroll/                  # CGEventTap 滚轮事件拦截器与权限管理
│       │   ├── Thermal/                 # 温控轮询引擎与 XPC 通信客户端
│       │   ├── NoTunes/                 # Apple Music / iTunes 启动拦截引擎
│       │   └── UI/                      # SwiftUI 状态栏面板与偏好设置窗口
│       ├── CalmBarKit/                  # 硬件 SMC 读写与驱动通信共享库
│       └── CalmBarHelper/               # Root 特权辅助工具 (Privileged Helper)
└── doc/
    └── 核心需求.md                       # 产品需求与架构说明文档
```

---

## 🚀 编译与运行指南

### 环境要求
* macOS 14.0 (Sonoma) 或更高版本 (兼容 macOS 15 Sequoia)
* Xcode 15.0+ 或 Swift 6.0+ 命令行工具

### 一键构建与启动

在项目终端中执行以下命令即可完成 Release 构建与 App 打包：

```bash
cd app
./build_app.sh
open ./build/CalmBar.app
```

构建脚本会自动生成 `./build/CalmBar.app` 并完成本地安全签名。

---

## 🔐 系统权限配置说明

为保证功能正常运作，首次运行需授予以下权限：

1. **辅助功能权限 (Accessibility)**：
   * 用于系统级拦截并翻转外接鼠标的滚轮事件。
   * 前往 **系统设置 -> 隐私与安全性 -> 辅助功能**，确保 **CalmBar** 处于开启状态。
2. **SMC 特权助手 (Fan Control Helper)**：
   * 用于向系统 SMC 寄存器写入风扇目标转速。
   * 点击 CalmBar 面板中的 **「一键激活」** 按钮，按系统提示输入开机密码即可一键安装特权服务。

---

## 📄 开源许可证

本项目基于 [Apache License 2.0](LICENSE) 许可证开源。

特别致谢开源社区优秀项目的启发与参考：
* [noTunes](https://github.com/tombonez/noTunes) (by Tom Taylor)
* [Scroll Reverser](https://pilotmoon.com/scrollreverser/) (by Pilotmoon)
* [Hidden Bar](https://github.com/dwarvesf/hidden) (by Dwarves Foundation)
* [AirPulse](https://github.com/chaoeng) (SMC Fan Controller)
