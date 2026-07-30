<#
.SYNOPSIS
    立刻對清單內所有下游 repo 觸發 sync-m2-common-ai.yml（workflow_dispatch），不等排程。

.DESCRIPTION
    下游的同步 workflow 平常靠 cron（台灣時間 05:00 / 17:00）自己跑；
    中央 repo 剛改完設定、想馬上讓所有下游拉到最新版時，用這支一次全部手動觸發。

    每個 repo 的處理流程：
      1. 讀 repo 資訊（預設分支、是否封存）
      2. 確認 .github/workflows/sync-m2-common-ai.yml 存在且為 active
         （GitHub 會在 repo 連續 60 天無活動時自動停用排程 workflow，
          此時 dispatch 會失敗；預設會自動重新啟用，可用 -NoEnable 關閉）
      3. gh workflow run sync-m2-common-ai.yml --ref <預設分支> -f ref=<中央 ref>
      4. 回頭撈出剛觸發的 run，回報網址；加 -Wait 會等到 run 結束並回報結論

    預設只預覽（dry-run），不觸發任何 repo；加上 -Apply 才會真的送出。

    中央 repo 為 public，本腳本只用你本機 gh 的登入身分操作，
    不需要任何額外 token / secret（但你的帳號需對下游 repo 有 write 權限）。

    放置路徑：Deployment_script/trigger-sync-now.ps1

.PARAMETER Repo
    一或多個目標 repo，格式 owner/name。可用空白或逗號分隔多個。

.PARAMETER RepoFile
    改由檔案提供 repo 清單，一行一個 owner/name（或 GitHub URL）；# 開頭與空行忽略。
    可與 -Repo 併用，兩者會合併去重。兩者都沒給時，預設用本腳本同層的 repos.txt。

.PARAMETER CentralRepo
    中央 repo，格式 owner/name。預設 M2Station/M2_COMMON_AI；出現在清單裡會被略過。

.PARAMETER CentralRef
    傳給下游 workflow 的 ref 輸入，代表要同步中央 repo 的哪個 branch / tag。預設 main。

.PARAMETER Apply
    實際觸發。未指定時只預覽回報，不對任何 repo 送出 dispatch。

.PARAMETER Wait
    觸發後等待每個 run 結束，並回報 success / failure。未指定時只回報「已送出」。

.PARAMETER NoEnable
    停用「自動重新啟用被停用的 workflow」。預設遇到 disabled 狀態會先啟用再觸發。

.PARAMETER TimeoutSeconds
    -Wait 時每個 run 的等待上限秒數。預設 600。

.EXAMPLE
    # 預覽：看哪些 repo 可以被觸發，不送出任何 dispatch
    .\trigger-sync-now.ps1

.EXAMPLE
    # 立刻觸發 repos.txt 內全部 repo
    .\trigger-sync-now.ps1 -Apply

.EXAMPLE
    # 立刻觸發並等待每個 run 跑完
    .\trigger-sync-now.ps1 -Apply -Wait

.EXAMPLE
    # 只觸發指定 repo，並指定同步中央的某個 tag
    .\trigger-sync-now.ps1 M2Station/M2_APEX -Apply -CentralRef v1
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Repo,
    [string]$RepoFile,
    [ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$CentralRepo = 'M2Station/M2_COMMON_AI',
    [string]$CentralRef = 'main',
    [switch]$Apply,
    [switch]$Wait,
    [switch]$NoEnable,
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
$WorkflowFile = 'sync-m2-common-ai.yml'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Write-Act  { param($m) Write-Host "    ACT  $m" -ForegroundColor Magenta }
function Write-Info { param($m) Write-Host "    $m" -ForegroundColor Gray }
function Write-Sub  { param($m) Write-Host "      $m" -ForegroundColor DarkGray }
function Fail       { param($m) Write-Host "    FAIL $m" -ForegroundColor Red; exit 1 }

# 統一呼叫 gh：強制 UTF-8 解碼（避免中文輸出亂碼）、自行檢查離開碼，
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

# gh 回傳的時間可能已被 ConvertFrom-Json 轉成 DateTime，也可能還是 ISO-8601 字串；兩者都統一成 UTC。
function ConvertTo-Utc {
    param($Value)
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    return [datetime]::Parse(
        [string]$Value,
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AdjustToUniversal
    )
}

# 讀取下游 workflow 的註冊狀態；檔案不存在或無權限時回 $null。
# state 可能是 active / disabled_manually / disabled_inactivity。
function Get-WorkflowInfo {
    param([string]$TargetRepo)
    $r = Invoke-Gh @('api', "repos/$TargetRepo/actions/workflows/$WorkflowFile", '--jq', '{id:.id,state:.state}')
    if ($r.ExitCode -ne 0 -or -not $r.Text) { return $null }
    return ($r.Text | ConvertFrom-Json)
}

function Enable-SyncWorkflow {
    param([string]$TargetRepo)
    $r = Invoke-Gh @('api', '-X', 'PUT', "repos/$TargetRepo/actions/workflows/$WorkflowFile/enable")
    return ($r.ExitCode -eq 0)
}

# 送出 workflow_dispatch。舊版 stub 若沒有 ref 輸入，會退回不帶輸入再試一次。
function Invoke-SyncDispatch {
    param([string]$TargetRepo, [string]$RepoRef)
    $r = Invoke-Gh @('workflow', 'run', $WorkflowFile, '--repo', $TargetRepo, '--ref', $RepoRef, '-f', "ref=$CentralRef")
    if ($r.ExitCode -ne 0 -and $r.Text -match 'nexpected input|nvalid input|does not accept') {
        Write-Sub '該 workflow 不接受 ref 輸入（舊版 stub），改以無輸入方式重試'
        $r = Invoke-Gh @('workflow', 'run', $WorkflowFile, '--repo', $TargetRepo, '--ref', $RepoRef)
    }
    return $r
}

# dispatch 之後 run 不會馬上出現在列表，這裡輪詢撈出「觸發時間之後」最新的那筆。
function Get-LatestRun {
    param([string]$TargetRepo, [datetime]$SinceUtc, [int]$WaitSeconds = 30)
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        $r = Invoke-Gh @('run', 'list', '--repo', $TargetRepo, '--workflow', $WorkflowFile,
            '--event', 'workflow_dispatch', '--limit', '10',
            '--json', 'databaseId,status,conclusion,createdAt,url')
        if ($r.ExitCode -eq 0 -and $r.Text) {
            $hit = @($r.Text | ConvertFrom-Json |
                Where-Object { (ConvertTo-Utc $_.createdAt) -ge $SinceUtc } |
                Sort-Object { ConvertTo-Utc $_.createdAt } -Descending)
            if ($hit.Count -gt 0) { return $hit[0] }
        }
        if ((Get-Date) -ge $deadline) { return $null }
        Start-Sleep -Seconds 3
    }
}

# 等到 run 結束；逾時回 $null（run 仍在跑，只是不再等）。
function Wait-RunComplete {
    param([string]$TargetRepo, [long]$RunId, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ($true) {
        $r = Invoke-Gh @('run', 'view', "$RunId", '--repo', $TargetRepo, '--json', 'status,conclusion,url')
        if ($r.ExitCode -eq 0 -and $r.Text) {
            $d = $r.Text | ConvertFrom-Json
            if ($d.status -eq 'completed') { return $d }
        }
        if ((Get-Date) -ge $deadline) { return $null }
        Start-Sleep -Seconds 5
    }
}

# ---------- 前置檢查 ----------
Write-Step '前置檢查'

if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) { Fail 'gh 未安裝或不在 PATH' }
Write-Ok 'gh 可用'

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login' }
Write-Ok 'gh 已登入'

# ---------- 收集並正規化 repo 清單 ----------
if (-not $Repo -and -not $RepoFile) {
    $defaultList = Join-Path $PSScriptRoot 'repos.txt'
    if (Test-Path $defaultList) {
        $RepoFile = $defaultList
        Write-Info "未指定 repo，改用預設清單：$RepoFile"
    }
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
Write-Info "workflow：$WorkflowFile    中央 ref：$CentralRef"
if (-not $Apply) {
    Write-Warn '目前為預覽模式（dry-run）；加上 -Apply 才會實際觸發'
}

# ---------- 逐一觸發 ----------
Write-Step $(if ($Apply) { '觸發同步' } else { '預覽（不觸發）' })

$results = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $status = ''
    $detail = ''
    $runUrl = ''
    try {
        $viewJson = Invoke-Gh @('repo', 'view', $t, '--json', 'defaultBranchRef,isArchived')
        if ($viewJson.ExitCode -ne 0 -or -not $viewJson.Text) {
            $status = 'INACCESSIBLE'
            $detail = '無法存取或找不到 repo'
            Write-Warn "$t -> $detail"
        }
        else {
            $info = $viewJson.Text | ConvertFrom-Json
            $defBranch = $info.defaultBranchRef.name
            $wf = Get-WorkflowInfo -TargetRepo $t

            if ($info.isArchived) {
                $status = 'SKIPPED'
                $detail = 'repo 已封存（archived）'
                Write-Warn "$t -> $detail"
            }
            elseif ($null -eq $wf) {
                $status = 'MISSING'
                $detail = "下游沒有 $WorkflowFile（尚未接入，請先跑 update-sync-workflow.ps1 -Apply）"
                Write-Warn "$t -> 缺少 workflow"
            }
            else {
                # workflow 被停用（多半是 60 天無活動被自動關掉排程）時，dispatch 會直接失敗。
                if ($wf.state -ne 'active') {
                    if ($Apply -and -not $NoEnable) {
                        Write-Act "$t -> workflow 狀態 $($wf.state)，先重新啟用"
                        if (Enable-SyncWorkflow -TargetRepo $t) {
                            Write-Sub '已重新啟用'
                            $detail = "原狀態 $($wf.state)，已重新啟用；"
                        }
                        else {
                            $status = 'DISABLED'
                            $detail = "workflow 狀態 $($wf.state)，重新啟用失敗"
                            Write-Warn "$t -> $detail"
                        }
                    }
                    else {
                        $status = 'DISABLED'
                        $detail = "workflow 狀態 $($wf.state)（-Apply 時會自動重新啟用，除非加 -NoEnable）"
                        Write-Warn "$t -> $detail"
                    }
                }

                if (-not $status) {
                    if (-not $Apply) {
                        $status = 'READY'
                        $detail += "可觸發（分支 $defBranch）"
                        Write-Ok "$t -> 可觸發（分支 $defBranch）"
                    }
                    else {
                        $since = (Get-Date).ToUniversalTime().AddSeconds(-30)
                        $d = Invoke-SyncDispatch -TargetRepo $t -RepoRef $defBranch
                        if ($d.ExitCode -ne 0) {
                            $status = 'FAILED'
                            $detail += "觸發失敗：$($d.Text -replace '\s+', ' ')"
                            Write-Warn "$t -> $detail"
                        }
                        else {
                            $status = 'DISPATCHED'
                            Write-Act "$t -> 已送出觸發（分支 $defBranch）"
                            $run = Get-LatestRun -TargetRepo $t -SinceUtc $since
                            if ($run) {
                                $runUrl = $run.url
                                Write-Sub "run：$runUrl"
                                if ($Wait) {
                                    Write-Sub "等待 run 結束（上限 $TimeoutSeconds 秒）..."
                                    $done = Wait-RunComplete -TargetRepo $t -RunId $run.databaseId -Seconds $TimeoutSeconds
                                    if ($null -eq $done) {
                                        $detail += "已觸發，等待逾時（run 仍在進行）"
                                        Write-Warn "  等待逾時，run 仍在進行"
                                    }
                                    elseif ($done.conclusion -eq 'success') {
                                        $status = 'SUCCESS'
                                        $detail += '同步 run 成功'
                                        Write-Ok "  run 成功"
                                    }
                                    else {
                                        $status = 'RUN_FAILED'
                                        $detail += "run 結論：$($done.conclusion)"
                                        Write-Warn "  run 結論：$($done.conclusion)"
                                    }
                                }
                                else {
                                    $detail += '已觸發'
                                }
                            }
                            else {
                                $detail += '已觸發，但暫時查不到對應的 run（稍後看 Actions 頁）'
                                Write-Sub '暫時查不到對應的 run，請稍後至 Actions 頁確認'
                            }
                        }
                    }
                }
            }
        }
    }
    catch {
        $status = 'ERROR'
        $detail = $_.Exception.Message
        Write-Warn "$t -> 錯誤：$detail"
    }
    $results.Add([pscustomobject]@{ Repo = $t; Status = $status; Run = $runUrl; Detail = $detail })
}

# ---------- 總結 ----------
Write-Step '總結'
$results | Format-Table Repo, Status, Run -AutoSize | Out-Host

$done  = @($results | Where-Object { $_.Status -in @('DISPATCHED', 'SUCCESS') }).Count
$ready = @($results | Where-Object { $_.Status -eq 'READY' }).Count
$bad   = @($results | Where-Object { $_.Status -in @('FAILED', 'RUN_FAILED', 'MISSING', 'DISABLED', 'INACCESSIBLE', 'ERROR') }).Count

Write-Host ''
if ($Apply) {
    Write-Info "已觸發：$done    問題：$bad"
    if ($bad -gt 0) { Write-Warn '有 repo 未成功觸發，詳見上表的 Detail 欄（用 Format-List 可看完整訊息）' }
    Write-Info '同步成功的 repo 會出現 chore/sync-m2-common-ai 的 PR，可用 auto-merge-sync-pr.ps1 -Apply 一次合併。'
}
else {
    Write-Info "可觸發：$ready    問題：$bad"
    Write-Warn '這是預覽模式；加上 -Apply 重跑才會真的觸發。'
}
