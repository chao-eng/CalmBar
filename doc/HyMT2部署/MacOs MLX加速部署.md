# Hy-MT2 本地翻译服务部署指南 (macOS MLX 硬件加速版)

本项目提供专为 **Apple Silicon (M1/M2/M3/M4 系列芯片)** 量身定制的 **Hy-MT2-1.8B** 本地高速翻译服务。基于 Apple 官方开源的 **MLX 机器学习框架与 Metal GPU 硬件加速**，具备毫秒级冷启动、极低内存占用、按需自动加载与空闲内存深度释放能力。

---

## 🌟 方案核心优势

- ⚡ **原生 Metal GPU 加速**：基于 Apple MLX 框架直接调用 Apple Silicon 统一内存与 GPU 核心，单字生成延迟低至毫秒级。
- 🧠 **4-bit 深度量化**：仅需约 **1.2 GB** 统一内存即可全速运行，极速加载。
- 🌿 **按需加载与空闲释放 (Lazy Loading & Auto-Release)**：
  - **按需加载**：平时不常驻占用显存，首次收到翻译请求时毫秒级自动加载进显存。
  - **自动释放**：默认连续 **20 分钟** 无请求时，自动卸载模型并执行底层显存缓存清理（`mx.clear_cache()`），显存占用归零。
- 🔌 **兼容 OpenAI 标准接口**：原生提供 `/v1/chat/completions`、`/v1/models`、`/health` 接口，支持 SSE 流式实时打字机输出。
- 🔄 **macOS 后台守护进程**：集成 `launchd` 守护进程，开机静默自启、异常自动重启。

---

## 🛠️ 前置环境准备

1. **硬件要求**：搭载 Apple Silicon 芯片（M1 / M2 / M3 / M4 及其 Pro / Max / Ultra 系列）的 Mac 电脑。
2. **系统要求**：macOS 13.0 (Ventura) 及以上版本（推荐 macOS 14.0+ Sonoma / macOS 15.0+ Sequoia）。
3. **Python 3.11**：推荐使用 Homebrew 安装：
   ```bash
   brew install python@3.11
   ```

---

## 🚀 一键安装与启动

在当前目录下直接运行一键安装脚本：

```bash
cd doc/HyMT2部署
chmod +x install.sh
./install.sh
```

### 脚本自动执行流程：
1. 创建安装运行目录：`~/HyMT2-Server/`。
2. 自动构建专属 Python 3.11 独立虚拟环境（`venv`）。
3. 从国内清华大学镜像源高速安装 MLX (`mlx`, `mlx-lm`)、FastAPI、Uvicorn 等依赖。
4. 从国内 ModelScope（魔搭社区）高速下载 `Hy-MT2-1.8B-4bit` 量化模型权重。
5. 生成高性能 OpenAI 兼容 FastAPI 服务端（`app/server.py`）。
6. 配置并注册 macOS `launchd` 用户级守护进程（`~/Library/LaunchAgents/com.user.hymt2.server.plist`）。
7. 启动服务并自动执行双语翻译连通性测试。

---

## 🕹️ 服务管理命令

安装完成后，可在 `~/HyMT2-Server/` 目录下随时使用以下快捷脚本进行服务运维：

```bash
cd ~/HyMT2-Server

# 查看服务运行状态、PID、端口与健康度
./status.sh

# 测试翻译接口连通性与模型推理输出
./test.sh

# 启动服务
./start.sh

# 停止服务
./stop.sh

# 重启服务
./restart.sh

# 查看实时运行日志
tail -f logs/server.log
```

---

## ⚙️ 在 CalmBar 中配置接入

启动服务后，打开 **CalmBar 偏好设置** $\to$ **【智能翻译】** 标签页，填入以下参数：

| 配置项 | 推荐配置值 | 说明 |
| :--- | :--- | :--- |
| **API 基础地址 (Base URL)** | `http://localhost:8000/v1` 或 `http://127.0.0.1:8000/v1` | 本地 MLX 服务监听端点 |
| **模型名称 (Model)** | `Hy-MT2` | 默认模型名称 |
| **API Key** | *(留空)* | 本地服务无需鉴权 |
| **默认目标语言** | `中文 (zh)` | 支持在 38 种多语言中自由切换 |

点击 **【测试连接】** 按钮，验证网络延迟（通常为 10~30ms）与连通性。测试成功后，即可在任意 App 中双击 `⌘+C` 或按下 `⌥⌘T` 享受极致极速的本地 AI 划词翻译！

---

## 🧪 命令行验证示例 (cURL)

你也可以随时在终端中直接通过标准 cURL 请求测试流式翻译输出：

```bash
curl --location --request POST 'http://127.0.0.1:8000/v1/chat/completions' \
--header 'Content-Type: application/json' \
--data-raw '{
    "model": "Hy-MT2",
    "messages": [
        {
            "role": "user",
            "content": "Translate the following segment into Chinese, without additional explanation:\n\n Apple silicon is a series of system on a chip (SoC) and system in a package (SiP) processors designed by Apple Inc."
        }
    ],
    "stream": true
}'
```