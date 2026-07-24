# Changelog

本檔案記錄通用規範與 prompt files 的變更。
下游 repo 收到自動同步 PR 時，以此判斷是否需要注意行為變化。

版本規則：`v<major>.<minor>.<patch>`

- **major** — 破壞性變更：prompt 檔更名或移除、slash command 改名、
  流程確認節點變動、同步範圍調整。合併前需通知所有下游 repo。
- **minor** — 新增 prompt file、新增規範章節、新增檢查項目。
- **patch** — 措辭修正、錯字、範例補充，行為不變。

---

## v1.4.0 — 2026-07-24

### 變更

- **同步 workflow 改為 reusable workflow 架構**：新增中央
  `.github/workflows/sync-m2-common-ai-reusable.yml` 承載全部同步邏輯；
  `templates/sync-m2-common-ai.yml` 縮成薄 stub，用 `uses:` 呼叫中央 reusable。
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
