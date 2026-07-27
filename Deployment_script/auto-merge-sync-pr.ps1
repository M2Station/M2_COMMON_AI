<#
.SYNOPSIS
    一鍵 approve + merge 各下游 repo 由自動化流程開出的 M2 同步 PR，並驗證確實 MERGED。

.DESCRIPTION
    掃描清單內每個 repo 的「開啟中」PR，只挑出由本套自動化機制產生的分支：
      - chore/sync-m2-common-ai      由中央 reusable workflow（sync-m2-common-ai-reusable.yml）自動開
      - chore/upgrade-sync-workflow  由 update-sync-workflow.ps1 -Apply 於本機開

    對每個 PR 依序執行：
      1. approve  （已 approve 或 PR 是自己開的則略過；GitHub 不允許 approve 自己的 PR）
      2. 等待可合併（BEHIND 會自動 update-branch；UNKNOWN 會重查；DIRTY 衝突則跳過）
      3. merge    （預設 squash + 刪分支；被分支保護擋住時自動改用 --admin 強制合併）
      4. 驗證     （重新查詢直到 state = MERGED，並回報 merge commit）
    全程顯示進度（第幾個 / 共幾個、目前階段、已等待秒數）。

    預設只掃描回報（dry-run），不 approve、不 merge。加上 -Apply 才會真的動作。

    為什麼需要這支腳本：自動 PR 由 GITHUB_TOKEN 開出，GitHub 為防遞迴不會觸發下游的
    on: pull_request 檢查；若該 check 被設為 required，PR 會永遠停在 BLOCKED，
    只能由具 admin 權限的人強制合併 —— 這正是本腳本 --admin 後援的用途。

    只使用本機 gh 的登入身分，不需要任何額外 token / secret。

    放置路徑：Deployment_script/auto-merge-sync-pr.ps1

.PARAMETER Repo
    一或多個目標 repo，格式 owner/name。可用空白分隔多個。

.PARAMETER RepoFile
    repo 清單檔，一行一個 owner/name（或 GitHub URL）；# 開頭與空行忽略。
    未指定時自動使用本腳本同目錄的 repos.txt。可與 -Repo 併用，兩者合併去重。

.PARAMETER Branch
    要處理的自動 PR 分支名稱（可多個）。預設涵蓋上述兩種自動分支。

.PARAMETER CentralRepo
    中央 repo，格式 owner/name；出現在清單中會被略過。預設 M2Station/M2_COMMON_AI。

.PARAMETER MergeMethod
    合併方式：squash（預設）/ merge / rebase。

.PARAMETER Apply
    實際執行 approve + merge。未指定時只掃描回報。

.PARAMETER NoApprove
    只 merge 不 approve（repo 未要求 review 時可用）。

.PARAMETER NoAdmin
    停用 --admin 後援；被分支保護擋住時直接回報失敗，不強制合併。

.PARAMETER TimeoutSeconds
    單一 PR 等待「可合併」的上限秒數。預設 180。

.EXAMPLE
    # 只掃描，看看有哪些自動 PR 待處理
    .\auto-merge-sync-pr.ps1

.EXAMPLE
    # 對清單內所有 repo 實際 approve + squash merge
    .\auto-merge-sync-pr.ps1 -Apply

.EXAMPLE
    # 只處理 workflow 產生的同步 PR，且不使用 --admin
    .\auto-merge-sync-pr.ps1 -Apply -Branch chore/sync-m2-common-ai -NoAdmin
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Repo,
    [string]$RepoFile,
    [string[]]$Branch = @('chore/sync-m2-common-ai', 'chore/upgrade-sync-workflow'),
    [ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$CentralRepo = 'M2Station/M2_COMMON_AI',
    [ValidateSet('squash', 'merge', 'rebase')][string]$MergeMethod = 'squash',
    [switch]$Apply,
    [switch]$NoApprove,
    [switch]$NoAdmin,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

# gh pr view 需要的欄位；mergeStateStatus 是判斷「能不能合併」的關鍵。
$PrFields = 'number,title,url,state,isDraft,mergeable,mergeStateStatus,reviewDecision,' +
            'statusCheckRollup,headRefName,baseRefName,author,mergeCommit,mergedAt'

# 可以直接進入合併的狀態：
#   CLEAN     一切就緒
#   HAS_HOOKS 有 pre-receive hook 但可合併
#   UNSTABLE  有失敗／進行中的「非必要」檢查，仍可合併（會另外警告）
$ReadyStates = @('CLEAN', 'HAS_HOOKS', 'UNSTABLE')

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Write-Act  { param($m) Write-Host "    ACT  $m" -ForegroundColor Magenta }
function Write-Info { param($m) Write-Host "    $m" -ForegroundColor Gray }
function Write-Sub  { param($m) Write-Host "      $m" -ForegroundColor DarkGray }
function Fail       { param($m) Write-Host "    FAIL $m" -ForegroundColor Red; exit 1 }

# 統一呼叫 gh：強制 UTF-8 解碼（避免中文 PR 標題亂碼）、自行檢查離開碼，
# 並把 EAP 降為 Continue，以免 gh 寫 stderr 觸發 NativeCommandError 中斷整批。
function Invoke-Gh {
    param([string[]]$GhArgs)
    $prevEap = $ErrorActionPreference
    $prevEnc = [Console]::OutputEncoding
    $ErrorActionPreference = 'Continue'
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $out = & gh @GhArgs 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $prevEnc
        $ErrorActionPreference = $prevEap
    }
    [pscustomobject]@{
        ExitCode = $code
        Text     = (($out | Out-String).Trim())
    }
}

function Get-PrDetail {
    param([string]$TargetRepo, [int]$Number)
    $r = Invoke-Gh @('pr', 'view', "$Number", '--repo', $TargetRepo, '--json', $PrFields)
    if ($r.ExitCode -ne 0) { throw "讀取 PR #$Number 狀態失敗：$($r.Text)" }
    return ($r.Text | ConvertFrom-Json)
}

# 取出失敗的檢查名稱，讓 UNSTABLE / BLOCKED 時看得出卡在哪一項。
function Get-FailedCheck {
    param($Detail)
    $bad = @()
    foreach ($c in @($Detail.statusCheckRollup)) {
        if (-not $c) { continue }
        $name = if ($c.name) { $c.name } elseif ($c.context) { $c.context } else { '(unnamed)' }
        $res = if ($c.conclusion) { $c.conclusion } elseif ($c.state) { $c.state } else { '' }
        if ($res -in @('FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE')) {
            $bad += "$name=$res"
        }
    }
    return $bad
}

# 等到 PR 進入可合併狀態；回傳最後一次查到的 detail。
# BEHIND 會自動 update-branch（只做一次，避免無限迴圈）。
function Wait-PrMergeable {
    param([string]$TargetRepo, [int]$Number, [int]$MaxSeconds, [string]$ProgressPrefix)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $updated = $false
    $lastState = ''
    while ($true) {
        $d = Get-PrDetail -TargetRepo $TargetRepo -Number $Number
        $st = "$($d.mergeStateStatus)"
        if ($d.state -ne 'OPEN') { return $d }
        if ($st -in $ReadyStates) { return $d }
        if ($st -eq 'DIRTY' -or $st -eq 'DRAFT') { return $d }

        if ($st -eq 'BEHIND' -and -not $updated) {
            Write-Sub 'wait     BEHIND -> 自動 update-branch'
            $u = Invoke-Gh @('pr', 'update-branch', "$Number", '--repo', $TargetRepo)
            $updated = $true
            if ($u.ExitCode -ne 0) { Write-Sub "wait     update-branch 失敗：$($u.Text)" }
        }

        $elapsed = [int]$sw.Elapsed.TotalSeconds
        if ($elapsed -ge $MaxSeconds) { return $d }
        if ($st -ne $lastState) {
            Write-Sub "wait     $st ... 等待中（上限 ${MaxSeconds}s）"
            $lastState = $st
        }
        Write-Progress -Id 2 -ParentId 1 -Activity $ProgressPrefix `
            -Status "等待可合併：$st（已等待 ${elapsed}s / ${MaxSeconds}s）" `
            -PercentComplete ([math]::Min(100, [int]($elapsed * 100 / [math]::Max(1, $MaxSeconds))))
        Start-Sleep -Seconds 3
    }
}

# 合併後再查一次，確認真的 MERGED（而不是 gh 回 0 但實際沒進去）。
function Confirm-PrMerged {
    param([string]$TargetRepo, [int]$Number, [int]$MaxSeconds = 30)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $d = Get-PrDetail -TargetRepo $TargetRepo -Number $Number
        if ($d.state -eq 'MERGED') { return $d }
        if ([int]$sw.Elapsed.TotalSeconds -ge $MaxSeconds) { return $null }
        Start-Sleep -Seconds 2
    }
}

# ---------- 前置檢查 ----------
Write-Step '前置檢查'

if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) { Fail 'gh 未安裝或不在 PATH' }
Write-Ok 'gh 可用'

$auth = Invoke-Gh @('auth', 'status')
if ($auth.ExitCode -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login' }

$meRes = Invoke-Gh @('api', 'user', '--jq', '.login')
$me = if ($meRes.ExitCode -eq 0) { $meRes.Text } else { '' }
Write-Ok "gh 已登入$(if ($me) { "：$me" })"

# ---------- 收集並正規化 repo 清單 ----------
if (-not $RepoFile) {
    $defaultList = Join-Path $PSScriptRoot 'repos.txt'
    if (Test-Path $defaultList) { $RepoFile = $defaultList }
}

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
Write-Info "目標分支：$($Branch -join '、')"
Write-Info "合併方式：$MergeMethod$(if (-not $NoAdmin) { '（卡住時自動 --admin）' })"
if (-not $Apply) {
    Write-Warn '目前為掃描模式（dry-run），不會 approve 也不會 merge；加上 -Apply 才會實際執行'
}

# ---------- 逐一處理 ----------
Write-Step $(if ($Apply) { 'Approve + Merge' } else { '掃描自動 PR' })

$results = New-Object System.Collections.Generic.List[object]
$mergedRepos = New-Object System.Collections.Generic.List[string]
$idx = 0

foreach ($t in $targets) {
    $idx++
    $prefix = "[$idx/$($targets.Count)] $t"
    Write-Progress -Id 1 -Activity 'Approve + Merge 自動 PR' -Status $prefix `
        -PercentComplete ([int](($idx - 1) * 100 / $targets.Count))
    Write-Host "`n  $prefix" -ForegroundColor White

    # 找出此 repo 內符合目標分支的開啟中 PR
    $prs = @()
    $listFailed = $false
    foreach ($b in $Branch) {
        $r = Invoke-Gh @('pr', 'list', '--repo', $t, '--state', 'open', '--head', $b,
            '--json', 'number,title,url,headRefName,isDraft,author')
        if ($r.ExitCode -ne 0) {
            Write-Warn "無法讀取 PR 清單（$b）：$($r.Text)"
            $listFailed = $true
            continue
        }
        $parsed = $null
        if ($r.Text) { $parsed = $r.Text | ConvertFrom-Json }
        foreach ($p in @($parsed)) { if ($p) { $prs += $p } }
    }

    if ($listFailed -and $prs.Count -eq 0) {
        $results.Add([pscustomobject]@{
                Repo = $t; PR = ''; Branch = ''; Result = 'INACCESSIBLE'; Detail = '無法存取 repo 或 PR 清單'
            })
        continue
    }

    if ($prs.Count -eq 0) {
        Write-Sub 'none     沒有待處理的自動 PR'
        $results.Add([pscustomobject]@{
                Repo = $t; PR = ''; Branch = ''; Result = 'NONE'; Detail = '無開啟中的自動 PR'
            })
        continue
    }

    foreach ($p in $prs) {
        $num = [int]$p.number
        $prTag = "#$num"
        $result = ''
        $detail = ''
        $sha = ''
        Write-Sub "pr       $prTag [$($p.headRefName)] $($p.title)"
        Write-Sub "url      $($p.url)"

        try {
            $d = Get-PrDetail -TargetRepo $t -Number $num

            if ($d.isDraft) {
                Write-Warn '  草稿 PR，略過'
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'SKIPPED'; Detail = '草稿 PR'
                    })
                continue
            }

            $failed = Get-FailedCheck -Detail $d
            Write-Sub "state    mergeable=$($d.mergeable) mergeState=$($d.mergeStateStatus) review=$($d.reviewDecision)"
            if ($failed.Count -gt 0) { Write-Sub "checks   失敗：$($failed -join '、')" }

            if (-not $Apply) {
                $plan = if ($d.mergeStateStatus -eq 'DIRTY') { '有衝突，需先手動處理' }
                        elseif ($d.reviewDecision -eq 'APPROVED') { '已 approve，將直接 merge' }
                        else { '將 approve + merge' }
                Write-Info "  預計動作：$plan"
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'PENDING'; Detail = $plan
                    })
                continue
            }

            # ---- 1. approve ----
            if ($NoApprove) {
                Write-Sub 'approve  略過（-NoApprove）'
            }
            elseif ($d.reviewDecision -eq 'APPROVED') {
                Write-Sub 'approve  略過（已是 APPROVED）'
            }
            elseif ($me -and $d.author.login -eq $me) {
                Write-Sub 'approve  略過（GitHub 不允許 approve 自己開的 PR）'
            }
            else {
                $rv = Invoke-Gh @('pr', 'review', "$num", '--repo', $t, '--approve',
                    '--body', 'Auto-approved by auto-merge-sync-pr.ps1（自動同步 PR）')
                if ($rv.ExitCode -eq 0) {
                    Write-Sub 'approve  OK'
                }
                elseif ($rv.Text -match 'own pull request') {
                    Write-Sub 'approve  略過（GitHub 不允許 approve 自己開的 PR）'
                }
                else {
                    Write-Sub "approve  失敗（續試合併）：$($rv.Text)"
                }
            }

            # ---- 2. 等待可合併 ----
            $d = Wait-PrMergeable -TargetRepo $t -Number $num -MaxSeconds $TimeoutSeconds -ProgressPrefix $prefix
            Write-Progress -Id 2 -ParentId 1 -Activity $prefix -Completed

            if ($d.state -eq 'MERGED') {
                $sha = "$($d.mergeCommit.oid)"
                if ($sha.Length -gt 7) { $sha = $sha.Substring(0, 7) }
                Write-Ok "  已是 MERGED（$sha）"
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'MERGED'; Detail = "sha=$sha"
                    })
                if (-not $mergedRepos.Contains($t)) { $mergedRepos.Add($t) }
                continue
            }
            if ($d.state -eq 'CLOSED') {
                Write-Warn '  PR 已被關閉，略過'
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'SKIPPED'; Detail = 'PR 已關閉'
                    })
                continue
            }
            if ($d.mergeStateStatus -eq 'DIRTY') {
                Write-Warn '  有合併衝突，需手動處理'
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'CONFLICT'; Detail = '合併衝突'
                    })
                continue
            }

            $stateAfterWait = "$($d.mergeStateStatus)"
            if ($stateAfterWait -eq 'UNSTABLE') {
                $failed = Get-FailedCheck -Detail $d
                if ($failed.Count -gt 0) {
                    Write-Warn "  有失敗的非必要檢查仍將合併：$($failed -join '、')"
                }
            }
            elseif ($stateAfterWait -notin $ReadyStates) {
                Write-Sub "wait     逾時仍為 $stateAfterWait，直接嘗試合併"
            }

            # ---- 3. merge ----
            $mergeArgs = @('pr', 'merge', "$num", '--repo', $t, "--$MergeMethod", '--delete-branch')
            Write-Act "  merge    $MergeMethod + 刪分支"
            $mg = Invoke-Gh $mergeArgs
            if ($mg.ExitCode -ne 0 -and -not $NoAdmin) {
                Write-Sub "merge    一般合併被擋（$($mg.Text -replace '\s+', ' ')）"
                Write-Act '  merge    改用 --admin 強制合併'
                $mg = Invoke-Gh ($mergeArgs + '--admin')
            }
            if ($mg.ExitCode -ne 0) {
                $msg = ($mg.Text -replace '\s+', ' ')
                Write-Warn "  合併失敗：$msg"
                $results.Add([pscustomobject]@{
                        Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'FAILED'; Detail = $msg
                    })
                continue
            }

            # ---- 4. 驗證確實 MERGED ----
            Write-Sub 'verify   確認 PR 狀態…'
            $v = Confirm-PrMerged -TargetRepo $t -Number $num
            if ($null -eq $v) {
                Write-Warn '  gh 回報合併成功，但查詢仍非 MERGED（請手動確認）'
                $results.Add([pscustomobject]@{
                        Repo   = $t; PR = $prTag; Branch = $p.headRefName; Result = 'UNVERIFIED'
                        Detail = 'gh 成功但狀態未變 MERGED'
                    })
                continue
            }
            $sha = "$($v.mergeCommit.oid)"
            if ($sha.Length -gt 7) { $sha = $sha.Substring(0, 7) }
            Write-Ok "  MERGED 已確認  sha=$sha  at=$($v.mergedAt)"
            $results.Add([pscustomobject]@{
                    Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'MERGED'; Detail = "sha=$sha"
                })
            if (-not $mergedRepos.Contains($t)) { $mergedRepos.Add($t) }
        }
        catch {
            $msg = $_.Exception.Message
            Write-Warn "  錯誤：$msg"
            $results.Add([pscustomobject]@{
                    Repo = $t; PR = $prTag; Branch = $p.headRefName; Result = 'ERROR'; Detail = $msg
                })
        }
    }
}
Write-Progress -Id 2 -Activity 'wait' -Completed
Write-Progress -Id 1 -Activity 'Approve + Merge 自動 PR' -Completed

# ---------- 最終複查：確認目標分支已無殘留的開啟中 PR ----------
if ($Apply -and $mergedRepos.Count -gt 0) {
    Write-Step '最終複查（確認沒有殘留的自動 PR）'
    $leftover = 0
    $j = 0
    foreach ($t in $mergedRepos) {
        $j++
        Write-Progress -Id 1 -Activity '最終複查' -Status "[$j/$($mergedRepos.Count)] $t" `
            -PercentComplete ([int](($j - 1) * 100 / $mergedRepos.Count))
        $open = @()
        foreach ($b in $Branch) {
            $r = Invoke-Gh @('pr', 'list', '--repo', $t, '--state', 'open', '--head', $b, '--json', 'number')
            if ($r.ExitCode -eq 0 -and $r.Text) {
                foreach ($p in @($r.Text | ConvertFrom-Json)) { if ($p) { $open += "#$($p.number)" } }
            }
        }
        if ($open.Count -gt 0) {
            Write-Warn "$t 仍有未合併的自動 PR：$($open -join '、')"
            $leftover += $open.Count
        }
        else {
            Write-Ok "$t 已無殘留自動 PR"
        }
    }
    Write-Progress -Id 1 -Activity '最終複查' -Completed
    if ($leftover -eq 0) { Write-Ok '複查通過：目標分支的自動 PR 全數合併完成' }
}

# ---------- 總結 ----------
Write-Step '總結'
if ($results.Count -gt 0) {
    $results | Format-Table Repo, PR, Branch, Result, Detail -AutoSize -Wrap | Out-Host
}

$merged  = @($results | Where-Object { $_.Result -eq 'MERGED' }).Count
$pending = @($results | Where-Object { $_.Result -eq 'PENDING' }).Count
$bad     = @($results | Where-Object { $_.Result -in @('FAILED', 'ERROR', 'CONFLICT', 'UNVERIFIED', 'INACCESSIBLE') }).Count

Write-Host ''
if ($Apply) {
    Write-Info "已合併並確認：$merged    失敗／需處理：$bad"
    if ($bad -gt 0) {
        Write-Warn '有 PR 未完成合併，請看上表 Detail 欄；BLOCKED 類問題通常需要 repo admin 權限。'
    }
}
else {
    Write-Info "待處理 PR：$pending    需注意：$bad"
    if ($pending -gt 0) { Write-Warn "加上 -Apply 重跑即可自動 approve + merge 這 $pending 個 PR。" }
}

if ($bad -gt 0) { exit 1 }
