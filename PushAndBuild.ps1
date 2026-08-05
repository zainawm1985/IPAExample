<#
.SYNOPSIS
    一键脚本：本地修改 → git push → 等 GitHub Actions 跑完 → 下载 artifact 到 artifacts-fakesigned/
    使用方式:
        .\PushAndBuild.ps1                       # 提交当前所有修改，用默认commit msg
        .\PushAndBuild.ps1 -Msg "修复启动闪退"     # 自定义commit信息
        .\PushAndBuild.ps1 -NoPush                # 只下载最近一次Action的artifact(不push)
        .\PushAndBuild.ps1 -Repo zainawm1985/IPAExample  # 指定仓库
#>
param(
    [string]$Msg = "auto build $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    [switch]$NoPush = $false,
    [string]$Repo = "zainawm1985/IPAExample",
    [string]$Branch = "main",
    [string]$Workflow = "build.yml",
    [int]$TimeoutSec = 600,
    [string]$OutDir = "artifacts-fakesigned",
    [switch]$SkipAuthCheck = $false
)

$ErrorActionPreference = "Stop"

# ============ 1. 刷新 PATH ============
$env:PATH = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " 🚀 Tweak 自动构建 (Push → Actions → Download Artifact)"        -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " 仓库:     $Repo" -ForegroundColor Gray
Write-Host " 分支:     $Branch" -ForegroundColor Gray
Write-Host " Workflow: $Workflow" -ForegroundColor Gray
Write-Host " 输出目录: $OutDir" -ForegroundColor Gray
Write-Host ""

# ============ 2. 检查 gh 认证 ============
function Test-GhAuth {
    try {
        $result = & gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ gh CLI 已登录" -ForegroundColor Green
            return $true
        }
    } catch {}
    return $false
}

if (-not $SkipAuthCheck -and -not (Test-GhAuth)) {
    Write-Host ""
    Write-Host "⚠️  gh CLI 尚未登录 GitHub" -ForegroundColor Yellow
    Write-Host "请选择一种登录方式：" -ForegroundColor Yellow
    Write-Host "  [1] Token 登录 (推荐，最稳定)" -ForegroundColor White
    Write-Host "  [2] 浏览器登录 (交互)" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "请输入选项 (默认 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "获取 Token:  https://github.com/settings/tokens  → Generate new token (classic)" -ForegroundColor Cyan
        Write-Host "权限勾选:  repo, workflow, read:org, admin:public_key" -ForegroundColor Cyan
        $token = Read-Host "粘贴 GitHub Personal Access Token (classic)" -AsSecureString
        $plainToken = [System.Net.NetworkCredential]::new("", $token).Password
        if ([string]::IsNullOrWhiteSpace($plainToken)) {
            throw "Token 为空，取消登录"
        }
        $plainToken | & gh auth login --with-token 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "gh auth login 失败，请检查 Token 是否正确"
        }
    } else {
        & gh auth login --scopes "repo,workflow,read:org,admin:public_key" --web 2>&1 | Out-Host
    }

    if (-not (Test-GhAuth)) {
        throw "❌ 登录失败，脚本终止"
    }
}

# ============ 3. git 提交并推送 ============
$beforeCommitHash = ""
if (-not $NoPush) {
    Write-Host ""
    Write-Host "--- [1/5] git 提交并 push ---" -ForegroundColor Yellow

    # 初始化仓库（如果还没有）
    if (-not (Test-Path ".git")) {
        Write-Host "  初始化 git 仓库..." -ForegroundColor Gray
        git init -b $Branch 2>&1 | Out-Host
        git config user.name  "Tweak Builder" 2>&1 | Out-Null
        git config user.email "tweak@builder.local" 2>&1 | Out-Null
        git remote add origin "https://github.com/$Repo.git" 2>&1 | Out-Host
    } else {
        # 确保remote正确
        $existing = git remote get-url origin 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $existing.Contains($Repo)) {
            git remote remove origin 2>&1 | Out-Null
            git remote add origin "https://github.com/$Repo.git" 2>&1 | Out-Host
        }
    }

    # 确保当前在正确分支
    $curBranch = git branch --show-current
    if ($curBranch -ne $Branch) {
        git checkout -B $Branch 2>&1 | Out-Host
    }

    git add -A 2>&1 | Out-Null

    # 检查是否有变更
    $status = git status --porcelain
    if ($status -or -not (Test-Path ".git/refs/heads/$Branch") -or -not (git rev-parse HEAD 2>$null)) {
        Write-Host "  提交变更: $Msg" -ForegroundColor Gray
        git commit -m $Msg --allow-empty 2>&1 | Out-Host
    } else {
        Write-Host "  ⚠️  没有文件变更，使用最近一次commit触发Actions..." -ForegroundColor Yellow
        # 加一个空commit确保触发
        git commit --allow-empty -m "rebuild: $Msg" 2>&1 | Out-Host
    }

    $beforeCommitHash = git rev-parse HEAD
    Write-Host "  Commit hash: $beforeCommitHash" -ForegroundColor Gray

    # push (会用gh的凭据或windows凭据管理器)
    Write-Host "  git push origin $Branch ..." -ForegroundColor Gray

    # 用 GITHUB_TOKEN 环境变量优先，否则让Windows自动弹凭据窗口
    $pushSucceeded = $false
    for ($retry = 0; $retry -lt 3 -and -not $pushSucceeded; $retry++) {
        $pushOutput = git push -u origin $Branch --porcelain 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pushSucceeded = $true
            $pushOutput | Out-Host
        } else {
            # 可能是没登录，尝试用gh auth setup-git
            Write-Host "  push失败，尝试配置 git credentials via gh auth..." -ForegroundColor Yellow
            & gh auth setup-git 2>&1 | Out-Host
            Start-Sleep -Seconds 2
        }
    }

    if (-not $pushSucceeded) {
        throw "❌ git push 连续3次失败，请检查网络或凭据（用命令 'gh auth login' 手动登录）"
    }

    Write-Host "  ✅ push 成功" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "--- 跳过 push (NoPush 模式)，查询最近一次运行 ---" -ForegroundColor Yellow
    if (Test-Path ".git") {
        $beforeCommitHash = git rev-parse HEAD 2>$null
    }
}

# ============ 4. 等待 workflow 开始 ============
Write-Host ""
Write-Host "--- [2/5] 等待 GitHub Actions 启动 workflow ---" -ForegroundColor Yellow
$runUrl = ""
$runId  = ""
$watchStart = Get-Date
$targetHash = $beforeCommitHash

while ($true) {
    $elapsed = (Get-Date) - $watchStart
    if ($elapsed.TotalSeconds -gt 120) {
        throw "❌ 等了2分钟workflow还没启动，请去 GitHub 页面检查仓库是否有 Actions 权限"
    }

    $listJson = & gh run list --repo $Repo --workflow $Workflow --branch $Branch --limit 5 --json databaseId,status,headSha,createdAt,url,conclusion 2>$null
    if ($LASTEXITCODE -eq 0 -and $listJson) {
        $runs = $listJson | ConvertFrom-Json
        foreach ($r in $runs) {
            # 找到匹配commit hash或最近刚创建且状态不是已完成的
            $matchByHash = ($targetHash -and $r.headSha -eq $targetHash)
            $matchByRecent = (-not $targetHash -and $r.status -ne "completed")
            if ($matchByHash -or $matchByRecent) {
                $runId  = $r.databaseId
                $runUrl = $r.url
                Write-Host "  ✅ 找到 workflow run: #$runId (status=$($r.status))" -ForegroundColor Green
                Write-Host "     页面: $($r.url -replace 'api\.github\.com/repos','github.com' -replace '/runs/','/actions/runs/')" -ForegroundColor Gray
                break
            }
        }
        if ($runId) { break }
    }
    Write-Host "  等待Actions启动... ($($elapsed.ToString('ss'))秒)" -ForegroundColor Gray
    Start-Sleep -Seconds 5
}

# ============ 5. 等待 workflow 完成 ============
Write-Host ""
Write-Host "--- [3/5] 等待 Actions 运行完成 ---" -ForegroundColor Yellow
$buildStart = Get-Date
$lastStatus = ""

while ($true) {
    $elapsed = (Get-Date) - $buildStart
    if ($elapsed.TotalSeconds -gt $TimeoutSec) {
        throw "❌ Actions运行超时($TimeoutSec秒)，请去GitHub页面查看错误"
    }

    $runJson = & gh run view $runId --repo $Repo --json status,conclusion,url,headSha 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $runJson) {
        Start-Sleep -Seconds 5
        continue
    }
    $run = $runJson | ConvertFrom-Json

    if ($run.status -ne $lastStatus) {
        $ts = Get-Date -Format "HH:mm:ss"
        Write-Host "  [$ts] 状态: $($run.status)  结论: $($run.conclusion ?? '<pending>')" -ForegroundColor Gray
        $lastStatus = $run.status
    }

    if ($run.status -eq "completed") {
        if ($run.conclusion -eq "success") {
            Write-Host "  ✅ Actions 成功完成 (耗时 $($elapsed.ToString('mm\分ss\秒')))" -ForegroundColor Green
            break
        } else {
            # 打日志
            Write-Host "  ❌ Actions 失败！结论: $($run.conclusion)" -ForegroundColor Red
            Write-Host "  拉取失败日志:" -ForegroundColor Red
            & gh run view $runId --repo $Repo --log-failed 2>&1 | Select-Object -Last 200 | Out-Host
            $pageUrl = $run.url -replace 'api\.github\.com/repos','github.com' -replace '/runs/','/actions/runs/'
            Write-Host ""
            Write-Host "  完整日志页面: $pageUrl" -ForegroundColor Cyan
            throw "Actions 运行失败($($run.conclusion))，见上方日志"
        }
    }

    Start-Sleep -Seconds 10
}

# ============ 6. 下载 artifact ============
Write-Host ""
Write-Host "--- [4/5] 下载 artifact --> $OutDir ---" -ForegroundColor Yellow

if (Test-Path $OutDir) {
    Remove-Item $OutDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# 优先下 dylib artifact；同时尝试下载 injected_IPA
$dylibArtifact = "MyTweak_dylib_packages"
$ipaArtifact   = "MyTweak_injected_IPA"

Write-Host "  下载 Artifact [$dylibArtifact] ..." -ForegroundColor Gray
$dl1 = & gh run download $runId --repo $Repo --name $dylibArtifact --dir $OutDir 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ $dylibArtifact 下载完成" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  下载 $dylibArtifact 失败: $dl1" -ForegroundColor Yellow
}

# 尝试下载注入好的IPA（如果存在）
$dl2 = & gh run download $runId --repo $Repo --name $ipaArtifact --dir $OutDir 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ $ipaArtifact 下载完成 (已注入好的IPA)" -ForegroundColor Green
}

# ============ 7. 整理输出 ============
Write-Host ""
Write-Host "--- [5/5] 整理产物 ---" -ForegroundColor Yellow
Get-ChildItem -Recurse $OutDir | ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path $OutDir).Path.Length + 1)
    $sz = [math]::Round($_.Length/1KB, 1)
    Write-Host "   $rel  ($sz KB)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " 🎉 全部完成！产物在: $(Resolve-Path $OutDir)"                          -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " 下一步:" -ForegroundColor White
Write-Host "  • 如果只下载到 MyTweak.dylib → 用 Sideloadly 注入到目标IPA（推荐）" -ForegroundColor Gray
Write-Host "  • 如果下载到了 *_已注入_*.ipa → 直接拖进 TrollStore 安装即可" -ForegroundColor Gray
Write-Host ""
