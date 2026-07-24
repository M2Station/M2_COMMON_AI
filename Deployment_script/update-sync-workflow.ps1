<#
.SYNOPSIS
    掃描多個 GitHub repo 的同步 workflow，與中央範本比對；不同就開 PR 更新。

.DESCRIPTION
    針對清單內每個 repo，讀取其 .github/workflows/sync-m2-common-ai.yml，
    與中央 repo 的 templates/sync-m2-common-ai.yml 逐字比對（忽略 BOM 與行尾差異）：
      - 相同         → 回報 SAME，不動作
      - 不同         → 回報 DIFF
      - 缺少         → 回報 MISSING（下游尚未接入）
      - 無法存取     → 回報 INACCESSIBLE

    預設只掃描回報（dry-run），不對任何 repo 做寫入。
    加上 -Apply 才會對「不同／缺少」的 repo 自動 clone、開分支、覆寫該檔並開 PR。

    為什麼需要這支腳本：自動同步機制刻意不碰 .github/workflows/
    （下游的 GITHUB_TOKEN 無法寫入該目錄），所以中央 stub 結構升級時，
    這支 workflow 檔不會自己更新，必須由外部（本腳本）批次推 PR 升級。

    中央 repo 為 public，本腳本只用你本機 gh 的登入身分讀取與開 PR，
    不需要任何額外 token / secret。

    放置路徑：Deployment_script/update-sync-workflow.ps1

.PARAMETER Repo
    一或多個目標 repo，格式 owner/name。可用空白或逗號分隔多個。

.PARAMETER RepoFile
    改由檔案提供 repo 清單，一行一個 owner/name（或 GitHub URL）；# 開頭與空行忽略。
    可與 -Repo 併用，兩者會合併去重。

.PARAMETER CentralRepo
    中央 repo，格式 owner/name。預設 M2Station/M2_COMMON_AI。

.PARAMETER TemplatePath
    比對用的本地範本路徑。預設自動指向本腳本上層的 templates/sync-m2-common-ai.yml。

.PARAMETER Apply
    實際開 PR。未指定時只掃描回報，不對任何 repo 做寫入。

.PARAMETER Branch
    -Apply 時建立的分支名稱。預設 chore/upgrade-sync-workflow。

.PARAMETER Assignee
    -Apply 開 PR 時指派的 GitHub 帳號（可選）。

.EXAMPLE
    # 只掃描回報，不動任何 repo
    .\update-sync-workflow.ps1 M2Station/repo-a M2Station/repo-b

.EXAMPLE
    # 用清單檔掃描，並對不同的 repo 實際開 PR 更新
    .\update-sync-workflow.ps1 -RepoFile .\repos.txt -Apply

.EXAMPLE
    # 指定 PR assignee
    .\update-sync-workflow.ps1 -RepoFile .\repos.txt -Apply -Assignee oahsiao
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Repo,
    [string]$RepoFile,
    [ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$CentralRepo = 'M2Station/M2_COMMON_AI',
    [string]$TemplatePath,
    [switch]$Apply,
    [string]$Branch = 'chore/upgrade-sync-workflow',
    [string]$Assignee
)

$ErrorActionPreference = 'Stop'
$WorkflowPath = '.github/workflows/sync-m2-common-ai.yml'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Write-Diff { param($m) Write-Host "    DIFF $m" -ForegroundColor Magenta }
function Write-Info { param($m) Write-Host "    $m" -ForegroundColor Gray }
function Fail       { param($m) Write-Host "    FAIL $m" -ForegroundColor Red; exit 1 }

# 正規化：忽略開頭 BOM、行尾 CRLF/LF 與檔尾多餘換行，避免因換行風格不同而誤判為「不同」。
function Get-Normalized {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $Text = $Text -replace '^\uFEFF', ''
    $Text = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return $Text.TrimEnd("`n")
}

# 讀取下游 repo 的單一檔案（raw 內容）；檔案不存在或無權限時回 $null。
# 強制以 UTF-8 解碼 gh 的輸出，避免中文註解在 PowerShell 擷取時亂碼。
function Get-RemoteFile {
    param([string]$TargetRepo, [string]$FilePath)
    $prev = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $out = gh api "repos/$TargetRepo/contents/$FilePath" -H 'Accept: application/vnd.github.raw' 2>$null
        $ok = ($LASTEXITCODE -eq 0)
    }
    finally {
        [Console]::OutputEncoding = $prev
    }
    if (-not $ok) { return $null }
    return ($out -join "`n")
}

# 對單一 repo 開 PR 更新：clone → 建分支 → 覆寫該檔 → commit → push → 開 PR。
# 回傳 PR 網址。函式內把 EAP 降為 Continue 並自行檢查 $LASTEXITCODE，
# 以免 git/gh 寫 stderr 觸發 NativeCommandError 中斷整批。
function New-UpgradePr {
    param([string]$TargetRepo, [string]$DefaultBranch, [string]$TemplateFullPath)
    $ErrorActionPreference = 'Continue'

    # 已有同名的開啟中 PR 就別重複開，維持冪等。
    $existing = gh pr list --repo $TargetRepo --head $Branch --state open --json url --jq '.[0].url' 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Write-Warn "已有開啟中的 PR，略過開新的：$existing"
        return $existing
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('m2sync_' + [guid]::NewGuid().ToString('N'))
    $pushed = $false
    try {
        $cloneOut = gh repo clone $TargetRepo $tmp -- --depth 1 --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { throw "clone 失敗：$($cloneOut | Out-String)" }

        Push-Location $tmp
        $pushed = $true

        # 臨時 clone，設定本地 commit 身分（取自 gh 登入者），避免缺少 user.name/email 而 commit 失敗。
        $ghUser = gh api user --jq .login 2>$null
        if ($LASTEXITCODE -eq 0 -and $ghUser) {
            git config user.name  $ghUser | Out-Null
            git config user.email "$ghUser@users.noreply.github.com" | Out-Null
        }

        git switch -c $Branch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "無法建立分支 $Branch（可能已存在）" }

        New-Item -ItemType Directory -Force -Path '.github/workflows' | Out-Null
        Copy-Item $TemplateFullPath $WorkflowPath -Force

        git add $WorkflowPath 2>&1 | Out-Null
        if (-not (git status --porcelain)) {
            throw '覆寫後無變更（下游檔案其實已與範本相同，無需開 PR）'
        }
        git commit -m 'chore(ai): upgrade sync workflow to latest central template' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'commit 失敗' }

        $pushOut = git push -u origin $Branch 2>&1
        if ($LASTEXITCODE -ne 0) {
            $pushText = ($pushOut | Out-String)
            # 推 .github/workflows/ 需要 token 帶 workflow scope，否則會被 GitHub 拒絕。
            if ($pushText -match 'workflow.*scope') {
                throw 'push 被拒：gh token 缺少 workflow scope。請先執行 gh auth refresh -h github.com -s workflow 再重試'
            }
            throw "push 失敗：$pushText"
        }

        $body = @"
由 ``update-sync-workflow.ps1`` 自動產生。

## What
更新 ``$WorkflowPath`` 至中央 repo ``$CentralRepo`` 的最新範本（stub）。

## Why
中央同步 workflow 的 stub 結構有更新，而此檔不受自動同步覆蓋
（同步機制刻意不寫入 .github/workflows/），故以本 PR 一次性升級。
換過之後，未來同步「邏輯」變更會經中央 reusable workflow 自動生效，不必再改此檔。

## 合併後
- [ ] Settings -> Actions -> General -> 已勾選「Allow GitHub Actions to create and approve pull requests」
- [ ] 可手動觸發驗證：``gh workflow run sync-m2-common-ai.yml``
"@

        $ghArgs = @(
            'pr', 'create',
            '--repo', $TargetRepo,
            '--base', $DefaultBranch,
            '--head', $Branch,
            '--title', 'chore(ai): upgrade sync workflow to latest central template',
            '--body', $body
        )
        if ($Assignee) { $ghArgs += @('--assignee', $Assignee) }

        $prOut = gh @ghArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw "gh pr create 失敗：$($prOut | Out-String)" }
        return ($prOut | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)
    }
    finally {
        if ($pushed) { Pop-Location }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- 前置檢查 ----------
Write-Step '前置檢查'

foreach ($cmd in 'git', 'gh') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "$cmd 未安裝或不在 PATH" }
}
Write-Ok 'git / gh 可用'

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login' }
Write-Ok 'gh 已登入'

# ---------- 定位並讀取範本 ----------
if (-not $TemplatePath) {
    $TemplatePath = Join-Path $PSScriptRoot '..\templates\sync-m2-common-ai.yml'
}
if (-not (Test-Path $TemplatePath)) {
    Fail "找不到範本：$TemplatePath（請用 -TemplatePath 指定，或在中央 repo 內執行）"
}
$TemplateFullPath = (Resolve-Path $TemplatePath).Path
$templateNorm = Get-Normalized ([System.IO.File]::ReadAllText($TemplateFullPath))
if (-not $templateNorm) { Fail "範本內容為空：$TemplateFullPath" }
Write-Ok "範本：$TemplateFullPath"

# ---------- 收集並正規化 repo 清單 ----------
$rawList = New-Object System.Collections.Generic.List[string]
if ($Repo) { foreach ($r in $Repo) { if ($r) { $rawList.Add($r.Trim()) } } }
if ($RepoFile) {
    if (-not (Test-Path $RepoFile)) { Fail "找不到清單檔：$RepoFile" }
    foreach ($line in Get-Content $RepoFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $rawList.Add($t)
    }
}

$seen = @{}
$targets = New-Object System.Collections.Generic.List[string]
foreach ($raw in $rawList) {
    # 容許貼上完整 URL：去掉 https://github.com/ 前綴、.git 後綴與結尾斜線。
    $n = $raw -replace '^https?://github\.com/', '' -replace '\.git$', '' -replace '/+$', ''
    if ($n -notmatch '^[\w.-]+/[\w.-]+$') { Write-Warn "略過非法 repo 格式：$raw"; continue }
    if ($n -eq $CentralRepo) { Write-Warn "略過中央 repo 本身：$n"; continue }
    if (-not $seen.ContainsKey($n)) { $seen[$n] = $true; $targets.Add($n) }
}

if ($targets.Count -eq 0) {
    Fail '沒有可處理的 repo。請用位置參數或 -RepoFile 提供 owner/name 清單。'
}
Write-Ok "待處理 repo：$($targets.Count) 個"
if (-not $Apply) {
    Write-Warn '目前為掃描模式（dry-run）；加上 -Apply 才會對不同／缺少的 repo 開 PR'
}

# ---------- 逐一掃描比對 ----------
Write-Step '掃描比對'

$results = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $status = ''
    $detail = ''
    $pr = ''
    try {
        $viewJson = gh repo view $t --json defaultBranchRef,isArchived 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $viewJson) {
            $status = 'INACCESSIBLE'
            $detail = '無法存取或找不到 repo'
            Write-Warn "$t -> $detail"
        }
        else {
            $info = $viewJson | ConvertFrom-Json
            $defBranch = $info.defaultBranchRef.name
            $archived = [bool]$info.isArchived

            $remote = Get-RemoteFile -TargetRepo $t -FilePath $WorkflowPath
            if ($null -eq $remote) {
                $status = 'MISSING'
                $detail = '下游沒有此 workflow 檔（尚未接入）'
                Write-Diff "$t -> 缺少（可新增）"
            }
            elseif ((Get-Normalized $remote) -eq $templateNorm) {
                $status = 'SAME'
                $detail = '與中央範本相同'
                Write-Ok "$t -> 相同"
            }
            else {
                $status = 'DIFF'
                $detail = '與中央範本不同'
                Write-Diff "$t -> 不同（可更新）"
            }

            if ($Apply -and ($status -eq 'DIFF' -or $status -eq 'MISSING')) {
                if ($archived) {
                    Write-Warn '  repo 已封存（archived），略過開 PR'
                    $detail += '；已封存略過'
                }
                else {
                    $pr = New-UpgradePr -TargetRepo $t -DefaultBranch $defBranch -TemplateFullPath $TemplateFullPath
                    if ($pr) { Write-Ok "  PR：$pr" }
                }
            }
        }
    }
    catch {
        $status = 'ERROR'
        $detail = $_.Exception.Message
        Write-Warn "$t -> 錯誤：$detail"
    }
    $results.Add([pscustomobject]@{ Repo = $t; Status = $status; PR = $pr; Detail = $detail })
}

# ---------- 總結 ----------
Write-Step '總結'
$results | Format-Table Repo, Status, PR -AutoSize | Out-Host

$same    = @($results | Where-Object { $_.Status -eq 'SAME' }).Count
$upgrade = @($results | Where-Object { $_.Status -eq 'DIFF' -or $_.Status -eq 'MISSING' }).Count
$bad     = @($results | Where-Object { $_.Status -eq 'INACCESSIBLE' -or $_.Status -eq 'ERROR' }).Count
$prCount = @($results | Where-Object { $_.PR }).Count

Write-Host ''
Write-Info "相同：$same    需更新：$upgrade    問題：$bad"
if ($Apply) {
    Write-Info "已開 PR：$prCount"
}
elseif ($upgrade -gt 0) {
    Write-Warn "有 $upgrade 個 repo 與中央範本不同／缺少；加上 -Apply 重跑即可自動開 PR 更新。"
}
