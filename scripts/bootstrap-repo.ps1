<#
.SYNOPSIS
    把中央 AI config 的同步機制安裝進一個 repo。

.DESCRIPTION
    在目標 repo 中建立 .github/workflows/sync-ai-config.yml、設定 CENTRAL_AI_REPO 變數，
    並開一個 PR。預設不直接推 main，走 PR 流程。

    放置路徑：scripts/bootstrap-repo.ps1

.PARAMETER Path
    目標 repo 的本地路徑。預設為當前目錄。

.PARAMETER CentralRepo
    中央 repo，格式 owner/name。

.PARAMETER SetRepoVars
    在此 repo 設定 repo 層級的 CENTRAL_AI_REPO 變數。
    預設不設定 —— 認證與變數應在 org 層級統一管理（見中央 repo 的 ADR-001）。

.PARAMETER RunNow
    安裝後立即觸發一次同步（需 workflow 已在預設分支上，故通常配合 -NoPr 使用）。

.PARAMETER NoPr
    直接 commit 到當前分支，不開 PR。

.EXAMPLE
    .\bootstrap-repo.ps1 -Path C:\dev\my-project -CentralRepo M2Station/M2_AI_CONFIG

.EXAMPLE
    .\bootstrap-repo.ps1 -CentralRepo M2Station/M2_AI_CONFIG -NoPr -RunNow
#>

[CmdletBinding()]
param(
    [string]$Path = (Get-Location).Path,
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$CentralRepo,
    [switch]$SetRepoVars,
    [switch]$RunNow,
    [switch]$NoPr
)

$ErrorActionPreference = 'Stop'
$BranchName = 'chore/add-ai-config-sync'
$WorkflowPath = '.github/workflows/sync-ai-config.yml'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Fail       { param($m) Write-Host "    FAIL $m" -ForegroundColor Red; exit 1 }

# ---------- 前置檢查 ----------
Write-Step '前置檢查'

foreach ($cmd in 'git', 'gh') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "$cmd 未安裝或不在 PATH" }
}
Write-Ok 'git / gh 可用'

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login' }
Write-Ok 'gh 已登入'

if (-not (Test-Path $Path)) { Fail "路徑不存在：$Path" }
Push-Location $Path
try {
    git rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "不是 git repo：$Path" }

    $targetRepo = (gh repo view --json nameWithOwner -q .nameWithOwner 2>$null)
    if (-not $targetRepo) { Fail '無法取得 repo 資訊，請確認已設定 remote 且有存取權限' }
    Write-Ok "目標 repo：$targetRepo"

    if ($targetRepo -eq $CentralRepo) { Fail '目標 repo 就是中央 repo，不需要安裝同步機制' }

    if ((git status --porcelain).Length -gt 0) {
        Fail 'working tree 不乾淨，請先 commit 或 stash 既有變更'
    }
    Write-Ok 'working tree 乾淨'

    if (Test-Path $WorkflowPath) {
        Write-Warn "$WorkflowPath 已存在，將被覆蓋"
        $ans = Read-Host '    繼續？(y/N)'
        if ($ans -ne 'y') { Fail '使用者取消' }
    }

    # ---------- 取得 workflow 範本 ----------
    Write-Step '取得同步 workflow 範本'

    # 中央 repo 為 private，改用 gh api 取檔（沿用你已登入的 gh 憑證，不需另外準備 token）
    $tmp = New-TemporaryFile
    $apiPath = "repos/$CentralRepo/contents/templates/sync-ai-config.yml"
    gh api $apiPath -H "Accept: application/vnd.github.raw" > $tmp 2>$null
    if ($LASTEXITCODE -ne 0) {
        Fail "無法從 $CentralRepo 取得範本。請確認：(1) repo 名稱正確 (2) 你的帳號對該 repo 有讀取權限"
    }
    Write-Ok "已取得範本：$CentralRepo/templates/sync-ai-config.yml"

    $content = Get-Content $tmp -Raw
    if ($content -notmatch 'CENTRAL_AI_REPO') {
        Fail '下載到的範本內容不正確，請確認中央 repo 的 templates/sync-ai-config.yml'
    }

    # ---------- 寫入檔案 ----------
    Write-Step '寫入 workflow'

    $originalBranch = git branch --show-current
    if (-not $NoPr) {
        git switch -c $BranchName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "無法建立分支 $BranchName（可能已存在）" }
        Write-Ok "已建立分支 $BranchName"
    }

    New-Item -ItemType Directory -Force -Path '.github/workflows' | Out-Null
    Copy-Item $tmp $WorkflowPath -Force
    Remove-Item $tmp -Force
    Write-Ok $WorkflowPath

    # ---------- 設定 variable / secret ----------
    Write-Step '設定 repository variable / secret'

    # 已在 org 層級設好時就不必重複設定（repo 層級會覆蓋 org 層級，反而更難維護）
    $orgVar = (gh api "orgs/$($targetRepo.Split('/')[0])/actions/variables/CENTRAL_AI_REPO" 2>$null)
    if ($orgVar) {
        Write-Ok 'CENTRAL_AI_REPO 已在 org 層級設定，跳過 repo 層級設定'
    }
    elseif ($SetRepoVars) {
        gh variable set CENTRAL_AI_REPO --body $CentralRepo 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail '設定 CENTRAL_AI_REPO 失敗，請確認你對該 repo 有 admin 權限' }
        Write-Ok "CENTRAL_AI_REPO = $CentralRepo（repo 層級）"
    }
    else {
        Write-Warn 'org 層級未設定 CENTRAL_AI_REPO。請設定 org 變數，或加 -SetRepoVars 只設定這個 repo'
        Write-Warn '  gh variable set CENTRAL_AI_REPO --org <ORG> --visibility all --body "' + $CentralRepo + '"'
    }

    # ---------- commit / push ----------
    Write-Step '提交變更'

    git add $WorkflowPath
    git commit -m 'chore(ai): add central Copilot config sync' | Out-Null
    Write-Ok 'commit 完成'

    if ($NoPr) {
        git push
        if ($LASTEXITCODE -ne 0) { Fail 'push 失敗' }
        Write-Ok "已推送到 $originalBranch"
    }
    else {
        git push -u origin $BranchName
        if ($LASTEXITCODE -ne 0) { Fail 'push 失敗' }

        $prUrl = gh pr create --base $originalBranch --title 'chore(ai): add central Copilot config sync' --body @"
由 ``bootstrap-repo.ps1`` 產生。

## What
加入 ``$WorkflowPath``，從中央 repo ``$CentralRepo`` 同步 Copilot 設定。

## Why
集中維護通用規範與 prompt files（``/review``、``/pr``、``/release``），避免各 repo 分歧。

## 合併後還需要做
- [ ] Settings → Actions → General → 勾選「Allow GitHub Actions to create and approve pull requests」
- [ ] 手動觸發一次：``gh workflow run sync-ai-config.yml``
"@
        Write-Ok "PR 已建立：$prUrl"
    }

    # ---------- 後續提示 ----------
    Write-Step '完成'
    Write-Host @"
    後續步驟：
      1. Settings -> Actions -> General
         勾選「Allow GitHub Actions to create and approve pull requests」
      2. 合併後手動跑一次：gh workflow run sync-ai-config.yml
      3. 同步 PR 合併後即可使用 /review、/pr、/release
"@ -ForegroundColor Gray

    if ($RunNow) {
        if ($NoPr) {
            Write-Step '觸發首次同步'
            gh workflow run sync-ai-config.yml
            if ($LASTEXITCODE -eq 0) { Write-Ok '已觸發，用 gh run watch 追蹤' }
            else { Write-Warn '觸發失敗，可能是 workflow 尚未出現在預設分支上' }
        }
        else {
            Write-Warn '-RunNow 需搭配 -NoPr；workflow 必須先存在於預設分支才能觸發'
        }
    }
}
finally {
    Pop-Location
}
