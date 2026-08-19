# CalmBar 🌬️

> **macOS 全能系统增强套件** —— 硬件温控 · 菜单栏收纳 · 鼠标滚轮解耦 · 媒体启动拦截 · 系统防休眠防离开 · 充电管理与电池上限 · 应用去隔离授权 · 屏幕文字与二维码识别 · 剪贴板历史管理 · 软件卸载与开发者环境深度清理

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
8. **屏幕信息快速提取与归档**：无需安装庞大第三方 OCR 软件，CalmBar 原生集成 Apple Vision 深度学习识别引擎，支持屏幕选区识字、二维码/条码解析与历史管理。
9. **剪贴板碎片化与数据丢失**：原生剪贴板仅保留单次复制，CalmBar 提供多模态格式捕获、图片智能升格、Vision OCR 文字/二维码索引与隐私过滤。
10. **应用卸载残留与开发缓存积压**：原生拖进废纸篓只带走主程序，散落在 Library 中的几个 GB 偏好与缓存依然霸占硬盘；Xcode/Node/Python 等工具链缓存及已被删除工程的历史工作区日积月累，CalmBar 提供一键应用深层卸载与开发者环境专属清理。

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

### 8. 🔤 屏幕文字与二维码识别 (Vision OCR & History)
* **Apple 原生深度学习引擎**：基于 macOS 原生 `Vision` 框架深度学习高精模型，零第三方二进制体积，极低内存消耗。
* **多语言与中英混排**：原生适配简体中文、繁体中文、英语、日语、韩语自动识别与代码混排，杜绝符号与汉字乱码。
* **二维码 / 条形码并发解析**：同时检测选区内文本与二维码/条码内容，支持网址识别一键 Safari 直达。
* **历史持久化与容量控制**：支持搜索、分类筛选、单项删除、一键清空与 50~500 条最大保留上限。
* **舒适毛玻璃悬浮窗**：高对比度排版、一键复制、删除记录，支持在偏好设置中自由配置自动倒计时消失（5s~60s）或常驻。

### 9. 📋 剪贴板历史记录与智能识别 (Clipboard History)
* **多模态全格式监听**：纯文本、富文本 (RTF/HTML)、系统截图/复制图像、访达图片/文件 URL、网页链接、十六进制颜色代码等。
* **访达图片智能升格与缩略图**：复制图片文件时自动升格为图片类型并生成高清缩略图与尺寸信息。
* **Vision OCR 后台索引**：自动提取图片中的多语言文字与二维码内容，配合空间感知隔离算法消除噪点，支持全局关键词检索。
* **安全隐私过滤**：自动忽略密码管理器（1Password/Bitwarden/KeePassXC）敏感数据及瞬态复制。
* **独立管理窗口与 Pin 固定**：支持分类筛选、Pin 固定保护、LRU 淘汰与磁盘缓存管理。

### 10. 🗑️ 软件卸载与开发者深度清理 (App & Developer Cleaner)
* **全量应用索引与架构识别**：多线程并发扫描已安装软件，提取图标、Bundle ID、安装体积、版本号及架构（Apple Silicon / Intel / Universal）。
* **深层残留嗅探引擎**：扫描 `~/Library` 与 `/Library` 下 20+ 个目录，基于 Bundle ID 衍生前缀、名称变体及安全排除列表精准匹配残留。
* **完全免密安全移入废纸篓**：多层级静默回退，全流程无需输入密码，误删可直接在废纸篓放回原处。
* **24+ 款主流开发工具链缓存清理**：覆盖 Xcode（`DerivedData`、`Archives`、`CoreSimulator` 模拟器等）、Node（Npm/Pnpm/Yarn/Bun/Deno）、Python（Pip/Poetry/Uv/Conda）、Rust（Cargo）、Go、Java（Gradle/Maven）、Flutter 等。
* **IDE 孤立工作区清理**：自动探测 VS Code / Cursor 中工程源码已被删除的历史孤立工作区缓存，支持一键批量清理释放数 GB 磁盘空间。
* **Pip 全局包管理**：自动探测 Python 3 环境，列出全局第三方包体积并支持多选批量一键卸载。

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
│       │   ├── Cleaner/                 # 应用卸载分析、残留嗅探、开发工具链与工作区清理
│       │   ├── Clipboard/               # 剪贴板监听、安全过滤、OCR 索引与存储管理
│       │   ├── Gatekeeper/              # macOS 隔离属性与自签名修复引擎
│       │   ├── MenuBar/                 # 菜单栏折叠与布局管理器
│       │   ├── Scroll/                  # CGEventTap 滚轮事件拦截器与权限管理
│       │   ├── Thermal/                 # 温控轮询引擎与 XPC 通信客户端
│       │   ├── NoTunes/                 # Apple Music / iTunes 启动拦截引擎
│       │   ├── OCR/                     # Vision 文字与条码识别、历史持久化调度
│       │   └── UI/                      # SwiftUI 状态栏面板与偏好设置窗口
│       ├── CalmBarKit/                  # 硬件 SMC 读写与驱动通信共享库
│       └── CalmBarHelper/               # Root 特权辅助工具 (Privileged Helper)
└── doc/
    ├── RELEASE.md                       # 版本发布说明与更新日志
    └── 核心需求.md                       # 产品需求与架构说明文档
```

---

## 🚀 安装与启动方式

### 1. 下载与安装
下载 Release 发布的 `CalmBar.app`，将其拖入 `/Applications`（应用程序）文件夹中即可。

### 2. 首次运行授权（绕过 Gatekeeper 隔离）
由于本项目为个人独立开源软件，未集成 Apple 商业付费证书，在 macOS 上直接双击打开时，系统安全机制（Gatekeeper）可能会拦截并提示 **“应用程序已损坏，无法打开”** 或 **“无法验证开发者”**。

在终端（Terminal）中执行以下命令移除系统的隔离属性即可正常运行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/CalmBar.app
```

> 💡 **提示**：
> * 若应用放置在其他目录，请将路径替换为实际的 `CalmBar.app` 文件路径。
> * CalmBar 内部的 **「应用去隔离与签名」** 功能页面也支持直接拖拽任意 App 一键执行该修复操作。

---

## 🔐 系统权限配置说明

为保证功能正常运作，首次运行需授予以下权限：

1. **辅助功能权限 (Accessibility)**：
   * 用于系统级拦截并翻转外接鼠标滚轮事件，以及办公软件防离开 (Activity Simulator) 微动仿真。
   * 前往 **系统设置 -> 隐私与安全性 -> 辅助功能**，确保 **CalmBar** 处于开启状态。
2. **完全磁盘访问权限 (Full Disk Access - 可选建议)**：
   * 用于完整扫描 `~/Library/Containers` 及受保护目录下的应用残留文件。
3. **SMC 特权助手 (Fan Control & Battery Helper)**：
   * 用于向系统 SMC 寄存器写入风扇目标转速及电池充电阻断状态。
   * 点击 CalmBar 面板中的 **「一键激活」** 按钮，按系统提示输入开机密码即可一键安装特权服务。

---

## 📄 开源许可证与仓库

* **GitHub 仓库**：[https://github.com/chao-eng/CalmBar](https://github.com/chao-eng/CalmBar)
* **开源协议**：本项目基于 [Apache License 2.0](LICENSE) 许可证开源。

特别致谢开源社区优秀项目的启发与参考：
* [Pearcleaner](https://github.com/alienator88/Pearcleaner) (macOS App & Dev Cache Cleaner)
* [Aidente](https://github.com/aidente) (SMC Battery Charging Control)
* [Caffeine](https://github.com/caffeine-app) (by Tomas Franzén & Dominic Rodemer)
* [noTunes](https://github.com/tombonez/noTunes) (by Tom Taylor)
* [Scroll Reverser](https://pilotmoon.com/scrollreverser/) (by Pilotmoon)
* [Hidden Bar](https://github.com/dwarvesf/hidden) (by Dwarves Foundation)
* [AirPulse](https://github.com/chaoeng) (SMC Fan Controller)
