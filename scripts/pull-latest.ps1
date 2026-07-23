<#
.SYNOPSIS
    更新中央 AI config 的本地 clone（方案 B：chat.promptFilesLocations 用）。

.DESCRIPTION
    對本地 clone 執行 fetch/pull，回報有哪些設定檔變更。
    可用 -InstallSchedule 註冊 Windows 排程器每日自動執行。

    放置路徑：scripts/pull-latest.ps1

.PARAMETER Path
    中央 repo 的本地 clone 路徑。預設為此腳本所在 repo 的根目錄。

.PARAMETER InstallSchedule
    註冊 Windows 工作排程器每日執行本腳本。

.PARAMETER At
    -InstallSchedule 的執行時間，預設 09:00。

.PARAMETER Quiet
    無變更時不輸出（適合排程執行）。

.EXAMPLE
    .\pull-latest.ps1

.EXAMPLE
    .\pull-latest.ps1 -InstallSchedule -At 08:30
#>

[CmdletBinding()]
param(
    [string]$Path,
    [switch]$InstallSchedule,
    [string]$At = '09:00',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$TaskName = 'Sync AI Config (ai-config)'

if (-not $Path) { $Path = Split-Path -Parent $PSScriptRoot }

function Write-Step { param($m) if (-not $Quiet) { Write-Host "`n==> $m" -ForegroundColor Cyan } }
function Write-Ok   { param($m) if (-not $Quiet) { Write-Host "    OK   $m" -ForegroundColor Green } }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Fail       { param($m) Write-Host "    FAIL $m" -ForegroundColor Red; exit 1 }

# ---------- 註冊排程 ----------
if ($InstallSchedule) {
    $self = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Path `"$Path`" -Quiet"
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Description "每日更新中央 Copilot config 的本地 clone" -Force | Out-Null

    Write-Host "已註冊排程「$TaskName」，每日 $At 執行" -ForegroundColor Green
    Write-Host "移除：Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Gray
    exit 0
}

# ---------- 檢查 ----------
if (-not (Test-Path $Path)) { Fail "路徑不存在：$Path" }

Push-Location $Path
try {
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "不是 git repo：$Path" }

    if ((git status --porcelain).Length -gt 0) {
        Fail "本地 clone 有未提交的變更，請先處理。這個 clone 應該是唯讀使用，不要在此編輯。"
    }

    $branch = git branch --show-current
    $before = git rev-parse HEAD

    Write-Step "更新 $Path（$branch）"

    git fetch --quiet origin
    if ($LASTEXITCODE -ne 0) { Fail 'fetch 失敗，請檢查網路或認證' }

    git merge --ff-only "origin/$branch" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "無法 fast-forward（本地與遠端分歧）。建議：git reset --hard origin/$branch"
    }

    $after = git rev-parse HEAD

    if ($before -eq $after) {
        Write-Ok '已是最新版本'
        exit 0
    }

    # ---------- 回報變更 ----------
    $changed = git diff --name-only $before $after -- '.github/copilot-instructions.md' '.github/prompts' '.github/instructions'

    if (-not $Quiet) {
        Write-Ok "已更新：$($before.Substring(0,7)) -> $($after.Substring(0,7))"
        Write-Host ''
    }

    if ($changed) {
        Write-Host '  設定檔變更：' -ForegroundColor Yellow
        $changed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '  commit：' -ForegroundColor Gray
        git log --oneline --no-merges "$before..$after" | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

        if (Test-Path 'CHANGELOG.md') {
            Write-Host ''
            Write-Host '  CHANGELOG 開頭：' -ForegroundColor Gray
            Get-Content 'CHANGELOG.md' -TotalCount 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        }

        Write-Host ''
        Write-Warn 'VS Code 需重新載入視窗才會套用新的 prompt files（Ctrl+Shift+P -> Reload Window）'
    }
    else {
        Write-Ok '有新 commit，但設定檔本身未變更'
    }
}
finally {
    Pop-Location
}
