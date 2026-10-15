@echo off
rem Spawn a persistent warm ollama serve under the Vulkan env (does NOT taskkill).
rem Returns immediately at process spawn; the server keeps running for reuse.
setlocal
set OLLAMA_LLM_LIBRARY=vulkan
start "ollama-vulkan" /min D:\Ollama\ollama.exe serve
endlocal