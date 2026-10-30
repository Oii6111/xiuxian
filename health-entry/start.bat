@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist .env (
    echo 未找到 .env，先复制一份并填入密钥：
    echo   copy .env.example .env
    echo 然后编辑 .env 设置 LLM_API_KEY。
    pause
    exit /b 1
)
echo 正在启动服务，浏览器打开 http://127.0.0.1:8000
python server.py
