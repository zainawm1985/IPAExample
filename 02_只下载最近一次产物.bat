@echo off
chcp 65001 >nul
title = 只下载最近一次 Actions 产物
color 0E

cd /d "%~dp0"
for /f "delims=" %%I in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%I"

echo.
echo ==============================================================
echo   📥 不 push 代码，只下载最近一次 Actions 的 Artifact
echo ==============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Set-Location '%CD%'; .\PushAndBuild.ps1 -SkipAuthCheck -NoPush }"

echo.
pause
