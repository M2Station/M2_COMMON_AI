---
description: PR-based CI release — bump version, open & merge PR, tag, push tag; CI builds & publishes.
mode: agent
---

# Release

**觸發**：`/m2_release`、`/m2_release <version>`

- `/m2_release` → 依規則自動計算下一版號
- `/m2_release 0.4.1` → 使用指定版號，跳過第 1 節計算

執行一次完整發版。流程為 **bump → PR → merge → tag → push tag → CI publish**。

## 0. 先對齊 repo 慣例（必做，不可略過）

在動手前先讀出既有慣例，所有格式一律沿用歷史紀錄，不自創：

```bash
git tag --sort=-v:refname | head -10          # tag 格式（有無 v 前綴、是否 annotated）
gh pr list --state merged --limit 10           # release PR 的 title / body 格式
git log --oneline -15                          # commit message 格式
ls .github/workflows/                          # 確認 publish workflow 的觸發條件
```

- 從 workflow 檔確認 **publish 是由 tag push 觸發**，以及 tag pattern（例如 `v*` 或 `v[0-9]+.*`）。
- 確認版本號來源檔案（`package.json` / `pyproject.toml` / `Cargo.toml` / `manifest.json` / `__init__.py`…），可能有多處需同步。

## 1. 計算下一版號

規則：**patch 逐一遞增，滿 9 進位到 minor**。

```text
patch < 9                 → patch + 1              0.3.0 → 0.3.1
patch == 9                → minor + 1, patch = 0   0.3.9 → 0.4.0
minor == 9 且 patch == 9  → major + 1, 其餘歸零     0.9.9 → 1.0.0
```

- 以「目前 main 上的版本號」為基準，不以最新 tag 為基準（若兩者不一致，先停下來回報）。
- 若使用者已指定版號，直接採用，跳過計算。

## 2. Bump 版本

```bash
git switch main
git pull --ff-only
git switch -c release/<NEW_VERSION>
```

- 更新**所有**版本號出現的位置（含 lock file，若專案有 commit lock file 的慣例）。
- 若 repo 有 `CHANGELOG.md`，依既有格式新增一節，內容取自上一個 tag 至今的 commit：
  ```bash
  git log <LAST_TAG>..HEAD --oneline --no-merges
  ```
- **這個 PR 只做版本變更**，不夾帶任何功能或修正。

```bash
git commit -am "chore(release): bump version to <NEW_VERSION>"   # 格式沿用 repo 歷史
git push -u origin release/<NEW_VERSION>
```

## 3. 開 PR、監控 CI、確認後合併

```bash
gh pr create --base main --title "<沿用歷史格式>" --body "<摘要 + 變更清單>"
```

**監控 CI：沿用 `/m2_pr` 第 5 節的自結束輪詢**，不要用 `gh pr checks --watch`（CI 無輸出時會被終端機判 idle 而假性 timeout，無必需 CI 時會空等）。以 `gh pr view --json state,mergeStateStatus,statusCheckRollup` 輪詢，一有結論即跳出，**以有界的同步批次執行、由你自己一批接一批跑到有結論；收到 `RESULT=RUNNING` 必須在同一回合內立即再跑下一批，不可停在 RUNNING，也不可 fire 成背景後結束回合等通知**（否則 CI 稍後完成時沒人輪詢，會「GitHub 已完成、agent 沒反應」）：

- `RESULT=READY`（CI 全過，或無必需 CI 已 mergeable）→ 進入下方確認關卡。
- `RESULT=FAILED` → **停止發版**，`gh run view <run-id> --log-failed` 讀根因回報；不重試、不繞過、不改 workflow。
- `RESULT=RUNNING` → 回報一次心跳，再跑下一批。
- `RESULT=BLOCKED`／`BEHIND`／`CONFLICT` → 回報卡點（缺 review／需更新分支／有衝突），交使用者處理，不自行動作。

> ⏸ **CI 綠燈後、合併前停下來**，回報「將要發布的版號 + PR 連結 + 變更檔案清單 + CI 耗時」，並**用互動式選擇工具彈出真正可點的按鈕**（不是把方括號當文字印出）請使用者確認：**[Confirm release]（最建議） / [取消]**（不要求打字，打字僅作備援）。點 **[Confirm release]** 即為授權合併。
> （若要全自動，刪除此段確認。）

確認後才合併（merge 策略沿用 repo 歷史）：

```bash
gh pr merge --squash --delete-branch
```

## 4. 打 tag 並推送

```bash
git switch main
git pull --ff-only            # 確認 HEAD 已包含剛合併的 bump commit
git tag -a <TAG> -m "<MSG>"   # 格式沿用歷史，通常為 v<NEW_VERSION>
git push origin <TAG>
```

- **tag 必須指向合併後的 main HEAD**，不可在 PR 分支或合併前打 tag。
- 推送 tag 前確認 `git log -1` 的 commit 就是版本 bump commit。

## 5. 驗證 publish workflow

`gh run watch` 同樣會在 job 無輸出時被終端機判 idle 而假性 timeout；改用會**自己結束**的輪詢追蹤 tag 觸發的 publish run（**以有界的同步批次執行、由你自己驅動；收到 `RESULT=RUNNING` 必須在同一回合內再跑下一批，不可 fire 成背景後結束回合等通知**）：

PowerShell：

```powershell
$wf  = '<publish workflow 檔名，取自第 0 節>'   # 例 publish.yml / release.yml
$end = (Get-Date).AddSeconds(120)          # 心跳窗，可調
do {
    $r = gh run list --workflow $wf --limit 1 --json databaseId,status,conclusion,workflowName,url |
         ConvertFrom-Json | Select-Object -First 1
    Write-Host ("[{0}] {1} status={2} conclusion={3}" -f (Get-Date -f HH:mm:ss), $r.workflowName, $r.status, $r.conclusion)
    if ($r.status -eq 'completed') { "RESULT=$($r.conclusion)"; break }   # success / failure / cancelled
    if ((Get-Date) -ge $end)       { 'RESULT=RUNNING'; break }
    Start-Sleep -Seconds 3
} while ($true)
```

Bash：

```bash
WF='<publish workflow 檔名，取自第 0 節>'
END=$(( $(date +%s) + 120 ))
while :; do
  R=$(gh run list --workflow "$WF" --limit 1 --json databaseId,status,conclusion,workflowName,url)
  S=$(jq -r '.[0].status' <<<"$R"); C=$(jq -r '.[0].conclusion' <<<"$R")
  echo "[$(date +%T)] $(jq -r '.[0].workflowName' <<<"$R") status=$S conclusion=$C"
  [ "$S" = completed ] && { echo "RESULT=$C"; break; }
  [ "$(date +%s)" -ge "$END" ] && { echo RESULT=RUNNING; break; }
  sleep 3
done
```

- `RESULT=success` → 發布完成；若 workflow 會建立 release，`gh release view <TAG>` 確認。
- `RESULT=failure`／其他 → `gh run view <run-id> --log-failed` 讀根因回報；不重跑、不繞過。
- `RESULT=RUNNING` → 回報心跳後再跑下一批。

回報：版號、tag、PR 連結、CI run 連結、發布結果。

---

## 硬性規則

- 不直接 push 到 `main`，一律走 PR。
- 不在本機手動 `npm publish` / 上傳產物 — **發布只由 CI 執行**。
- CI 失敗時停止流程並回報，不重試、不繞過、不改 workflow 來讓它通過。
- tag 已存在時停止並回報，不使用 `-f` 覆寫、不刪除既有 tag。
- 版本號格式、tag 格式、commit / PR 文案一律比對 repo 歷史後沿用。
- 任何步驟出現與預期不符（版本號不一致、branch 非乾淨、pull 非 fast-forward）→ 停下來回報，不自行修補。
