@echo off
setlocal
if "%~1"=="" (
    echo 请将 MP3 或 WAV 文件拖到本文件上。
    pause
    exit /b 2
)
python "%~dp0mp3_to_pcm.py" "%~1"
echo.
pause
