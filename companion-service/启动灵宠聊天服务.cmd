@echo off
setlocal
cd /d "%~dp0"
if not exist ".env" (
  echo 没有找到 .env，先执行: copy .env.example .env
  echo 然后把 DeepSeek 密钥填到 LLM_API_KEY。
)
python server.py
pause
endlocal
