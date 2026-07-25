---
description: Open a PR from the current branch: inspect the diff, write title/body matching repo history, create the PR, then monitor merge-readiness (CI + mergeStateStatus) via self-terminating background polls that alert the moment it is ready or fails, and wait for confirmation to merge.
mode: agent
---

# Pull Request

**觸發**：`/m2_pr`、`/m2_pr draft`、`/m2_pr <補充說明>`

- `/m2_pr` → 從當前分支開一個 ready-for-review 的 PR
- `/m2_pr draft` → 開成 draft PR
- `/m2_pr <說明>` → 將補充說明納入 PR body 的動機段落

> 發版用的版本 bump PR 請用 `/m2_release`，不要走這支流程。

---

## 0. 先對齊 repo 慣例（必做，不可略過）

```bash
gh pr list --state merged --limit 10                    # title / body 慣例、語言（中/英）
gh pr view <最近一個 PR 編號>                             # body 段落結構、有無 checklist
ls .github/PULL_REQUEST_TEMPLATE* .github/pull_request_template.md 2>/dev/null
cat .github/CODEOWNERS 2>/dev/null                      # 需指定的 reviewer
gh label list                                           # 可用 label
```

- **有 PR template 就必須沿用**，不自創段落結構。
- title 語言、body 語言、有無 emoji、有無 issue 連結格式，一律比對歷史後沿用。

## 1. 收集變更內容

```bash
git status --short                                      # 確認無未 commit 變更
git branch --show-current
git log --oneline --no-merges main..HEAD                # 本分支的 commit
git diff main...HEAD --stat                             # 變更範圍
git diff main...HEAD                                    # 實際內容（大型 diff 可只讀關鍵檔案）
```

- **必須讀過實際 diff 才寫 PR 描述**，不可只依 commit message 推測。
- 若 commit 數量多且訊息雜亂，在 body 中依「功能面」重組敘述，不逐一列 commit。

## 2. 前置檢查（任一項不通過 → 停止並回報）

- [ ] 當前分支**不是** `main`
- [ ] working tree 乾淨（無未 commit 變更）
- [ ] 已同步 main：`git fetch origin && git log origin/main..HEAD` 確認可乾淨合併
- [ ] diff 中無帳號、密碼、token、API key、內部 IP、客戶機密資料
- [ ] 無殘留 `console.log` / `debugger` / 註解掉的舊程式碼 / 測試用假資料
- [ ] 變更範圍聚焦，無夾帶不相關的格式化或重排
- [ ] 已存在同分支的 open PR？→ 改為更新既有 PR，不重複建立

若分支尚未推送：

```bash
git push -u origin $(git branch --show-current)
```

## 3. 撰寫 PR title 與 body

**title**：沿用 repo 慣例；若歷史為 Conventional Commits，格式為

```text
<type>(<scope>): <subject>
```

- 英文、動詞原形開頭、不超過 72 字元、句尾不加句號。
- 不寫 `update code`、`fix bug` 這類無資訊量的標題。

**body**：優先使用 repo 的 PR template。若無 template，使用下列結構（內容語言沿用 repo 慣例）：

```markdown
## What
<改了什麼，2–4 句，以行為/結果描述，非檔案清單>

## Why
<動機。有 issue 就寫 `Closes #123`>

## How
- <關鍵實作決策，或非顯而易見的取捨>
- <若有替代方案被排除，說明原因>

## Impact
- 影響範圍：<模組 / 使用者可見行為 / 相容性>
- Breaking change：<有/無，有則說明遷移方式>

## Verification
- [ ] <實際做過的驗證步驟，非「應該可以」>
- [ ] CI passed
```

- **不編造未執行的測試**。沒測就寫「未測試，需 reviewer 協助驗證」。
- UI 變更請提示使用者補截圖，agent 不自行宣稱已附圖。

## 4. 建立 PR

```bash
gh pr create \
  --base main \
  --title "<TITLE>" \
  --body "<BODY>" \
  --assignee @me
# 需要時追加：--draft / --label <label> / --reviewer <user>
```

- reviewer 依 CODEOWNERS 或歷史慣例指定；不確定則留空並回報。
- label 只從 `gh label list` 的既有清單挑選，不新建 label。

## 5. 監控 PR 直到「可合併」或「有失敗」（即時反饋，不空等）

PR 建立後**先抓一次快照立即回報**，再進入輪詢。判斷「可不可以合併」要看**整體狀態**，不能只看 CI checks——很多 repo 的 PR 根本沒有必需 CI，`statusCheckRollup` 是空的，但 GitHub 網頁早已顯示 mergeable；此時要**直接進第 6 節**，絕不可空等到 timeout。

> **不要用 `gh pr checks --watch` 當主要手段。** 它在 CI 沒有輸出的期間會被終端機判為 idle 而假性 timeout，且在「沒有任何 check」時行為不定——這正是「網頁已 READY、agent 卻還在等」與「動不動 timeout」的主因。改用下面會**自己結束**的輪詢批次。

### 5.1 立即快照（開 PR 後馬上跑一次）

```powershell
$pr = gh pr view --json number -q .number
$j = gh pr view $pr --json state,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup | ConvertFrom-Json
$c   = @($j.statusCheckRollup)
$run = @($c | Where-Object { $_.status -in 'QUEUED','IN_PROGRESS','PENDING' -or $_.state -in 'PENDING','EXPECTED' })
"state=$($j.state) draft=$($j.isDraft) merge=$($j.mergeStateStatus) review=$($j.reviewDecision) checks=$($c.Count) running=$($run.Count)"
```

- `checks=0` 且 `merge=CLEAN`（或 `UNSTABLE`/`HAS_HOOKS`）→ 此 repo PR 無必需 CI，**直接跳第 6 節**發合併提醒，不要輪詢。
- `running>0` 或 `merge=UNKNOWN` → 進 5.2 輪詢。
- `merge=DIRTY` → 有衝突，停止並回報需 rebase／解衝突。
- `draft=True` → 是 draft PR，回報並暫不提醒合併。

### 5.2 輪詢批次（會自己結束：有結論即停，否則到心跳窗上限就回報一次）

**設計重點**：這支指令**只要 CI 一有結論（全過／有失敗／已合併）就在 3 秒內跳出**；若心跳窗（預設 120 秒，可調）內仍在跑，就印 `RESULT=RUNNING` 結束該批。**以「有界的同步批次」執行：由你自己一批接一批跑，直到有結論為止；不要 fire 成背景（async）然後結束回合等通知。** 原因：async 只會在「這一批指令結束」時通知你，而這批通常是在心跳窗到點（`RESULT=RUNNING`、CI 其實還沒好）就結束——你若此時結束回合，就沒有任何輪詢在跑了，等 GitHub 稍後才跑完時**沒人發現、agent 就此沉默**（這正是「GitHub 已完成、agent 沒反應」的成因）。因為每批會自己結束，不會 hang、也不會假性 timeout。**絕不可停在 `RESULT=RUNNING`**：收到 RUNNING 先回報一句心跳，然後**在同一個回合內立刻再跑下一批**，直到收斂為 `READY`/`FAILED`/`BLOCKED`/`BEHIND`/`CONFLICT`/`MERGED_OR_CLOSED` 才停。

PowerShell：

```powershell
$pr  = gh pr view --json number -q .number
$end = (Get-Date).AddSeconds(120)          # 心跳窗，可調小以更頻繁回報
do {
    $j   = gh pr view $pr --json state,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup | ConvertFrom-Json
    $c   = @($j.statusCheckRollup)
    $run = @($c | Where-Object { $_.status -in 'QUEUED','IN_PROGRESS','PENDING' -or $_.state -in 'PENDING','EXPECTED' })
    $bad = @($c | Where-Object { $_.conclusion -in 'FAILURE','TIMED_OUT','CANCELLED','ACTION_REQUIRED','STARTUP_FAILURE' -or $_.state -in 'FAILURE','ERROR' })
    Write-Host ("[{0}] merge={1} review={2} checks={3} running={4} failed={5}" -f (Get-Date -f HH:mm:ss), $j.mergeStateStatus, $j.reviewDecision, $c.Count, $run.Count, $bad.Count)
    if ($j.state -ne 'OPEN')                                      { 'RESULT=MERGED_OR_CLOSED'; break }
    if ($bad.Count -gt 0)                                         { 'RESULT=FAILED'; break }
    if ($j.mergeStateStatus -eq 'DIRTY')                         { 'RESULT=CONFLICT'; break }
    if ($j.mergeStateStatus -in 'CLEAN','HAS_HOOKS')             { 'RESULT=READY'; break }
    if ($run.Count -eq 0 -and $j.mergeStateStatus -eq 'UNSTABLE') { 'RESULT=READY'; break }
    if ($run.Count -eq 0 -and $j.mergeStateStatus -eq 'BLOCKED')  { 'RESULT=BLOCKED'; break }
    if ($run.Count -eq 0 -and $j.mergeStateStatus -eq 'BEHIND')   { 'RESULT=BEHIND'; break }
    if ((Get-Date) -ge $end)                                     { 'RESULT=RUNNING'; break }
    Start-Sleep -Seconds 3
} while ($true)
```

Bash：

```bash
PR=$(gh pr view --json number -q .number)
END=$(( $(date +%s) + 120 ))               # 心跳窗，可調
while :; do
  J=$(gh pr view "$PR" --json state,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup)
  ST=$(jq -r .state <<<"$J"); MS=$(jq -r .mergeStateStatus <<<"$J")
  CNT=$(jq '.statusCheckRollup|length' <<<"$J")
  RUN=$(jq '[.statusCheckRollup[]|select(.status=="QUEUED" or .status=="IN_PROGRESS" or .status=="PENDING" or .state=="PENDING" or .state=="EXPECTED")]|length' <<<"$J")
  BAD=$(jq '[.statusCheckRollup[]|select(.conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED" or .conclusion=="ACTION_REQUIRED" or .conclusion=="STARTUP_FAILURE" or .state=="FAILURE" or .state=="ERROR")]|length' <<<"$J")
  echo "[$(date +%T)] merge=$MS review=$(jq -r .reviewDecision <<<"$J") checks=$CNT running=$RUN failed=$BAD"
  [ "$ST" != OPEN ] && { echo RESULT=MERGED_OR_CLOSED; break; }
  [ "$BAD" -gt 0 ] && { echo RESULT=FAILED; break; }
  [ "$MS" = DIRTY ] && { echo RESULT=CONFLICT; break; }
  { [ "$MS" = CLEAN ] || [ "$MS" = HAS_HOOKS ]; } && { echo RESULT=READY; break; }
  if [ "$RUN" -eq 0 ]; then
    [ "$MS" = UNSTABLE ] && { echo RESULT=READY; break; }
    [ "$MS" = BLOCKED ]  && { echo RESULT=BLOCKED; break; }
    [ "$MS" = BEHIND ]   && { echo RESULT=BEHIND; break; }
  fi
  [ "$(date +%s)" -ge "$END" ] && { echo RESULT=RUNNING; break; }
  sleep 3
done
```

### 5.3 依 `RESULT` 處理

| RESULT | 意義 | 行為 |
|---|---|---|
| `READY` | 可合併（CI 全過，或無必需 CI 已 mergeable） | **立即**進第 6 節，發提醒 + 等使用者確認；不糾結個別非必需 check |
| `RUNNING` | 心跳窗內仍在跑 | 回報一次心跳（哪些 check 在跑、已耗時多久）→ 立刻再跑下一批 |
| `FAILED` | 有 check 失敗 | 立即停止，`gh run view <run-id> --log-failed` 讀根因，回報建議修法 |
| `BLOCKED` | checks 跑完仍被擋（缺 review／缺必需 check） | 回報卡在哪（`reviewDecision`／缺哪個必需 check），問使用者如何處理 |
| `BEHIND` | 分支落後 base，可能需先更新 | 回報，建議 `gh pr update-branch` 或 rebase 後再監控 |
| `CONFLICT` | 與 base 有衝突（`DIRTY`） | 停止，回報需 rebase／解衝突 |
| `MERGED_OR_CLOSED` | PR 已被合併或關閉 | 停止，回報最終狀態 |

- **每批先回報再決定**；`RUNNING` 也要回報，讓使用者隨時看得到進度。
- 失敗時：`gh run view <run-id> --log-failed` 取實際錯誤。**不自行重跑到過**、不改 workflow 繞過、不加 `continue-on-error`、不 `--admin` 略過保護規則。
- 連續多批 `RUNNING`、總耗時超過合理範圍時，主動問使用者要繼續等還是先擱置，不無限輪詢。

## 6. PR 可合併（READY）→ 提醒使用者確認合併

PR 進入可合併狀態後（CI 全過，或此 repo 無必需 CI 但 GitHub 已顯示 mergeable），**必須主動發出明顯提醒**，然後停下來等待。

```powershell
[console]::beep(880,200); [console]::beep(1320,300)   # 提示音
```

輸出格式：

```markdown
🔔 **CI 全部通過 — 等待你確認合併**

- PR：#<N> <title>
- 連結：<url>
- 合併狀態：<mergeStateStatus，例 CLEAN>（review：<reviewDecision 或「不需要」>）
- Status checks：✅ <N>/<N> passed（耗時 <mm:ss>）；此 repo 無必需 CI 時標「PR 無 CI checks，依 mergeable 判定」
  - build ✅ / test ✅ / lint ✅
- 變更：<N> files, +<X>/-<Y>
- Reviewer：<user 或「未指定」>
- 待人工確認：<截圖 / 手動驗證項目 / 無>

👉 **用互動式選擇工具彈出可點按鈕請使用者確認合併**（下列為選項標籤，不要當純文字印出；使用者不需打字）：
**[Confirm merge]（最建議）**　／　**[尚未，先不要]**
```

### 合併規則（重要）

- **確認一律用互動式選擇工具彈出真正可點的按鈕**（不是把方括號當文字印出），不要求使用者打字（打字僅作備援）。CI 通過後彈出 **[Confirm merge]（最建議） / [尚未，先不要]**。
- **agent 不主動合併。** 一律等到使用者**點下 [Confirm merge] 按鈕**、按下 GitHub 的 Confirm merge 按鈕，或明確打 `confirm merge` / `合併`。點下 [Confirm merge] 即由我執行 `gh pr merge <N> --squash --delete-branch`。
- 使用者回覆「OK」、「好」、「可以」等模糊字眼、或未點按鈕**不視為合併授權** → 再以按鈕請他確認一次。
- 代為合併時，merge 策略（`--squash` / `--rebase` / `--merge`）依 repo 歷史慣例判斷，不自行選擇。
- 合併後回報：merge commit SHA、分支是否已刪除、後續建議（例如是否要跑 `/m2_release`）。

## 7. 回報

輸出：PR 連結、title、變更檔案數、CI 狀態與耗時、指定的 reviewer、待人工補齊的項目（截圖、手動驗證）、目前停在哪一步等待什麼。

---

## 硬性規則

- 不直接 push 到 `main`。
- **不自行 merge PR。** 必須等使用者**點下 [Confirm merge] 按鈕**、按下 GitHub 的 Confirm merge 按鈕，或明確打 `confirm merge`；模糊回覆不算授權。確認一律以按鈕呈現，不要使用者打字。
- PR 建立後**必須持續監控至有明確結論**（`READY` / `FAILED` / `BLOCKED` / `BEHIND` / `CONFLICT`）：監控**以有界的同步批次執行、由你自己一批接一批驅動**，收到 `RESULT=RUNNING` 一定**在同一個回合內立即再跑下一批**；**不可 fire 成背景（async）後就結束回合等通知**——async 只在批次到點時通知，常在 CI 尚未完成時就結束，會造成「GitHub 已完成、agent 沒反應」；亦不可停在 RUNNING、不可只查一次就結束回合。
- 不在開 PR 的過程中順手修改程式碼；發現問題先回報，由使用者決定。
- 不 force push 已被 review 過的分支（必要時改用新 commit）。
- PR body 中不出現機密資訊、客戶專案代號、成本數字。
- title / body 格式一律比對 repo 歷史後沿用，不自創風格。
- 任何前置檢查未通過 → 停下來回報，不自行修補後繼續。
