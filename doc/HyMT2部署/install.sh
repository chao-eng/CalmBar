#!/bin/bash

set -e


APP_NAME="Hy-MT2 Server"

INSTALL_DIR="$HOME/HyMT2-Server"

MODEL_DIR="$INSTALL_DIR/models/Hy-MT2-1.8B-4bit"

VENV_DIR="$INSTALL_DIR/runtime/venv"

PORT=8000


PYTHON_VERSION="python3.11"


MODEL_ID="bujidc/mlx-community_Hy-MT2-1.8B-4bit"


echo "================================"
echo " Hy-MT2 Server Installer"
echo "================================"


#################################
# 创建目录
#################################

mkdir -p "$INSTALL_DIR"

mkdir -p "$INSTALL_DIR/models"

mkdir -p "$INSTALL_DIR/logs"

mkdir -p "$INSTALL_DIR/app"


cd "$INSTALL_DIR"


#################################
# 检查 Python
#################################

echo

echo "Python check"


if ! command -v $PYTHON_VERSION >/dev/null 2>&1
then
    echo "ERROR: python3.11 not found"

    echo "Install:"
    echo "brew install python@3.11"

    exit 1
fi


$PYTHON_VERSION --version



#################################
# 创建虚拟环境
#################################


if [ ! -d "$VENV_DIR" ]
then

    echo
    echo "Create python virtual environment"


    mkdir -p runtime


    $PYTHON_VERSION -m venv "$VENV_DIR"

else

    echo "venv exists"

fi



source "$VENV_DIR/bin/activate"



#################################
# pip
#################################


echo
echo "Upgrade pip"


pip install \
pip==25.3 \
-i https://pypi.tuna.tsinghua.edu.cn/simple



#################################
# requirements
#################################


cat > requirements.txt <<EOF

mlx==0.32.1
mlx-lm==0.31.3
mlx-metal==0.32.1

fastapi==0.116.1
uvicorn==0.35.0

transformers==5.5.0
sentencepiece==0.2.0
protobuf==5.29.3

modelscope==1.39.0
huggingface-hub>=1.5.0

numpy==2.2.4

EOF



echo
echo "Install python dependencies"


pip install \
-r requirements.txt \
-i https://pypi.tuna.tsinghua.edu.cn/simple



#################################
# 下载模型
#################################


echo
echo "Check model"


if [ -f "$MODEL_DIR/config.json" ]
then

    echo "Model exists"

else


    echo "Download model"


    python <<EOF

from modelscope import snapshot_download

snapshot_download(
    "$MODEL_ID",
    local_dir="$MODEL_DIR"
)

EOF


fi



#################################
# app/server.py
#################################

echo
echo "Create app/server.py"

cat > app/server.py <<'EOF'
import os
import gc
import json
import time
import uuid
import re
import threading
from typing import Optional, Tuple, List, Any

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

import mlx.core as mx
from mlx_lm import load, generate
import mlx_lm.sample_utils as su


# ==================================================
# Config
# ==================================================

BASE_DIR = os.path.dirname(
    os.path.dirname(
        os.path.abspath(__file__)
    )
)

MODEL_PATH = os.environ.get(
    "MODEL_PATH",
    os.path.join(
        BASE_DIR,
        "models",
        "Hy-MT2-1.8B-4bit"
    )
)

# 默认 20 分钟无请求自动释放 (单位: 秒)
IDLE_TIMEOUT_SECONDS = int(os.environ.get("IDLE_TIMEOUT", 20 * 60))
CHECK_INTERVAL_SECONDS = 10


# ==================================================
# Model Lifecycle Manager (First Principles)
# ==================================================

class ModelManager:
    """
    第一性原理模型生命周期管理器：
    1. 按需加载 (Lazy/On-demand Loading)：有请求时若模型不在内存则自动加载。
    2. 活性追踪 (Activity Tracking)：每次请求/推理完成均刷新最后活跃时间戳。
    3. 线程安全 (Thread Safety)：通过锁保证并发访问、加载与卸载的互斥与安全。
    4. 彻底释放 (Deep Memory Free)：空闲超时后解构 Python 对象并调用 gc.collect() 与 mx.clear_cache()。
    """

    def __init__(
        self,
        model_path: str,
        idle_timeout: int = IDLE_TIMEOUT_SECONDS,
        check_interval: Optional[int] = None
    ):
        self.model_path = model_path
        self.idle_timeout = idle_timeout
        self.check_interval = check_interval or max(1, min(CHECK_INTERVAL_SECONDS, idle_timeout // 2))

        self._model = None
        self._tokenizer = None
        self._last_active_time: float = time.time()
        self._lock = threading.Lock()

        # 启动后台空闲检测守护线程
        self._monitor_thread = threading.Thread(
            target=self._idle_monitor_loop,
            daemon=True,
            name="ModelIdleMonitor"
        )
        self._monitor_thread.start()

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    @property
    def idle_seconds(self) -> float:
        return time.time() - self._last_active_time

    def touch(self):
        """刷新最后活跃时间戳"""
        self._last_active_time = time.time()

    def get_model(self) -> Tuple[object, object]:
        """
        获取模型和分词器。
        若模型尚未加载或已被卸载，则在锁内执行按需加载。
        """
        with self._lock:
            if self._model is None:
                print("=" * 50)
                print(f"[ModelManager] Loading model from: {self.model_path}")
                start_t = time.time()
                self._model, self._tokenizer = load(self.model_path)
                load_cost = time.time() - start_t
                print(f"[ModelManager] Model successfully loaded in {load_cost:.2f}s")
                print("=" * 50)

            self.touch()
            return self._model, self._tokenizer

    def unload(self, reason: str = "idle timeout"):
        """
        卸载模型并彻底释放 Unified Memory 及 Metal 显存缓存。
        """
        with self._lock:
            if self._model is None:
                return

            print("=" * 50)
            print(f"[ModelManager] Unloading model (Reason: {reason})")
            start_t = time.time()

            del self._model
            del self._tokenizer
            self._model = None
            self._tokenizer = None

            # 触发 Python 垃圾回收
            gc.collect()

            # 清理 MLX 统一内存 / Metal 显存缓存池
            if hasattr(mx, "clear_cache"):
                mx.clear_cache()
            elif hasattr(mx, "metal") and hasattr(mx.metal, "clear_cache"):
                mx.metal.clear_cache()

            unload_cost = time.time() - start_t
            print(f"[ModelManager] Model unloaded and Metal cache cleared in {unload_cost:.2f}s")
            print("=" * 50)

    def _idle_monitor_loop(self):
        """
        后台守护线程：定期检查空闲时间，达到超时时间且模型在内存中时触发自动释放。
        """
        while True:
            time.sleep(self.check_interval)
            if self.is_loaded:
                idle_time = time.time() - self._last_active_time
                if idle_time >= self.idle_timeout:
                    print(f"[ModelManager] Inactive for {idle_time:.1f}s (>= {self.idle_timeout}s). Triggering auto-unload.")
                    self.unload(reason=f"idle for {int(idle_time)}s")


# 初始化全局模型管理器
model_manager = ModelManager(
    model_path=MODEL_PATH,
    idle_timeout=IDLE_TIMEOUT_SECONDS
)

# 启动时预先加载模型
print("=" * 50)
print(f"Initializing Hy-MT2 Server (Auto-unload after {IDLE_TIMEOUT_SECONDS}s idle)")
print("=" * 50)
model_manager.get_model()


# ==================================================
# FastAPI App
# ==================================================

app = FastAPI(
    title="Hy-MT2 OpenAI API"
)


# ==================================================
# Request Model
# ==================================================

class ChatRequest(BaseModel):
    model: str = "Hy-MT2"
    messages: list
    stream: bool = False
    max_tokens: Optional[int] = 4096
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 0.6
    top_k: Optional[int] = 20
    repetition_penalty: Optional[float] = 1.05


# ==================================================
# Prompt Builder
# ==================================================

def build_prompt(messages: list, tokenizer: Any) -> str:
    """
    使用官方 chat_template 生成 Hy-MT2 的专用结构化 Prompt。
    包含特殊 Token <｜hy_begin▁of▁sentence｜>, <｜hy_User｜>, <｜hy_Assistant｜> 等，
    防止模型因识别不到边界而出现重复回答/幻觉问题。
    """
    if hasattr(tokenizer, "apply_chat_template"):
        return tokenizer.apply_chat_template(
            messages,
            add_generation_prompt=True,
            tokenize=False
        )

    # 兜底纯文本构建
    text = ""
    for msg in messages:
        if msg.get("role") == "user":
            text += msg.get("content", "")
    return text.strip()


# ==================================================
# Inference (Thread-safe MLX Execution)
# ==================================================

def inference(
    prompt: str,
    max_tokens: int = 4096,
    temperature: float = 0.7,
    top_p: float = 0.6,
    top_k: int = 20,
    repetition_penalty: float = 1.05
) -> str:
    # 1. 确保模型处于加载状态
    model, tokenizer = model_manager.get_model()

    # 2. 构建官方推荐采样器与重复惩罚处理器
    sampler = su.make_sampler(temp=temperature, top_p=top_p, top_k=top_k)
    logits_processors = su.make_logits_processors(repetition_penalty=repetition_penalty)

    # 3. 锁内执行生成（保持在当前调用线程以确保 MLX GPU Context 稳定）
    with model_manager._lock:
        result = generate(
            model,
            tokenizer,
            prompt,
            max_tokens=max_tokens,
            sampler=sampler,
            logits_processors=logits_processors
        )
        model_manager.touch()

    return result.strip()


# ==================================================
# Streaming Generator (SSE Protocol Compatible)
# ==================================================

def split_text_chunks(text: str) -> List[str]:
    """将文本切分为适合流式传输的自然块（中文字符、英文词汇、标点）"""
    # 匹配英文单词、中日韩单个文字、空格或标点符号
    pattern = r'[\u4e00-\u9fa5]|\b[A-Za-z0-9_\'-]+\b|[^\w\s]|[\s]+'
    tokens = re.findall(pattern, text)
    return tokens if tokens else [text]


def stream_generator(
    text: str,
    model_name: str
):
    chat_id = "chatcmpl-" + str(uuid.uuid4())
    created = int(time.time())

    tokens = split_text_chunks(text)
    for token in tokens:
        chunk = {
            "id": chat_id,
            "object": "chat.completion.chunk",
            "created": created,
            "model": model_name,
            "choices": [
                {
                    "index": 0,
                    "delta": {
                        "content": token
                    },
                    "finish_reason": None
                }
            ]
        }
        yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"

    # 发送 stop 结束块
    final_chunk = {
        "id": chat_id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": model_name,
        "choices": [
            {
                "index": 0,
                "delta": {},
                "finish_reason": "stop"
            }
        ]
    }
    yield f"data: {json.dumps(final_chunk, ensure_ascii=False)}\n\n"
    yield "data: [DONE]\n\n"


# ==================================================
# OpenAI Chat API
# ==================================================

@app.post("/v1/chat/completions")
async def chat(req: ChatRequest):
    _, tokenizer = model_manager.get_model()
    prompt = build_prompt(req.messages, tokenizer)

    max_tokens = req.max_tokens if req.max_tokens is not None else 4096
    temperature = req.temperature if req.temperature is not None else 0.7
    top_p = req.top_p if req.top_p is not None else 0.6
    top_k = req.top_k if req.top_k is not None else 20
    repetition_penalty = req.repetition_penalty if req.repetition_penalty is not None else 1.05

    # MLX GPU context 保持在主调用线程执行，避免跨线程 Stream 异常
    result = inference(
        prompt=prompt,
        max_tokens=max_tokens,
        temperature=temperature,
        top_p=top_p,
        top_k=top_k,
        repetition_penalty=repetition_penalty
    )

    if req.stream:
        return StreamingResponse(
            stream_generator(
                text=result,
                model_name=req.model
            ),
            media_type="text/event-stream"
        )

    return {
        "id": "chatcmpl-" + str(uuid.uuid4()),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": req.model,
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": result
                },
                "finish_reason": "stop"
            }
        ]
    }


# ==================================================
# Models API
# ==================================================

@app.get("/v1/models")
async def models():
    return {
        "object": "list",
        "data": [
            {
                "id": "Hy-MT2",
                "object": "model"
            }
        ]
    }


# ==================================================
# Health API
# ==================================================

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model_loaded": model_manager.is_loaded,
        "idle_seconds": round(model_manager.idle_seconds, 1),
        "idle_timeout_seconds": model_manager.idle_timeout
    }
EOF



#################################
# start.sh
#################################


cat > start.sh <<EOF
#!/bin/bash


APP_DIR="$INSTALL_DIR"

PORT=$PORT


source \$APP_DIR/runtime/venv/bin/activate


if lsof -i:\$PORT >/dev/null 2>&1
then

echo "ERROR: Port \$PORT already in use"

lsof -i:\$PORT

exit 1

fi



echo "================================"
echo " Start Hy-MT2 API Server"
echo " Port: \$PORT"
echo "================================"


cd \$APP_DIR


nohup uvicorn app.server:app \\
--host 0.0.0.0 \\
--port \$PORT \\
--workers 1 \\
> logs/server.log 2>&1 &



echo \$! > logs/server.pid


echo

echo "Started PID:"
cat logs/server.pid


EOF



chmod +x start.sh



#################################
# stop.sh
#################################


cat > stop.sh <<EOF
#!/bin/bash


APP_DIR="$INSTALL_DIR"

cd \$APP_DIR


if [ -f logs/server.pid ]
then

PID=\$(cat logs/server.pid)

kill \$PID

rm logs/server.pid


echo "Stopped (PID: \$PID)"

else

echo "Not running"

fi


EOF


chmod +x stop.sh



#################################
# 完成
#################################


echo
echo "================================"
echo " Install Complete"
echo "================================"


echo

echo "Install dir:"
echo "$INSTALL_DIR"


echo

echo "Start:"
echo

echo "cd $INSTALL_DIR"

echo "./start.sh"

