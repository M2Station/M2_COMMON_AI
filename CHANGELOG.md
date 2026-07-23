# Changelog

本檔案記錄通用規範與 prompt files 的變更。
下游 repo 收到自動同步 PR 時，以此判斷是否需要注意行為變化。

版本規則：`v<major>.<minor>.<patch>`

- **major** — 破壞性變更：prompt 檔更名或移除、slash command 改名、
  流程確認節點變動、同步範圍調整。合併前需通知所有下游 repo。
- **minor** — 新增 prompt file、新增規範章節、新增檢查項目。
- **patch** — 措辭修正、錯字、範例補充，行為不變。

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
- `templates/sync-ai-config.yml` — 下游 repo 的同步 workflow。
  中央 repo 為 public，故不需任何 token / secret / variable；
  排程失敗時自動開 issue。
- `scripts/validate.py` — 設定檔結構與 frontmatter 驗證。
- `scripts/bootstrap-repo.ps1` — 一鍵將同步機制安裝進指定 repo。
- `scripts/pull-latest.ps1` — 更新本地 clone（VS Code 路徑方案用）。
- `docs/adr-001-visibility.md` — visibility 決策記錄，決議為 Private + GitHub App。

### 決策

- 中央 repo 採 **public**，消費端零設定認證。
  各專案 repo 維持 private，不受影響。
  決策脈絡與被推翻的 private + GitHub App 方案見 `docs/adr-001-visibility.md`。
