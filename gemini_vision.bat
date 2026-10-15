@echo off
rem Gemini web automation wrapper (tools\gemini_vision.py)
rem   gemini_vision.bat sync-profile
rem   gemini_vision.bat login
rem   gemini_vision.bat ask --image .vision\captures\Capture.PNG --prompt "critique this"
setlocal
set "UV_CACHE_DIR=%~dp0.uv-cache"
set "PYTHONIOENCODING=utf-8"
set "UV_EXE=D:\Tools\uv\uv.exe"
if not exist "%UV_EXE%" set "UV_EXE=uv"
"%UV_EXE%" run --with playwright python "%~dp0tools\gemini_vision.py" %*
