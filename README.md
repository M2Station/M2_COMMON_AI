# M2_COMMON_AI

集中維護 GitHub Copilot 的通用規範與工作流程指令，供組織內所有 repo 共用。
在這裡改一次，各專案透過 GitHub Actions 自動同步。

本 repo 為 **public**（內容不含任何專案或客戶資訊）。
各專案 repo 維持 **private**，不受影響。

---

## 可用指令

在 VS Code 的 Copilot Chat 輸入 `/` 即可看到：

| 指令 | 用途 | 會不會改你的 code |
|---|---|---|
| `/m2_review` | 自我 code review，依 🔴 Blocker／🟡 Should fix／🔵 Nit 分級回報 | 不會（`/m2_review fix` 才會，且逐項確認） |
| `/m2_pr` | 開 PR → 每 3 秒輪詢 CI → 全過時提醒你確認合併 | 不會 |
| `/m2_next` | PR 合併後收尾：刪已合併分支、回到並更新 main、確認乾淨、備妥下一輪 | 只清理分支/切 main |
| `/m2_release` | 算版號 → bump PR → merge → tag → CI 發布 | 只改版本號 |

建議串接使用：

```text
寫完 code  →  /m2_review  →  修 Blocker  →  /m2_pr  →  你按 Confirm merge  →  /m2_next（收尾）  →（要發版才）/m2_release
```

版號規則：patch 逐一遞增，滿 9 進位到 minor。
`0.3.0 → 0.3.1`、`0.3.9 → 0.4.0`、`0.9.9 → 1.0.0`

四支指令都有「停下來等你確認」的節點。特別注意：**回覆「OK」不算合併授權**，
必須明確回 `confirm merge` 或自己按 GitHub 上的按鈕。

---

## 目錄結構

`.github/` 就是 source of truth。中央 repo 自己也吃自己的設定，
所以在這個 repo 裡開 Copilot Chat 就能直接測試四支指令。

```text
M2_COMMON_AI/
├── .github/                          ← ★ 同步出去的就是這裡
│   ├── copilot-instructions.md       ← 通用規範，每次對話都會載入
│   ├── sync-manifest.txt             ← ★ 同步清單：定義要 sync 哪些路徑
│   ├── prompts/                      ← slash 指令，打 / 才觸發
│   │   ├── m2_review.prompt.md       ← /m2_review
│   │   ├── m2_pr.prompt.md           ← /m2_pr
│   │   └── m2_release.prompt.md      ← /m2_release
│   ├── instructions/                 ← 分領域規範（applyTo glob），目前為空
│   └── workflows/
│       ├── validate.yml              ← CI：檢查格式，防止推壞
│       └── sync-m2-common-ai-reusable.yml  ← ★ 同步邏輯本體，下游用 stub 呼叫
│
├── templates/sync-m2-common-ai.yml   ← 各專案要放的同步 workflow（stub，呼叫上面的 reusable）
├── scripts/
│   ├── validate.py                   ← 本地驗證：python scripts/validate.py
│   └── bootstrap-repo.ps1            ← 一鍵把同步機制裝進某個專案
├── CHANGELOG.md                      ← 每次改規範都要更新，CI 會檢查
└── docs/adr-001-visibility.md        ← 決策記錄，日常不需要看
```

> `instructions/` 內只有 `.gitkeep`。**不要刪掉它** ——
> 同步 workflow 的 rsync 找不到來源目錄會直接失敗。

---

## 同步機制（manifest 驅動）

**pull 式**：下游 repo 的 `sync-m2-common-ai.yml` 定時（或手動）從本 repo 拉取；
「要同步哪些路徑」由本 repo 的 `.github/sync-manifest.txt` 單一決定。
之後要加範圍，**只改中央 manifest，下游 workflow 完全不用動**。

> 下游那支 `sync-m2-common-ai.yml` 只是**stub**，用 `uses:` 呼叫中央的
> `.github/workflows/sync-m2-common-ai-reusable.yml`。同步「邏輯」（步驟、action 版本、
> assignee）都住在中央 reusable，改一次全下游下次排程自動生效；stub 只留觸發時機與權限。

### 一次同步的流程

1. 下游 workflow 觸發：排程（台灣時間每天 05:00 / 17:00）或手動 `gh workflow run`。
2. checkout 公開的中央 repo（免 token），讀 `.github/sync-manifest.txt`。
3. 逐行同步，路徑相對於 `.github/`：
   - 結尾 `/` → 資料夾，`rsync --delete`（中央沒有的檔案，下游會一併刪掉）
   - 無 `/` → 單檔，`cp` 覆寫
4. 只有 manifest 列的路徑「實際有變化」才寫 `.github/M2_COMMON_AI_VERSION`（來源版本戳記，含本次變更的檔案清單）並開一個 PR；無變化就靜默結束，不開空 PR。
5. 你在下游 review、合併那個 PR，設定即生效。

安全邊界：只准同步 `.github/` 底下，擋掉絕對路徑、`..` 跳脫與 `workflows/`
（`GITHUB_TOKEN` 無法寫 `.github/workflows/`，明確擋下以免製造 rejected push）。
`validate.py` 會在中央端先把關這些。

### manifest 長怎樣

`.github/sync-manifest.txt`，每行一個路徑（相對 `.github/`），`#` 開頭與空行忽略：

```text
copilot-instructions.md
prompts/
instructions/
```

> 不支援行內註解（`路徑 # 說明`）—— 整行才會被當成路徑，`#` 只在行首才算註解。

### 新增一個同步路徑

全程只動中央：

1. 把檔案／資料夾放進本 repo 的 `.github/` 下。
2. 在 `.github/sync-manifest.txt` 加一行（資料夾結尾記得加 `/`）。
3. `python scripts/validate.py` 要綠（會驗路徑合法且真的存在）。
4. 更新 `CHANGELOG.md` → 開 PR → 合併。下次下游同步就自動帶上，**下游零改動**。

### 既有下游 repo 的一次性遷移

下游那支 workflow 檔本身**不會自動升級** —— 因為同步不碰 `.github/workflows/`（見安全邊界）。
所以每次「stub 結構升級」都要**重跑一次 bootstrap** 覆蓋那支 workflow，之後就一勞永逸：

- **manifest 版**（v1.1.0+）：把寫死路徑換成讀中央 manifest。
- **reusable stub 版**（v1.4.0+）：把整段邏輯換成 `uses:` 呼叫中央 reusable，
  日後同步邏輯改動（升 action、改 assignee 等）全部自動生效，永遠不用再碰下游。

重跑方式：

```powershell
cd <你的專案>
git switch -c chore/upgrade-sync-manifest

Invoke-WebRequest -UseBasicParsing `
  -Uri "https://raw.githubusercontent.com/M2Station/M2_COMMON_AI/main/templates/sync-m2-common-ai.yml" `
  -OutFile ".github\workflows\sync-m2-common-ai.yml"

git add .github\workflows\sync-m2-common-ai.yml
git commit -m "chore(ai): upgrade sync workflow to manifest-driven"
git push -u origin chore/upgrade-sync-manifest
gh pr create --fill
```

換過之後，未來新增路徑就永遠不用再碰這個下游。

### 什麼會自動傳播、什麼不會

| 變更 | 下游要不要動 |
|---|---|
| 改 `copilot-instructions.md`／`prompts`／`instructions` 內容 | 不用，自動同步 |
| 在 manifest 新增一條路徑 | 不用（前提：已在 manifest 版） |
| 改同步「邏輯」（加 step、升 action、改 assignee，改在中央 reusable） | 不用，下次排程自動生效 |
| 改 stub 本身（觸發時機／權限／換 pin 的 tag） | 要，重跑 bootstrap（前提：已在 reusable stub 版） |

> 為什麼是 pull 不是中央 push：pull 讓消費端零設定、免 token，下游 private 也不受影響。
> 中央 push 要保管能寫全 org 的 GitHub App key，是安全信任升級 —— 取捨見 `docs/adr-001-visibility.md`。

---

## 接入一個新專案

### 1. 放入同步 workflow

只有三個動作，建議直接手動做（不受 PowerShell execution policy 限制）：

```powershell
cd <你的專案>
git switch -c chore/add-ai-config-sync

mkdir -Force .github\workflows
Invoke-WebRequest -UseBasicParsing `
  -Uri "https://raw.githubusercontent.com/M2Station/M2_COMMON_AI/main/templates/sync-m2-common-ai.yml" `
  -OutFile ".github\workflows\sync-m2-common-ai.yml"

git add .github\workflows\sync-m2-common-ai.yml
git commit -m "chore(ai): add central Copilot config sync"
git push -u origin chore/add-ai-config-sync
gh pr create --fill
```

> 不要用 `curl`：在 Windows PowerShell 5.1 中 `curl` 是 `Invoke-WebRequest` 的別名，
> `-o` 參數會被解讀成別的東西。用 `Invoke-WebRequest -OutFile` 才可靠。

也可以用腳本（會自動建分支、開 PR）：

```powershell
<本 repo 的本地路徑>\scripts\bootstrap-repo.ps1
```

若出現 `is not digitally signed` 或 `UnauthorizedAccess`，是 execution policy 阻擋。
腳本未簽章，且放在網路磁碟（如 `Z:\`）會被視為遠端來源。處理方式：

```powershell
# 先看目前政策由哪個範圍決定
Get-ExecutionPolicy -List

# 若 MachinePolicy / UserPolicy 為 Undefined（非群組原則強制）→ 單次繞過即可
powershell -ExecutionPolicy Bypass -File "<路徑>\scripts\bootstrap-repo.ps1"

# 若為群組原則強制 → 上述方法無效，請改用上面的手動步驟
```

### 2. 允許 Actions 開 PR

這是**唯一需要的設定**。不需要 token、secret 或 variable。

```text
專案 Settings → Actions → General → Workflow permissions
→ 勾選 Allow GitHub Actions to create and approve pull requests
```

org 層級開一次可涵蓋所有 repo：
`https://github.com/organizations/M2Station/settings/actions`

### 3. 立即同步一次

```powershell
gh workflow run sync-m2-common-ai.yml
gh run watch
```

會出現一個 `chore(ai): sync Copilot config from central repo` 的 PR。
合併後，那個專案就能用三支指令了。

之後每天固定兩次（台灣時間 05:00 / 17:00）自動檢查，有變更才開同步 PR。排程失敗時會自動開 issue 通知。

---

## 修改規範

```powershell
cd <本 repo>
git switch -c feature/<描述>
# 改 .github/ 下的檔案
python scripts\validate.py          # 必須全綠
# 更新 CHANGELOG.md（CI 會檢查，沒改會被擋）
```

然後在本 repo 內實際跑一次 `/m2_review` → `/m2_pr` 驗證，再合併。

### PowerShell 腳本必須存成 UTF-8 with BOM

Windows PowerShell 5.1 在檔案**沒有 BOM** 時，會以系統 ANSI codepage（繁中為 cp950）
解析 `.ps1`。cp950 的 trail byte 範圍含 `0x40`–`0x7E`，UTF-8 中文位元組會被錯誤配對，
吃掉後面的引號或換行 —— 結果是**中文變亂碼，而且敘述被當成字串、變數指派被跳過**，
出現像 `Cannot bind argument to parameter 'Path' because it is null` 這種與中文毫無關聯的錯誤。

編輯 `.ps1` 後請確認存成 **UTF-8 with BOM**（VS Code 右下角編碼欄可切換）。
`validate.py` 會擋下沒有 BOM 的 `.ps1`。

### validate.py 會檢查什麼

- prompt 檔名格式（`m2_<動作>.prompt.md`，小寫）
- YAML frontmatter 存在且含 `description`
- `instructions/*.md` 含 `applyTo`
- **`copilot-instructions.md` 的路由表是否涵蓋所有 prompt**
- 常見憑證樣式（token、私鑰、hardcoded password）
- `scripts/*.ps1` 是否為 UTF-8 with BOM

第四項最容易漏：新增 prompt 但忘記加進路由表時，不會報錯，
只會安靜地讓 Copilot 永遠不知道那支指令存在。

### 命名慣例

- prompt 一律 `m2_` 前綴。檔名**直接就是**指令名稱，`m2_pr.prompt.md` → `/m2_pr`。
- 好處：打 `/m2` 就能列出所有內部指令，與 `/explain`、`/fix` 等內建指令區隔。
- **更名等同破壞性變更** —— 下游同步後舊指令會消失。
  須 bump major、更新 CHANGELOG、同步改路由表。

---

## 三種檔案的差別

維護時最需要搞清楚的一件事，是它們的**載入時機**：

| 檔案 | 何時載入 | 放什麼 |
|---|---|---|
| `copilot-instructions.md` | **每次對話都載入** | 語言、命名、Git、安全等通用規範。以及 §9 的指令路由表 |
| `instructions/*.md` | 依 `applyTo` 自動匹配當前檔案 | 分領域規範（前端／後端／測試） |
| `prompts/*.prompt.md` | **只有打 `/` 才載入** | 多步驟流程 |

所以 40 行的發版流程放 prompt file，不放 `copilot-instructions.md` ——
否則你只是問「這個函式做什麼」時也會被塞進去，稀釋掉真正重要的規範。

反過來，**路由表必須放在 always-on 的檔案裡**，Copilot 才會「總是知道」
有這些指令存在，在你說「發版」時去讀對應檔案。

---

## 注意事項

### 同步是覆蓋式的

同步範圍與流程見上方〈同步機制〉。重點在它**會覆蓋、資料夾還會 `rsync --delete`**：

- **專案特定內容不要寫進被同步的路徑**（目前 `copilot-instructions.md`、`prompts/`、`instructions/`），下次同步就沒了。
- 專案專屬規範請放 `.github/<project>-instructions/`（不列進 manifest 就不會被同步）。

### 通用規範不記錄專案資訊

`copilot-instructions.md` §2 是「自我探查」設計：不寫專案名稱、技術堆疊、目錄結構，
而是規定 Copilot 自己去讀 `README.md`、`package.json`、`.github/workflows/`、`git log`
推導。這是它能原封不動用在任何 repo 的原因。

### 本 repo 公開

- **不得放入**客戶名稱、專案代號、料號、成本、內部 IP、憑證、內部路徑。
- 建議開啟 secret scanning + push protection，`main` 設 branch protection。
- git 歷史是永久的：誤 commit 後即使刪除，內容仍留在歷史與可能的 fork 裡。

### Copilot 的兩個行為

- prompt files **不影響** inline 自動補完（灰字建議），那是另一套系統。
- Copilot 做 **PR code review 時讀的是 base branch** 的 `copilot-instructions.md`。
  新規範要 merge 進 `main` 後才對 review 生效。
