@echo off
chcp 65001 >nul
title = Tweak 一键登录 + 首次构建
color 0B

echo.
echo ==============================================================
echo   🚀  第一步：GitHub 登录 (只需运行一次)
echo ==============================================================
echo.
echo 接下来会打开浏览器让你授权 GitHub CLI，按提示做就行：
echo   1. 等下会出现一串 8 位字母数字码（比如 ABCD-1234）
echo   2. 会自动打开浏览器 https://github.com/login/device
echo   3. 页面里粘贴那个码
echo   4. 选 "Authorize github" 就好了
echo.
pause

REM 刷新PATH
for /f "delims=" %%I in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%I"

echo.
echo --- 启动 gh auth login ---
gh auth login --scopes "repo,workflow,read:org,admin:public_key,write:public_key" --hostname github.com --web

if errorlevel 1 (
    echo.
    echo ❌ 登录失败，自己手动跑一次：gh auth login --web
    pause
    exit /b 1
)

echo.
echo ✅ 登录成功！验证一下：
gh auth status

echo.
echo.
echo ==============================================================
echo   🚀  第二步：初始化 git 仓库 + 首次 push + 自动构建下载
echo ==============================================================
echo.
REM 切到脚本所在目录（就是项目根目录）
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File PushAndBuild.ps1 -SkipAuthCheck -Msg "首次提交：MyTweak源码 + GitHub Actions 云编译配置"

echo.
echo ==============================================================
echo  🎉 全部完成！
echo ==============================================================
pause
