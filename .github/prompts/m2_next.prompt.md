---
description: PR 合併後的收尾 — 刪除已合併分支、切回並更新 main、確認 PR 已進 main、確認工作區乾淨，備妥下一輪工作。
mode: agent
---

# Next

**觸發**：`/m2_next`、`/m2_next <PR 編號>`、`/m2_next auto`

- `/m2_next` → 自動判斷剛剛的 PR（由當前分支對應）
- `/m2_next <PR>` → 指定要收尾的 PR 編號
- `/m2_next auto` → **全自動**：不彈按鈕，自行完成收尾（見 §Auto 模式）；可並用，例 `/m2_next 42 auto`

> 用途：跑完 `/m2_pr`、PR 已合併後的收尾。把本機帶回乾淨的 `main`、清掉已合併分支、確認狀態，
> 讓下一件工作從乾淨的起點開始。**不做**任何功能變更、不 commit、不開新 PR。

---

## 0. 先用 gh 查證、再用 GitHub API 重複查證 PR 狀態（第一步）

刪分支是破壞性動作，所以合併狀態要用**兩個獨立來源交叉比對**，一致才算數：

```bash
# (1) gh CLI 查
gh pr view <PR> --json number,state,mergedAt,mergeStateStatus,headRefName

# (2) GitHub REST API 重複查證（{owner}/{repo} 由 gh 自動代入當前 repo）
gh api repos/{owner}/{repo}/pulls/<PR> --jq '{merged, merged_at, state}'
```

- 未指定 `<PR>` 時，從當前分支對應的 PR 判斷；判斷不出來就**以按鈕請使用者選**要收尾哪個 PR。
- **兩邊必須一致為「已合併」才繼續**：
  - gh：`state == "MERGED"`
  - API：`.merged == true`（注意 REST 的 `state` 對已合併 PR 會是 `"closed"`，要看 `merged` 布林值，不是 `state`）
- 兩來源**不一致**（例如一邊已 merged、一邊還沒）→ **停止並回報**，不動任何東西（可能是 GitHub 尚在同步，稍後重查）。
- 依結果分流：
  - 兩邊皆**已合併** → 繼續收尾。
  - **未合併（OPEN）** → **先不清任何東西**。回報 CI checks 與 `mergeStateStatus`，並**用互動式選擇工具彈出按鈕**問使用者：**[等它合併好再收尾]（最建議） / [先中止]**。不自行合併。
  - **`CLOSED` 但 `merged == false`**（未合併就關閉）→ 停止並回報。
- **未經雙重查證確認合併前，一律不刪分支、不動本機。**

## 1. 看本機現況（唯讀）

```bash
git branch --show-current
git status --short            # 是否有未 commit / 未追蹤檔案
```

- 記下目前所在分支（通常是剛剛開 PR 的 feature 分支），後面收尾要刪的就是它。

## 2. 檢查工作區是否乾淨（有變更 → 先問）

```bash
git status --porcelain
```

- 輸出為空 → 乾淨，直接進第 3 節。
- 有**未 commit 變更**或**未追蹤檔案** → **停下來**，列出清單，並**用互動式選擇工具彈出按鈕**問使用者怎麼處理：
  - **[先中止，我自己處理]（最建議）**（交還給使用者，避免動到進行中的工作）
  - **[保留並繼續]**（不動這些檔案，照樣收尾）
  - 絕不自行 `git reset --hard`、`git clean`、或刪除未追蹤檔案（可能是進行中的工作）。

## 3. 切回 main 並更新到最新

```bash
git switch main
git pull --ff-only
```

- `--ff-only`：只允許快轉，避免把本機多餘 commit 併出奇怪的 merge。
- 若非快轉（本機 `main` 已分歧）→ 停下回報，不強拉、不 rebase、不 force。

## 4. 確認剛剛的 PR 已進 main

```bash
git log --oneline -5
git branch --merged main       # 該 feature 分支應已被 main 涵蓋
```

- 確認 `main` 最新 commit 已包含該 PR 的合併（squash commit 或 merge commit）。
- 對不上就停下回報，不繼續刪分支。

## 5. 刪除已合併分支（先用按鈕確認）

先列出「已合併、可安全刪除」的分支，**以可點選按鈕**請使用者確認後再刪：

```bash
git branch --merged main       # 已被 main 涵蓋的分支（排除 main 與當前分支即可安全刪）
```

- 用互動式選擇工具彈出按鈕確認：**[刪除這些分支]（最建議） / [跳過]**。
- 確認後：
  ```bash
  git branch -d <branch>                # 只刪已合併（-d，不用 -D 強刪）
  git push origin --delete <branch>     # 遠端若還在才刪；已被 GitHub 自動刪除則略過
  git fetch --prune                     # 清掉遠端已刪的追蹤 ref
  ```
- 只刪**本次相關**的分支，不掃掉其他人或無關的分支。

## 6. 收尾回報

確認並回報下列狀態，宣告可以開始下一輪：

- 目前分支：`main`
- `main` 是否已與 `origin/main` 同步（up to date）
- 該 PR 狀態：MERGED（附連結）
- 工作區：乾淨（無未 commit / 未追蹤檔案）
- 已刪除的分支清單（本機 / 遠端）
- ✅ 準備好開始新一輪工作

---

## Auto 模式（`/m2_next auto`）

通用契約見 `copilot-instructions.md` §9「Auto Mode」。這裡只講本流程的差異。

**第 0 節的雙重查證不得省略。** 刪分支是不可逆動作，`auto` 只免掉按鈕，**不免掉查證**。

### 三個按鈕節點在 auto 下的做法

| 節點 | 原本的按鈕 | auto 的做法 |
|---|---|---|
| §0 PR 尚未合併（OPEN） | [等它合併好再收尾] / [先中止] | **中止並回報**。`/m2_next` 是合併後的收尾，PR 還開著就是呼叫時機錯了，不在這裡等、也不代為合併 |
| §2 工作區不乾淨 | [保留並繼續] / [先中止] | **只有未追蹤檔** → 保留並繼續（不碰它們，`git switch` 不受影響）；<br>**有已追蹤檔的未 commit 變更** → **中止**（可能是進行中的工作，切分支會帶著跑） |
| §5 刪除已合併分支 | [刪除這些分支] / [跳過] | 自行刪除，但**只刪本次 PR 的 `headRefName` 那一支**，且只用 `git branch -d`。其他也已合併的分支**只列出來**，不代為刪 |

區分兩種髒的方式：

```bash
git diff --quiet && git diff --cached --quiet && echo "TRACKED=clean" || echo "TRACKED=dirty"
git ls-files --others --exclude-standard          # 有輸出 = 有未追蹤檔
```

### auto 仍然中止的情況

除了 §9 列的通用 ABORT 條件，本流程額外：

- `gh` 與 GitHub API 的合併狀態**不一致** → 中止（可能尚在同步，不要猜）
- PR 是 `CLOSED` 但 `merged == false`（未合併就關閉）→ 中止
- `git pull --ff-only` 非快轉 → 中止（**不** rebase、**不** force）
- 第 4 節對不上（`main` 最新 commit 不含該 PR）→ 中止，不刪分支
- 推斷不出要收尾哪個 PR（未給 `<PR>` 且當前分支對不到唯一 PR）→ 中止，**不猜**

### auto 的最終報告

嚶一聲後輸出：實際執行的步驟、代你做的決定與依據（尤其是工作區不乾淨時怎麼判的）、
最終狀態（分支 / `main` 同步狀態 / 已刪除的分支），以及**刻意沒動的東西**（保留的未追蹤檔、沒刪的其他分支）。

---

## 硬性規則

- **PR 未合併一律不刪分支**；合併狀態需經 `gh`（`state == MERGED`）與 GitHub API（`.merged == true`）**雙重查證一致**才算已合併。
- 刪分支只用 `git branch -d`（已合併才刪），不使用 `-D` 強刪。
- **絕不** `git reset --hard`、`git clean -fd`、或刪除未追蹤檔案 —— 那可能是進行中的工作；發現未追蹤檔案一律**以按鈕**問使用者。
- 切分支 / 更新 `main` 前若工作區不乾淨 → 停下確認，不硬切、不覆蓋。
- `git pull` 一律 `--ff-only`；非快轉就停下回報，不 rebase、不 force。
- 刪分支、切 `main` 等會改變狀態的動作，一律**以按鈕請使用者確認**，不要使用者打字。
  **唯一例外是使用者明打了 `/m2_next auto`**；不得從語氣**推論**出 auto 模式。即使在 auto，第 0 節的雙重查證也不得省略。
- 只處理本次相關分支，不主動清掉其他分支。
- 不做任何功能變更、不 commit、不開 PR。
