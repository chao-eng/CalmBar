# CalmBar 🌬️

> **macOS 全能系统增强套件** —— 硬件温控 · 菜单栏收纳 · 鼠标滚轮解耦 · 媒体启动拦截 · 系统防休眠防离开 · 充电管理与电池上限 · 应用去隔离授权

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
5. **任务中断与通讯软件误判离开**：长任务、文件传输或挂机时屏幕自动熄屏休眠，且办公软件（Teams/Slack/飞书/钉钉）自动切 Away 状态，CalmBar 提供一键防休眠断言与智能防离开仿真。
6. **插电满电高压损伤电池**：长期插电使用电量持续处于 100% 极易导致电池损耗老化与鼓包，CalmBar 提供精准硬件级 80% 充电上限与适配器旁路供电。
7. **未签名与已损坏应用拦截**：外部下载软件常因 Gatekeeper 隔离标记报错无法打开，CalmBar 支持拖拽一键递归去隔离与 Ad-hoc 自签名修复。

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

### 5. ☕ 系统防休眠与办公软件防离开 (Caffeine / Keep Awake)
* **IOKit 原生电源断言**：通过 `kIOPMAssertPreventUserIdleDisplaySleep` 阻止显示器休眠、屏幕保护程序与系统睡眠，保障长耗时渲染、编译及下载任务不中断。
* **丰富定时预设**：支持无限期保持清醒，或设定 5m / 15m / 30m / 1h / 2h / 5h 定时倒计时，实时毫秒级倒计时显示。
* **办公软件防离开仿真 (Keep Apps Active)**：读取 `IOHIDSystem` 真实系统闲置时间，超时自动发送原地微幅 HID 事件，防止 Microsoft Teams、Slack、飞书、钉钉等协同工具自动判定为 Away/离开状态。
* **睡眠唤醒与锁屏自适应**：Mac 手动进入睡眠时自动退出，多用户锁屏注销时自动挂起，退出 CalmBar 时安全释放所有断言。

### 6. 🔋 充电管理与电池上限 (Battery Charge Limit)
* **硬件级充电阻断**：通过向 SMC 写入 `CH0C` / `CHTE` 寄存器精准控制充放电，达到设定阈值（默认 80%）后彻底切断流入电池电流，转由电源适配器直接旁路供电。
* **回差巡航模式 (Sailing Mode)**：支持配置回差跨度（如 75% ~ 80%），电量自然消耗回落至下限时才恢复涓流补电，避免在 80% 边缘反复高频微充。
* **临时充至 100% (Top Up)**：提供一键临时充满模式，放开限制充至满电后自动恢复设定上限，适合出门前临时蓄电。
* **电池健康监控**：实时展示电池健康度 (Health %)、循环计数 (Cycle Count)、电池实时温度及供电功率。

### 7. 🛡️ 未签名与已损坏应用一键授权 (Gatekeeper Quarantine Unlocker)
* **拖拽一键解锁**：直接将报错或未公证的 `.app`、文件夹拖入设置面板，自动执行 `xattr -rd com.apple.quarantine` 解除隔离。
* **深度自签名修复**：支持勾选「深度修复 (Ad-hoc 重签名)」，针对签名损坏或修改过的应用执行 `codesign --force --deep --sign -`。
* **免终端无感提权**：结合特权助手 `CalmBarHelper`，处理 `/Applications` 下需要管理员权限的应用时无需反复输入 `sudo` 密码。

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
│       │   ├── Battery/                 # IOPowerSources 电池监听与充电上限状态机
│       │   ├── Caffeine/                # IOKit 电源断言与 HID 微动防离开引擎
│       │   ├── Gatekeeper/              # macOS 隔离属性与自签名修复引擎
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
   * 用于系统级拦截并翻转外接鼠标滚轮事件，以及办公软件防离开 (Activity Simulator) 微动仿真。
   * 前往 **系统设置 -> 隐私与安全性 -> 辅助功能**，确保 **CalmBar** 处于开启状态。
2. **SMC 特权助手 (Fan Control & Battery Helper)**：
   * 用于向系统 SMC 寄存器写入风扇目标转速及电池充电阻断状态。
   * 点击 CalmBar 面板中的 **「一键激活」** 按钮，按系统提示输入开机密码即可一键安装特权服务。

---

## 📄 开源许可证与仓库

* **GitHub 仓库**：[https://github.com/chao-eng/CalmBar](https://github.com/chao-eng/CalmBar)
* **开源协议**：本项目基于 [Apache License 2.0](LICENSE) 许可证开源。

特别致谢开源社区优秀项目的启发与参考：
* [Aidente](https://github.com/aidente) (SMC Battery Charging Control)
* [Caffeine](https://github.com/caffeine-app) (by Tomas Franzén & Dominic Rodemer)
* [noTunes](https://github.com/tombonez/noTunes) (by Tom Taylor)
* [Scroll Reverser](https://pilotmoon.com/scrollreverser/) (by Pilotmoon)
* [Hidden Bar](https://github.com/dwarvesf/hidden) (by Dwarves Foundation)
* [AirPulse](https://github.com/chaoeng) (SMC Fan Controller)

