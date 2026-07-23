# M2_AI_CONFIG

集中維護 GitHub Copilot 的**通用**規範與工作流程 prompt，供組織內所有 repo 共用。
單一來源、單點更新，各專案自動同步。

---

## 目錄結構

`.github/` 就是 source of truth —— 中央 repo 自己也吃自己的設定（dogfooding），
所以在這個 repo 裡開 Copilot Chat 就能直接測試 `/m2_review`、`/m2_pr`、`/m2_release`。

```text
M2_AI_CONFIG/
├── README.md                         ← 本檔：原理與使用說明
├── CHANGELOG.md                      ← 每次規範變更的記錄（消費端據此判斷是否升級）
├── docs/
│   └── adr-001-visibility.md         ← public / private 決策記錄與認證方案
│
├── .github/                          ← ★ source of truth，同步的內容就是這裡
│   ├── copilot-instructions.md       ← 通用規範（always-on，跨專案，不含專案特定資訊）
│   ├── prompts/                      ← 工作流程 slash commands（on-demand）
│   │   ├── m2_review.prompt.md       ← /m2_review
│   │   ├── m2_pr.prompt.md           ← /m2_pr
│   │   └── m2_release.prompt.md      ← /m2_release
│   ├── instructions/                 ← 路徑範圍規範（applyTo glob，選用）
│   │   ├── frontend.instructions.md  ← applyTo: "**/*.{html,css,js,jsx,tsx}"
│   │   └── security.instructions.md  ← applyTo: "**/{api,server,db}/**"
│   └── workflows/
│       └── validate.yml              ← CI：檢查 frontmatter 格式與必要欄位
│
├── templates/
│   └── sync-ai-config.yml            ← 消費端 repo 要放的同步 workflow
│
└── scripts/
    ├── bootstrap-repo.ps1            ← 一鍵把同步機制裝進某個 repo
    └── pull-latest.ps1               ← 本地 clone 拉最新（方案 B 用）
```

### 版本策略

- `main` = 最新，`v<major>.<minor>.<patch>` tag = 穩定點。
- 消費端預設同步 `main`；需要穩定時，把 workflow 的 `ref` 改為某個 tag 並固定。
- **破壞性變更**（例如更名 prompt 檔、改變流程確認節點）必須 bump major 並寫入 `CHANGELOG.md`。

---

## 原理

### Copilot 的三層客製機制

三種檔案的**載入時機完全不同**，這是設計時最關鍵的區別：

| 檔案 | 位置 | 載入方式 | 用途 |
|---|---|---|---|
| `copilot-instructions.md` | `.github/` | **always-on**，每次請求都載入 | 跨專案通用規範：語言、命名、安全、Git |
| `*.instructions.md` | `.github/instructions/` | 依 `applyTo` glob **自動**匹配當前檔案 | 分領域規範：前端 / 後端 / 測試 |
| `*.prompt.md` | `.github/prompts/` | **僅在打 `/<檔名>` 時**才送給模型 | 多步驟工作流程：review / pr / release |

三者可同時生效並疊加。例如編輯 `src/api/user.js` 時，`copilot-instructions.md`
＋ `security.instructions.md`（`applyTo: src/api/**`）會一起載入。

### 為什麼工作流程要用 prompt file，不寫進 instructions？

因為 `copilot-instructions.md` 每次請求都會載入。發版流程有 40 行細節，
若寫進 always-on 檔案，會在你只是問「這個函式做什麼」時也占用 context，
稀釋掉真正重要的規範。**prompt file 是 on-demand 層**，只在你需要時才進場。

反過來說，**觸發路由表必須寫在 `copilot-instructions.md`**（見其 §9）—
因為 agent 必須「總是知道」有這些 prompt 存在，才可能在你說「發版」時去讀對應檔案。

### 為什麼通用規範不能含專案資訊

同步機制會**整份覆蓋** `copilot-instructions.md`。任何寫在裡面的專案特定內容
（專案名稱、技術堆疊、目錄結構）都會在下次同步時被抹掉。

所以本 repo 的 `copilot-instructions.md` 採**自我探查**設計：它不記錄專案事實，
只規定 agent 要怎麼從 `README.md`、`package.json`、`.github/workflows/`、`git log`
自行推導脈絡（詳見該檔 §2）。這讓同一份檔案能原封不動用在任何 repo。

**分界原則：**

| 內容 | 放哪 |
|---|---|
| 語言、命名、Git、安全、agent 行為規範 | 中央 repo（會被同步） |
| 通用工作流程（review / pr / release） | 中央 repo（會被同步） |
| 專案架構、模組職責、特殊業務邏輯 | **專案自己的** `.github/instructions/<name>.instructions.md`（用 `applyTo` 限定範圍，同步時排除） |
| 客戶專案代號、成本數字、內部 IP、憑證 | **哪裡都不放** |

### 已知限制

- prompt files **不影響 inline ghost-text completion**，那是另一套系統。
- Copilot 做 **PR code review 時讀的是 base branch** 的 `copilot-instructions.md`，
  不是 feature branch 的。新規範要 merge 進 `main` 後才對 review 生效。
- `chat.*FilesLocations` 這類「指向外部資料夾」的設定曾被 VS Code 移除過先例
  （`chat.modeFilesLocations`），因此**不建議只依賴方案 B**。

---

## 工作流程

三支 prompt 設計為串接使用，每一支都有「停下來等人確認」的節點：

```text
寫完 code
   │
   ├─ /m2_review ───► 分級回報（🔴 Blocker / 🟡 Should fix / 🔵 Nit）
   │                  預設不改 code；/m2_review fix 才逐項確認後修
   │
   ├─ /m2_pr ───────► 讀 diff → 前置檢查 → 開 PR
   │                  → 每 3 秒輪詢 status check
   │                  → 全過則發提示音 + 🔔 提醒
   │                  ⏸ 等你按 Confirm merge（「OK」不算授權）
   │
   └─ /m2_release ──► 算版號 → bump PR → merge → tag → push tag
                      ⏸ 合併前回報並等確認
                      CI 由 tag 觸發 build & publish
```

版號規則（`m2_release.prompt.md` §1）：patch 逐一遞增，滿 9 進位到 minor。
`0.3.0 → 0.3.1`、`0.3.9 → 0.4.0`、`0.9.9 → 1.0.0`。

---

## 使用方式

### 方案 C：Actions 自動同步（推薦，團隊主力）

檔案實際落在各 repo 的 `.github/`，所以 GitHub.com 上的 Copilot code review、
cloud agent、以及其他人 clone 下來都有效 —— 這是方案 A / B 做不到的。

#### 設定項放在哪：全部在「消費端」，不在中央 repo

這是最容易搞錯的一點。下列三項設定都是給 `sync-ai-config.yml` 用的，
而那支 workflow 跑在**各個專案**裡 —— **中央 repo 一項都不需要設定**
（它只跑 `validate.yml`，不需要任何 variable 或 secret）。

| 設定項 | 用途 | 設定位置 | 中央 repo 需要嗎 |
|---|---|---|---|
| `CENTRAL_AI_REPO`（variable） | 告訴 workflow 去哪抓設定 | 消費端 repo **或 org 層級** | ❌ 不需要 |
| `AI_CONFIG_TOKEN`（secret） | 中央 repo 為 private 時的讀取權限 | 消費端 repo **或 org 層級** | ❌ 不需要 |
| Allow Actions to create PR | 讓 workflow 能開同步 PR | 消費端 repo **或 org 層級** | ❌ 不需要 |

#### 建議：設在 org 層級，只設一次

專案數量多時**不要逐個 repo 設定**。三項都可在組織層級設定並被所有 repo 繼承，
新專案接進來時完全不必再設定。

```powershell
# 1. 組織層級變數
gh variable set CENTRAL_AI_REPO --org M2Station --visibility all --body "M2Station/M2_AI_CONFIG"

# 2. 組織層級 secret（中央 repo 為 private 時才需要）
gh secret set AI_CONFIG_TOKEN --org M2Station --visibility all --body "<PAT>"

# 3. 此項僅能於網頁設定
#    https://github.com/organizations/M2Station/settings/actions
#    → Workflow permissions
#    → 勾選 Allow GitHub Actions to create and approve pull requests
```

網頁操作路徑：`Organization Settings → Secrets and variables → Actions`
→ `Variables` / `Secrets` 分頁 → `New organization variable / secret`
→ `Repository access` 選 `All repositories`。

不想全開時改用 `--visibility selected --repos repo-a,repo-b`。

> ⚠️ **優先順序：repo 層級會覆蓋 org 層級。**
> 若某 repo 曾設過 repo 層級的 `CENTRAL_AI_REPO`，之後改 org 層級對它無效。
> 清除：`gh variable delete CENTRAL_AI_REPO --repo <owner>/<name>`

#### 接入新 repo

org 層級已設定的情況下，每個專案只需要放入 workflow：

```powershell
# 方式一：用腳本（會自動抓範本、開 PR）
Z:\M2_AI_CONFIG\scripts\bootstrap-repo.ps1 -CentralRepo M2Station/M2_AI_CONFIG

# 方式二：手動（中央 repo 為 private，不能用 curl 匿名抓，需經 gh api）
mkdir -Force .github\workflows
gh api repos/M2Station/M2_AI_CONFIG/contents/templates/sync-ai-config.yml `
  -H "Accept: application/vnd.github.raw" > .github\workflows\sync-ai-config.yml
git add . && git commit -m "chore(ai): add central config sync" && git push

# 立即跑一次，不等排程
gh workflow run sync-ai-config.yml
```

> 若**未**採用 org 層級設定，才需要在每個 repo 補上：
> `gh variable set CENTRAL_AI_REPO --body "M2Station/M2_AI_CONFIG"`
> 以及（private 時）`gh secret set AI_CONFIG_TOKEN --body "<PAT>"`。

之後每週一自動開一個同步 PR。每次同步會寫入 `.github/AI_CONFIG_VERSION`，
記錄來源 repo、ref、SHA 與時間，方便追溯是哪一版同步進來的。

#### 認證方式：GitHub App（本 repo 為 private）

中央 repo 為 private，因此消費端的 `github.token` 無法讀取它
（`github.token` 只作用於當前 repo，無法跨 repo、跨 visibility 邊界）。

採用 **GitHub App** 而非 PAT，原因是 PAT 有到期日，而**到期時所有 repo 的同步會同時
失效且無人察覺**（排程任務紅燈通常沒人在看）。App 的私鑰不會過期，每次執行換發
1 小時期效的 installation token。

**org 層級只需設定三項，之後接任何專案都不必再設：**

| 類型 | 名稱 | 內容 |
|---|---|---|
| Variable | `CENTRAL_AI_REPO` | `M2Station/M2_AI_CONFIG` |
| Variable | `AI_CONFIG_APP_CLIENT_ID` | GitHub App 的 Client ID |
| Secret | `AI_CONFIG_APP_KEY` | App 私鑰 `.pem` 全文 |

App 權限只需 **Repository permissions → Contents: Read-only**，
且只安裝到 `M2_AI_CONFIG` 這一個 repo —— 權限範圍比 PAT 小得多。

同步 workflow 另外加了 `if: failure()` 步驟，排程失敗時會自動開 issue，
避免靜默失效。

> 完整的 public / private 利弊分析、其他認證方案對照、以及日後若要改為公開的
> 檢查清單，見 [`docs/adr-001-visibility.md`](docs/adr-001-visibility.md)。

#### 本組織的實際設定（已完成）

| 項目 | 值 |
|---|---|
| 中央 repo | `M2Station/M2_AI_CONFIG`（private） |
| GitHub App | `m2-ai-config-sync`，權限 Contents: Read-only，僅安裝於 `M2_AI_CONFIG` |
| Org variable | `CENTRAL_AI_REPO` = `M2Station/M2_AI_CONFIG` |
| Org variable | `AI_CONFIG_APP_CLIENT_ID` = `Iv23li…`（完整值見 App 設定頁） |
| Org secret | `AI_CONFIG_APP_KEY` = App 私鑰 `.pem` 全文 |
| Actions 權限 | [org settings](https://github.com/organizations/M2Station/settings/actions) → 已允許 Actions 建立 PR |

重建或輪替時使用的指令：

```powershell
gh variable set AI_CONFIG_APP_CLIENT_ID --org M2Station --visibility all --body "<CLIENT_ID>"

gh secret set AI_CONFIG_APP_KEY --org M2Station --visibility all `
  --body (Get-Content "Z:\m2-ai-config-sync.<date>.private-key.pem" -Raw)

gh variable set CENTRAL_AI_REPO --org M2Station --visibility all --body "M2Station/M2_AI_CONFIG"
```

> **私鑰檔請勿長期留在共用磁碟（如 `Z:\`）。**
> 設定完成後即可刪除 —— GitHub 端只保留公鑰，私鑰僅存於 org secret。
> 遺失時不需要救援，直接在 App 頁面重新產生一把再更新 secret 即可。

> **App token 的授權範圍由 `CENTRAL_AI_REPO` 推導**（workflow 的 `Resolve central
> repo name` 步驟），因此中央 repo 若更名，只需改這一個 org variable，
> 不必逐一修改各專案的 workflow。

### 方案 A：VS Code User Profile（個人日常，零設定）

把 prompt files 放使用者層級，所有 workspace 都能用，並靠 Settings Sync 跨裝置同步。

1. Command Palette → `Chat: New Prompt File` → 選 **User**
2. 貼入本 repo `.github/prompts/` 的內容
3. Command Palette → `Settings Sync: Configure` → 勾選 **Prompts and Instructions**

優點是不必等每週同步、任何 repo 立即可用；缺點是只有你有，GitHub 端無效。
建議與方案 C 並用：C 保證團隊一致，A 讓你自己隨時能用。

### 方案 B：本地 clone + 指定路徑（不建議單獨依賴）

```jsonc
// VS Code User settings.json
{
  "chat.promptFilesLocations": {
    ".github/prompts": true,
    "Z:/M2_AI_CONFIG/.github/prompts": true
  }
}
```

更新只需在該 clone 執行 `git pull`（可用 `scripts/pull-latest.ps1` 掛工作排程器）。
風險見上方「已知限制」。

---

## 修改規範

1. 開分支 → 改 `.github/` 下的檔案 → 在**本 repo 內**實測 `/m2_review`、`/m2_pr`、`/m2_release`。
2. 更新 `CHANGELOG.md`，說明變更內容與對消費端的影響。
3. 破壞性變更需 bump major 並在 PR 中列出受影響的 repo。
4. 走本 repo 自己的 `/m2_review` → `/m2_pr` 流程（吃自己的狗糧就是最好的測試）。

### 撰寫 prompt file 的原則

這些規則是從實際踩過的坑歸納出來的，修改時請一併遵守：

- **第 0 節一律是「對齊 repo 慣例」**，且要給出具體指令（`git tag --sort=-v:refname`、
  `gh pr list --state merged`）。只寫「請沿用專案慣例」agent 會自己編一套。
- **明確禁止 agent 幻覺產出**：不編造未執行的測試、不臆造不存在的 API、
  「其他呼叫端」必須 `grep` 過才能寫。
- **確認節點要寫死**，並定義什麼**不算**授權（「OK」、「好」、「可以」不算合併授權）。
- **失敗時停止，不自行修補**。特別是禁止改 workflow 或加 `continue-on-error` 讓 CI 過。
- **「沒問題就說沒問題」**。不加這條，agent 會為了顯得有產出而硬湊意見，
  久了整份 review 就沒人看了。
- 每支 prompt 的骨架保持一致：
  `觸發` → `0. 對齊慣例` → `前置檢查` → `執行` → `監看` → `回報` → `硬性規則`。

### 命名慣例

- prompt file 一律使用 **`m2_` 前綴**：`m2_<動作>.prompt.md`。
- 檔名會**直接成為 slash command 名稱**，因此 `m2_pr.prompt.md` → `/m2_pr`。
- 前綴的作用：在 Copilot Chat 打 `/m2` 就能列出所有組織內部指令，
  與 `/explain`、`/fix` 等內建指令明確區隔，也避免與其他來源的 prompt 撞名。
- 允許字元：小寫 `a-z`、數字、`_`、`-`。`scripts/validate.py` 會檢查此規則，
  並對未使用 `m2_` 前綴的檔案發出警告。
- **更名等同破壞性變更**：下游 repo 同步後舊指令會消失。必須 bump major、
  寫入 `CHANGELOG.md`，並同步更新 `copilot-instructions.md` §9 的路由表
  （validator 會擋下路由表未涵蓋的 prompt）。
