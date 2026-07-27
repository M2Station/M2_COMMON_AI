# Changelog

本檔案記錄通用規範與 prompt files 的變更。
下游 repo 收到自動同步 PR 時，以此判斷是否需要注意行為變化。

版本規則：`v<major>.<minor>.<patch>`

- **major** — 破壞性變更：prompt 檔更名或移除、slash command 改名、
  流程確認節點變動、同步範圍調整。合併前需通知所有下游 repo。
- **minor** — 新增 prompt file、新增規範章節、新增檢查項目。
- **patch** — 措辭修正、錯字、範例補充，行為不變。

---

## v2.2.0 — 2026-07-27

### 新增

- **新增 `/m2_evolve`（`.github/prompts/m2_evolve.prompt.md`）** — 長時間自主迭代優化流程。
  給一個目標，agent 在 **12 小時時間預算**內反覆執行「找改進點 → 改 → 驗證 → smoke test → 收或退」，
  收斂或預算用盡才停。
  - 啟動前以互動式按鈕訪談六件事（範圍、專案輪廓、期望成果、改進重點、自主程度、checkpoint 模式），
    產出**凍結的 CHARTER**；目標無法量測就追問到可驗收為止。沒有 smoke test 就先建一個。
  - 全程寫入 `.evolve/<run-id>/`（CHARTER / BASELINE / STATE.json / LEDGER.md），
    支援 `/m2_evolve resume` 冷啟動接續；帳本以 `.git/info/exclude` 忽略，**不改 `.gitignore`**。
  - 三種 checkpoint 模式（`ask` / `notify` / `silent`）、檔案 kill switch（`.evolve/STOP`、`.evolve/PAUSE`），
    以及不可停用的 tripwire（連續 revert、blast radius 超標、要動公開 API/相依/schema、發現安全漏洞…）。
  - 「絕不作弊」硬性規則：不得改測試遷就實作、不得 skip/刪測試、不得放寬 lint 或 smoke test；
    回合報告固定列出「測試數」與「lint 問題數」前後對比。
  - 只在 `evolve/*` 分支工作，**不自行開 PR、不自行 merge** — 回合結束交給 `/m2_pr`。
  - Git 安全：commit 只 add 本迭代動到的檔（禁用 `git add -A`）、送出前 `git diff --cached` 自檢機密資料；
    退回時用 `git restore` + 逐一刪除本迭代新建的檔（**禁用 `git clean -fd` / `git reset --hard`**）。
- **全自動模式：指令後面加 `auto`** — `/m2_pr auto`、`/m2_next auto`、`/m2_release auto`。
  agent 自行解決每個確認節點，一路跑到任務完成，最後才輸出單一的工作流程 + 結果報告。
  - `auto` 為後置修飾字，可與現有參數並用：`/m2_pr draft auto`、`/m2_next 42 auto`、`/m2_release 0.4.1 auto`。
  - 只有這三支支援；`/m2_review` 不改狀態、`/m2_evolve` 已有 `checkpoint silent`。
  - **必須明打 `auto`**；不得從「你直接做」「不用問我」推論出 auto 模式。
- **`copilot-instructions.md` §9 新增「Auto Mode」通用契約**（三支 prompt 共用）：
  - 決策規則：優先選 repo 歷史支持的選項；**無依據且不可逆 → 中止**。
  - ABORT 清單（`auto` 一律不免）：CI 紅/逾時/取消、diff 含機密資料、已追蹤檔未 commit、
    **本機落後 `origin`**、PR 身分無法查證、tag 或版號已被用掉、合併衝突、需繞過 branch protection。
  - 永久禁止（任何模式）：force push、`git reset --hard`、`git clean -fd`、刪未追蹤檔、
    `git branch -D`、直推 `main`、本機發布產物。
  - **開工前強制新鮮度檢查**：`git fetch origin` 後確認 `git rev-list --left-right --count origin/main...HEAD`
    左邊為 `0`。落後的 base 是最具破壞性的失敗模式 —— 所有編輯都對到舊檔，開出來的 PR 會回退掉期間已合併的工作。
  - **合併/刪分支前強制用 `gh api` 查證 PR 身分**（`head.ref` / `base.ref` / title 全對）——
    `gh pr create` 的輸出與 `gh pr list` 均不可單獨作為依據。

### 變更

- `m2_pr` / `m2_next` / `m2_release` 各新增一節「Auto 模式」，明訂哪個節點被自動化、依什麼判斷、
  以及哪些情況仍然中止；硬性規則同步註明 auto 是唯一例外。
  - `m2_next auto`：工作區只有未追蹤檔 → 保留並繼續；有已追蹤檔的未 commit 變更 → 中止。
    只刪本次 PR 的分支，其他已合併分支只列出不代為刪。
  - `m2_release auto`：版本號與最新 tag 不一致、算出的版號已在 CHANGELOG、合併後 HEAD 不是 bump commit、
    release PR 夾帶其他檔案 → 一律停下並不打 tag。
- `copilot-instructions.md` §9 原本「不可跳過確認節點」的規則修正為「唯一例外是使用者明打 `auto`」，
  並補上 `/m2_evolve` 的 routing 條目與「與主流程正交」的說明。
- README 新增 `/m2_evolve` 與「全自動：指令後面加 `auto`」說明，目錄樹補齊五支 prompt。

---

### 新增

- **`m2_release` 新增「附錄 A：Release CI 產出規格（Portable + Setup + 靜默安裝）」**，
  把「M2_APEX 內建自動更新器吃得下的產物」寫成一份驗收契約：
  - 每次發版必須產出 4 個資產：Portable / Setup × x64 / arm64，檔名規則對齊 APEX 的
    `PickAsset()`／`IsInstallerAsset()`（單一架構 token、Setup 必含 `setup`、Portable 不可含）。
  - 靜默安裝契約：`/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` 需 exit code 0、
    全程無視窗；**app 執行中仍須能靜默覆蓋升級**（`.iss` 需 `AppMutex` 與 `CloseApplications=yes`，
    且 app 本體要建同名 single-instance mutex）。
  - exe 的 `ProductVersion` 必須是純 `X.Y.Z`（含 `+gitsha` 會被解析成 patch=0，誤判成「沒有更新」）。
  - 另含 Release CI 必做事項清單、常見地雷對照表、發版後驗收清單、M2_APEX catalog 登記格式。
- **`copilot-instructions` §9 新增 routing 條目**：`release ci`／`installer`／「打包規格」／
  「自動更新裝不起來」等語意，導向 `m2_release.prompt.md` 附錄 A。

### 說明

- 附錄 A 是**規格，不是流程**：只在建置／修改 build & release CI 或安裝檔腳本時讀；
  日常發一版仍走第 1～5 節，且不得順手改 workflow。既有發版流程行為不變。

---

## v2.0.0 — 2026-07-26

### 變更（破壞性）

- **資料夾同步由 mirror 改為 overlay：不再刪除下游自有的檔案。**
  - 先前 manifest 中結尾為 `/` 的路徑（`prompts/`、`instructions/`）走 `rsync --delete`，
    等同鏡像中央內容；下游 repo 放在同一資料夾的專案自有 prompt 會在同步時被刪掉。
  - 現在只覆寫「與中央同名」的檔案，**檔名沒有跟中央重複的下游檔案一律保留**。
  - 影響：中央刪除或更名某個 prompt 時，下游的舊檔不會自動消失，需下游自行清理。
  - 下游 repo 不需改任何檔案，邏輯住在中央 reusable workflow，下次排程自動生效。

---

## v1.6.1 — 2026-07-25

### 修正

- **CI／PR 監控改回「有界同步批次、由 agent 自己驅動」**，修掉「GitHub 已完成、agent 卻沒反應」：
  - 先前 v1.5.0／v1.6.0 指示監控「一律背景（async）執行、等通知」，但 async 只在**該批指令結束**時通知，
    而該批常在心跳窗到點（`RESULT=RUNNING`、CI 未完成）就結束；agent 若此時結束回合就無人輪詢，
    CI 稍後完成便沒人察覺。
  - 改為：`m2_pr` §5／硬性規則、`m2_release` §3／§5 一律「同步批次、收到 `RESULT=RUNNING` 於同一回合立即再跑下一批」，
    不得 fire 成背景後結束回合等通知。

---

## v1.6.0 — 2026-07-25

### 新增

- **需要使用者輸入／選擇／確認時發出提示音**：agent 交還控制、停下等待前，先用終端機發一聲
  短 beep（PowerShell `[console]::beep(880,200); [console]::beep(1320,300)`；bash/zsh `printf '\a'`），
  讓使用者不用盯著畫面也會注意到。屬 best-effort（視系統音效）；使用者可另外啟用 VS Code
  Accessibility Signals（設定 `accessibility.signals.*`，指令 **Help: List Signal Sounds**）取得穩定原生提示音。
  - `copilot-instructions.md` §1 新增此互動規則。

---

## v1.5.0 — 2026-07-25

### 變更

- **CI／PR 監控改為「會自己結束」的輪詢**，修掉假性 timeout 與「網頁已可合併卻空等」：
  - `m2_pr` §5 重寫：立即快照 + 自結束輪詢批次，依 `mergeStateStatus` 收斂為
    `READY/FAILED/BLOCKED/BEHIND/CONFLICT/MERGED_OR_CLOSED`；一律背景（async）執行、
    收到 `RESULT=RUNNING` 立即再跑，CI 一有結論 ≤3 秒跳出，不再用 `gh pr checks --watch`。
  - `m2_release` §3／§5 沿用同一套自結束監控（PR CI + publish run），移除 `gh run watch`。
- **確認節點改用互動式選擇工具的真按鈕**，並要求標一個 `（最建議）` 預設：
  - `copilot-instructions.md` §1／§8 立為中央規則：按鈕＝互動式選擇工具（非純文字），
    且每個決策點必須標一個 `（最建議）`。
  - `m2_pr` / `m2_release` / `m2_review` / `m2_next` 各確認點一併套用。
- 向後相容（打字仍作備援、確認節點位置不變），故列為 minor。

---

## v1.4.0 — 2026-07-24

### 變更

- **同步 workflow 改為 reusable workflow 架構**：新增中央
  `.github/workflows/sync-m2-common-ai-reusable.yml` 承載全部同步邏輯；
  `templates/sync-m2-common-ai.yml` 縮成 stub，用 `uses:` 呼叫中央 reusable。
  - 效果：日後升 action 版本、改同步邏輯、改 assignee 只需改中央 reusable，
    所有下游下次排程自動生效，不用逐一改下游檔案。
  - 下游 stub 只保留觸發時機（schedule / dispatch）、權限與 `uses:` pin，穩定少動。
  - `bootstrap-repo.ps1` 下載範本時額外要求含 reusable 參照，避免部署到舊版 monolith。
  - `validate.yml` 一併驗證 reusable workflow 可解析（並加入觸發路徑）。
- **一次性遷移**：既有下游 repo 需重跑一次 bootstrap 覆蓋那支 workflow 才會換成 stub
  （同步不碰 `.github/workflows/`，不會自動升級）；換過之後同步邏輯改動即永久自動傳播。
- 非破壞性：舊版 monolithic workflow 仍可運作，遷移前後不中斷，故列為 minor。

---

## v1.3.0 — 2026-07-24

### 新增

- `.github/prompts/m2_next.prompt.md` — `/m2_next`，PR 合併後收尾：
  用 `gh` + GitHub API 雙重查證 PR 已合併 → 回到並更新 `main` → 確認工作區乾淨 →
  刪除已合併分支 → 備妥下一輪。含按鈕式確認與安全護欄（未合併不刪、只 `-d`、
  不 `reset --hard`/`clean`、`pull --ff-only`）。
- `copilot-instructions.md` §9 路由表新增 `/m2_next`，並更新標準流程順序。

---

## v1.2.0 — 2026-07-24

### 變更

- 三支流程指令與通用規範改為**按鈕式互動**：需要使用者選擇或確認時，一律以可點選清單
  （按鈕）呈現，不再要求打字。
  - `copilot-instructions.md` 新增互動規則（§1 溝通、§8 行為）。
  - `m2_pr`：合併確認改為 **[Confirm merge] / [尚未]** 按鈕，點按即授權；
    仍保留打 `confirm merge` 與 GitHub 按鈕作為備援（模糊字眼仍不算授權）。
  - `m2_release`：發版合併前改為 **[Confirm release] / [取消]** 按鈕確認。
  - `m2_review`：`/m2_review fix` 逐項改為 **[修這項] / [略過] / [剩下的全修]** 按鈕。
- 打字確認仍作為備援（向後相容），故列為 minor 而非 major。

---

## v1.1.2 — 2026-07-24

### 變更

- `templates/sync-m2-common-ai.yml` 自動 PR 內文改為中英雙語（English 在前、中文在後），
  並修正 workflow 名稱指稱（檔名 `sync-m2-common-ai` → 顯示名 `Sync M2 Common AI`）、
  PR 標題加上 `[M2]` 前綴。純文案調整，同步行為不變；
  既有下游 repo 需重跑一次 bootstrap 才會套用（同步不碰 `.github/workflows/`）。
- 同步失敗通知 issue 改為中英雙語，並加上權限檢查提示
  （最常見失敗原因：Actions 未被允許建立 PR，導致無法開同步 PR）。

---

## v1.1.1 — 2026-07-24

### 變更

- `.github/copilot-instructions.md` 全文改寫為英文（原為繁體中文），
  規則語意、章節結構與檢查項目不變；純語言調整，行為不變。

---

## v1.1.0 — 2026-07-23

### 變更

- 同步機制改為 **manifest 驅動**：下游 `sync-m2-common-ai.yml` 改讀中央
  `.github/sync-manifest.txt` 決定同步範圍。之後新增同步路徑只需改中央 manifest，
  下游 workflow 不必再修改（已接入的 repo 需重跑一次 bootstrap 換到此版本）。
- 版本記錄檔更名 `.github/AI_CONFIG_VERSION` → `.github/M2_COMMON_AI_VERSION`，
  並新增 `changed_files` 欄位記錄本次同步實際變更的檔案；同步時會順手移除舊檔。

### 新增

- `.github/sync-manifest.txt` — 同步清單（single source of truth）。
- `scripts/validate.py` 新增 manifest 驗證（路徑合法性與存在性）。

### 修正

- manifest 路徑守衛改為**區段比對**：擋掉 `./workflows/` 這類經正規化後可繞過
  `workflows/` 阻擋的路徑（workflow 與 `validate.py` 一致）；同時不再誤擋含 `..`
  的合法檔名（如 `a..b.md`）。

---

## v1.0.0 — 2026-07-23

初版。

### 新增

- `.github/copilot-instructions.md` — 跨專案通用規範（12 章）。
  採自我探查設計，不記錄任何專案特定資訊，可原封不動用於任何 repo。
- `.github/prompts/m2_review.prompt.md` — `/m2_review`，自我 code review，
  依 Blocker / Should fix / Nit 分級，預設不修改程式碼。
- `.github/prompts/m2_pr.prompt.md` — `/m2_pr`，開 PR 後每 3 秒輪詢 status check，
  全過時發出提醒並等待使用者確認合併。
- `.github/prompts/m2_release.prompt.md` — `/m2_release`，
  版本 bump → PR → merge → tag → CI publish。
  版號規則：patch 逐一遞增，滿 9 進位到 minor。
- `templates/sync-m2-common-ai.yml` — 下游 repo 的同步 workflow。
  中央 repo 為 public，故不需任何 token / secret / variable；
  排程失敗時自動開 issue。
- `scripts/validate.py` — 設定檔結構與 frontmatter 驗證。
- `scripts/bootstrap-repo.ps1` — 一鍵將同步機制安裝進指定 repo。
- `docs/adr-001-visibility.md` — visibility 決策記錄，決議為 Private + GitHub App。

### 決策

- 中央 repo 採 **public**，消費端零設定認證。
  各專案 repo 維持 private，不受影響。
  決策脈絡與被推翻的 private + GitHub App 方案見 `docs/adr-001-visibility.md`。
