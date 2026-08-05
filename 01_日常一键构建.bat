@echo off
chcp 65001 >nul
title = Tweak 一键构建 (日常使用)
color 0A

REM 切到项目根
cd /d "%~dp0"

REM 刷新PATH
for /f "delims=" %%I in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%I"

if "%~1"=="" (
    set "COMMIT_MSG=auto build %date:~0,4%-%date:~5,2%-%date:~8,2% %time:~0,2%:%time:~3,2%"
) else (
    set "COMMIT_MSG=%~1"
)

echo.
echo ==============================================================
echo   🚀 Tweak 一键构建（日常使用）
echo   提交信息: %COMMIT_MSG%
echo ==============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Set-Location '%CD%'; .\PushAndBuild.ps1 -SkipAuthCheck -Msg '%COMMIT_MSG%' }"

echo.
pause
