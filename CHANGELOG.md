# Changelog

本檔案記錄通用規範與 prompt files 的變更。
下游 repo 收到自動同步 PR 時，以此判斷是否需要注意行為變化。

版本規則：`v<major>.<minor>.<patch>`

- **major** — 破壞性變更：prompt 檔更名或移除、slash command 改名、
  流程確認節點變動、同步範圍調整。合併前需通知所有下游 repo。
- **minor** — 新增 prompt file、新增規範章節、新增檢查項目。
- **patch** — 措辭修正、錯字、範例補充，行為不變。

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
