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
import json
import time
import uuid
import threading

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from mlx_lm import load, generate


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


print("=" * 50)
print("Loading Hy-MT2 model")
print(MODEL_PATH)
print("=" * 50)



model, tokenizer = load(
    MODEL_PATH
)


print("Model loaded")



app = FastAPI(
    title="Hy-MT2 OpenAI API"
)



# ==================================================
# MLX lock
# ==================================================

# MLX GPU context 不支持并发线程
# 所以必须锁住推理

generate_lock = threading.Lock()



# ==================================================
# Request Model
# ==================================================

class ChatRequest(BaseModel):

    model: str = "Hy-MT2"

    messages: list

    stream: bool = False



# ==================================================
# Prompt Builder
# ==================================================

def build_prompt(messages):

    """
    Hy-MT2:
    
    不使用 chat template
    不使用 system prompt
    
    直接 instruction + text

    """

    text = ""

    for msg in messages:

        role = msg.get(
            "role",
            ""
        )


        content = msg.get(
            "content",
            ""
        )


        if role == "user":

            text += content



    prompt = f"""
Translate the following text.

{text}

Translation:
"""


    return prompt.strip()



# ==================================================
# Inference
# ==================================================

def inference(prompt):


    with generate_lock:


        result = generate(
            model,
            tokenizer,
            prompt,

            # mlx-lm 0.31.3
            # 只支持这些基础参数

            max_tokens=512
        )


    return result.strip()



# ==================================================
# Streaming
# ==================================================

def stream_generator(text):


    chat_id = (
        "chatcmpl-"
        + str(uuid.uuid4())
    )


    # 模拟 OpenAI SSE

    for token in text.split():

        chunk = {

            "id": chat_id,

            "object":
            "chat.completion.chunk",


            "created":
            int(time.time()),


            "model":
            "Hy-MT2",


            "choices":[

                {

                    "index":0,


                    "delta":{

                        "content":
                        token + " "

                    },


                    "finish_reason":
                    None

                }

            ]

        }


        yield (
            "data: "
            +
            json.dumps(
                chunk,
                ensure_ascii=False
            )
            +
            "\n\n"
        )


    yield "data: [DONE]\n\n"



# ==================================================
# OpenAI Chat API
# ==================================================

@app.post(
    "/v1/chat/completions"
)
async def chat(req: ChatRequest):


    prompt = build_prompt(
        req.messages
    )


    #
    # 注意:
    #
    # 这里不能 async_to_thread
    # 
    # MLX GPU context 必须保持当前线程
    #

    result = inference(
        prompt
    )



    if req.stream:


        return StreamingResponse(

            stream_generator(
                result
            ),

            media_type=
            "text/event-stream"

        )



    return {


        "id":
        "chatcmpl-"
        +
        str(uuid.uuid4()),


        "object":
        "chat.completion",


        "created":
        int(time.time()),


        "model":
        req.model,


        "choices":[

            {

                "index":0,


                "message":{

                    "role":
                    "assistant",


                    "content":
                    result

                },


                "finish_reason":
                "stop"

            }

        ]

    }



# ==================================================
# Models API
# ==================================================

@app.get(
    "/v1/models"
)
async def models():


    return {


        "object":
        "list",


        "data":[

            {

                "id":
                "Hy-MT2",


                "object":
                "model"

            }

        ]

    }




# ==================================================
# Health
# ==================================================

@app.get(
    "/health"
)
async def health():

    return {

        "status":
        "ok"

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

