@echo off
rem spawn-windows.cmd TITLE RUNNER_PATH CONFIG_PATH
rem
rem Helper invoked by spawn.sh on Windows. Bypasses Git Bash → cmd quote
rem stripping that breaks `start "title" wt.exe ...` chains, and converts
rem Windows-style paths to forward-slash form so bash inside the spawned
rem tab does NOT treat backslashes as escape characters.

setlocal EnableDelayedExpansion
set "TITLE=%~1"
set "RUNNER=%~2"
set "CONFIG=%~3"

rem Convert backslashes to forward slashes so bash receives the paths intact.
set "RUNNER=!RUNNER:\=/!"
set "CONFIG=!CONFIG:\=/!"
set "TERM=xterm-256color"
set "COLORTERM=truecolor"

rem Try Windows Terminal first.
where /q wt.exe
if %ERRORLEVEL% EQU 0 (
  start "codex-launcher" wt.exe -w 0 nt --title "%TITLE%" bash "!RUNNER!" "!CONFIG!"
  exit /b 0
)

rem Fallback: plain cmd window.
start "%TITLE%" cmd /k "bash ""!RUNNER!"" ""!CONFIG!"""
exit /b 0
