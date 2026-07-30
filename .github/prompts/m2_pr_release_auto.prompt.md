---
description: Fully unattended delivery: run /m2_pr auto for the current committed changes, then run /m2_release auto and verify the GitHub Release. No confirmation prompts.
mode: agent
---

# PR And Release Auto

**觸發**：`/m2_pr_release_auto`、`pr release auto`、`PR 合併後自動發版`、`無人職守推送並發布`

這是一支固定為全自動的 orchestration prompt。依序執行：

```text
目前分支已 commit 的變更
  -> /m2_pr auto
  -> 確認 PR 已合併且 main 已同步
  -> /m2_release auto
  -> 確認 tag、publish workflow 與 GitHub Release
```

全程不彈確認按鈕、不等待人工決策。`auto` 只免除確認節點；所有安全查證與 ABORT 條件仍然有效。

## 0. 載入底層流程

開始前必須完整讀取並遵守：

1. `.github/prompts/m2_pr.prompt.md` 的 `/m2_pr auto` 流程。
2. `.github/prompts/m2_release.prompt.md` 第 0～5 節與 `Auto 模式`；不要載入或執行附錄 A。
3. `.github/copilot-instructions.md` §9 的 Auto Mode 通用契約。

本 prompt 只定義階段順序與交接條件。底層 prompt 的前置檢查、輪詢、身分查證、決策規則、ABORT 條件與
最終驗證不得省略、弱化或改寫。

## 1. 執行目前變更的 PR

將使用者輸入 `/m2_pr_release_auto` 視為已明確授權第一階段使用 `auto`。

### 1.1 自動提交未 commit 的變更

```bash
git status --short
git branch --show-current
```

- **已追蹤檔案**：一律 `git add -u`（涵蓋修改與刪除）。
- **未追蹤檔案**：只加入**本次功能確實需要的新檔**，且必須**逐一列出完整路徑**
  （例 `git add .github/prompts/m2_foo.prompt.md`）。**禁用 `git add -A`、`git add .` 與任何萬用字元**。
  - 判斷依據：該檔是否被本次變更的其他檔案引用（routing、import、設定、文件連結），
    或明顯是本次功能的組成部分。**無法判定 → 不加入**，並在最終報告列為「已略過的未追蹤檔」。
  - **一律排除**：`.env*`、金鑰與憑證檔、log、快取、建置產物、`node_modules/`、
    測試暫存檔，以及任何已被 `.gitignore` 忽略的路徑。
  - 新增的檔案必須在最終報告中逐一列出，讓使用者事後可核對。
- **目前在 `main` 上時不可就地提交**：先讀實際 diff 判斷變更類型，依分支慣例建立
  `feature/<描述>`／`fix/<描述>`／`chore/<描述>`，切過去之後才提交。
- commit 前必須 `git diff --cached` 自檢；出現帳號、密碼、token、API key、內部 IP 或客戶資料
  → **立即中止且不提交**。
- commit message 依 repo 歷史沿用 Conventional Commits，內容取自實際 diff，
  不寫 `update code` 這類無資訊量訊息。
- 已追蹤變更為空 → 跳過本節。若同時也沒有任何可進 PR 的 commit → 停止並回報「沒有要發布的變更」。

### 1.2 執行 `/m2_pr auto`

完整執行 `/m2_pr auto`：

- 處理目前分支上已 commit、尚未進入 `main` 的變更。
- 必須 push 當前分支、建立或更新該分支唯一的 PR、持續監控 CI、查證 PR 身分並依 repo 慣例合併。
- 第一階段若觸發任何 ABORT，立即停止整支流程；不得開始 release。

## 2. PR 到 Release 的交接關卡

只有第一階段成功後才能繼續。開始 release 前重新查證：

```bash
git fetch origin
git status --short
git switch main
git pull --ff-only
git rev-list --left-right --count origin/main...HEAD
```

必須同時成立：

- 第一階段 PR 經 GitHub REST API 確認為 `merged=true`，且 merge SHA 可取得。
- working tree 乾淨。
- 目前位於 `main`，且 `origin/main...HEAD` 為 `0 0`。
- `main` HEAD 已包含第一階段 PR 的合併結果。

任一不成立就 ABORT。不得用 rebase、force push、hard reset、stash 或直接 push `main` 修補狀態。

## 3. 自動發布版本

交接關卡通過後，將本指令視為已明確授權第二階段使用 `auto`，完整執行 `/m2_release auto`：

- 依 release prompt 規則從 `main` 計算下一版號並先輸出計算結果。
- 建立 `release/<NEW_VERSION>`、只提交版本號與 CHANGELOG 變更、push 並建立 release PR。
- 持續監控 CI；READY 後查證 release PR 身分，再依 repo 慣例自動合併。
- tag 必須指向合併後的 `main` HEAD；push tag 後持續監控 publish workflow。
- publish workflow 必須為 `RESULT=success`，並以 `gh release view <TAG>` 驗證 GitHub Release 頁面存在。
- 若 repo 的 workflow 成功但設計上不建立 GitHub Release，停止並明確回報「publish 成功但沒有 Release 頁面」；
  不得宣稱已發布到 Release 畫面。

第二階段任何 ABORT 或失敗都立即停止。已完成的 PR merge 或 tag push 不回退，也不得重跑、覆寫 tag 或繞過保護規則。

## 4. 單一最終報告

正常執行期間只提供必要的 CI 心跳；不要求使用者輸入。完成或 ABORT 後嗶一聲，輸出一份合併報告：

```markdown
## /m2_pr_release_auto 結果

- 結果：完成 / ABORT
- 第一階段 PR：<url>｜merge SHA：<sha>｜CI：<result + run url>
- 發布版本：<version>｜tag：<tag>
- Release PR：<url>｜merge SHA：<sha>｜CI：<result + run url>
- Publish：<result + run url>
- GitHub Release：<release url，未建立時明確寫無>
- 本次新增並提交的檔案：<逐一列出，無則寫無>
- 已略過的未追蹤檔：<逐一列出，無則寫無>

### 實際執行步驟
1. <依時間順序列出實際完成的動作>

### 自動決策與依據
| 節點 | 決定 | 依據 |
|---|---|---|
| <版號 / merge 策略 / tag 格式等> | <採用值> | <repo 歷史或設定> |

### 未完成事項
- <無，或 ABORT 原因與停在哪一步>
```

不可把未執行、未成功或未經 API 驗證的步驟寫成完成。

## 硬性規則

- 這支指令本身就是明確的全自動授權，不需再要求使用者輸入 `auto`，也不得彈確認按鈕。
- 不執行 `/m2_next`；第一階段後由本 prompt 的交接關卡同步 `main`，再交給 `/m2_release auto`。
- 不執行 smoke test、修改 app code、修 CI、修改 release workflow 或套用 release prompt 附錄 A。
- 自動提交採 `git add -u` 加上**逐一明列路徑**的本次新檔；禁用 `git add -A`、`git add .` 與萬用字元，
  不得提交機密檔或建置產物、不得刪除 untracked 檔案、不得在 `main` 上提交。
- 任一底層 ABORT 條件優先於「無人職守」要求；ABORT 時不向使用者追問，直接停止並在最終報告列明原因。
- 絕不 force push、`git reset --hard`、`git clean -fd`、`git branch -D`、直接 push `main`、覆寫或刪除 tag、
  使用 `--admin` / `--no-verify`，或從本機直接發布 artifact。