# ADR-001：中央 repo 的 visibility 決策

**狀態**：✅ 已決定 —— **Public**（2026-07-23 修訂，取代先前的 Private + GitHub App）
**日期**：2026-07-23
**決策者**：<填入>
**放置路徑**：`docs/adr-001-visibility.md`

---

## 為什麼要一開始就決定

因為**改變 visibility 無法真正回溯**：

- private → public：一旦公開，全部 **git 歷史**同時公開。commit 過的任何內容
  （即使後來刪掉）都留在歷史裡，且可能已被 fork、被 archive 服務抓走、被爬蟲收錄。
  事後 `git filter-repo` 只能改自己的 repo，救不回已擴散的副本。
- public → private：技術上可行，但已存在的 fork **不會**跟著變 private。

而 visibility 直接決定了整條認證路徑（要不要 token、要不要輪替、失敗時的爆炸半徑），
先做這個決定，後面的 workflow、org secret、腳本才不用重寫。

---

## 判斷的起點：這個 repo 實際會裝什麼

不要抽象地問「內部東西能不能公開」，先看實際內容：

| 內容 | 是否含機密 | 說明 |
|---|---|---|
| `copilot-instructions.md` | 否（刻意設計） | §2 為自我探查機制，不記錄任何專案事實；§6 明訂不放客戶名稱、料號、成本 |
| `m2_*.prompt.md` | 否 | 通用 git / PR / release 流程，任何團隊都適用 |
| `templates/`、`scripts/` | 否 | 同步機制本身 |
| `README.md` | **邊緣** | 揭露 org 名稱、內部工具鏈、AI 協作流程 |

> ⚠️ **已處理**：`copilot-instructions.md` §6 原本列舉了客戶名稱。
> 那一行本身就是揭露 —— 一家 ODM 的客戶清單即使不含成本數字也是商業資訊。
> 已改為不點名的通用敘述。若決定公開，請再全文檢查一次。

**結論**：內容本身不含機密，所以這**不是資安問題，是公司政策問題**。

---

## 選項 A：Public

### Pros

| 項目 | 說明 |
|---|---|
| **零 token** | 消費端的 `github.token` 就能 checkout 公開 repo。不需要 PAT、不需要 org secret、不需要 GitHub App |
| **不會過期** | 沒有憑證，就沒有憑證到期導致全組織同步同時失效的風險 |
| **接入最簡單** | `bootstrap-repo.ps1` 直接用 `raw.githubusercontent.com` 抓範本，無需認證 |
| **權限門檻低** | 不需要 org admin 幫忙設 secret |
| **可對外分享** | 同業或社群可參考、回饋；也方便你在對外場合引用自己的作法 |
| **維護成本最低** | 少掉一整條憑證生命週期管理 |

### Cons

| 項目 | 嚴重度 | 說明 |
|---|---|---|
| **公司政策風險** | **高** | ODM 環境通常禁止未經核可將任何工作產出放上公開 GitHub，即使不含機密。這是最可能卡住的一點，且屬於合規問題而非技術問題 |
| **不可逆** | **高** | 一次誤 commit（客戶代號、內部路徑、截圖、測試資料）就永久外流。人為疏失的機率隨參與者增加而上升 |
| **組織資訊揭露** | 中 | org 名稱、內部命名慣例（`m2_` 前綴）、工具鏈、部署環境、團隊 AI 使用方式。單獨看無害，聚合起來是可用的偵查資訊 |
| **社會工程素材** | 中 | 公開你們的 PR / release 流程與確認節點，對針對性釣魚有幫助 |
| **會被納入訓練資料** | 低 | 公開內容會被各家爬取。對純規範文件而言影響有限 |
| **雜訊** | 低 | 外部 issue、PR、star 通知 |

---

## 選項 B：Private

### Pros

| 項目 | 說明 |
|---|---|
| **符合預設政策** | 不需要任何核可流程，最不會出事的選擇 |
| **可逆** | 之後想公開隨時可以（但要先審過歷史） |
| **誤 commit 有救** | 出錯時範圍限於組織內，可補救 |
| **內容可放寬** | 未來若想加入專案清單、內部連結、團隊慣例，不必自我審查 |

### Cons

| 項目 | 嚴重度 | 說明 |
|---|---|---|
| **必須有跨 repo 認證** | **高** | `github.token` 只作用於當前 repo，checkout 別的 private repo 一定要自帶憑證 |
| **PAT 過期 = 全組織同時失效** | **高** | 且失敗發生在排程任務上，通常沒人在看，可能數週後才發現規範沒同步 |
| **憑證輪替成本** | 中 | 需要記錄到期日、輪替、更新 org secret |
| **接入多一步** | 低 | `bootstrap-repo.ps1` 抓範本需要帶 token |
| **對外分享困難** | 低 | 想給同業看只能複製貼上 |

---

## 選項 C：Internal（org 由 enterprise 帳號擁有時才有）

組織全體成員可見、外部不可見。**這是折衷解，也通常是企業環境的正解。**

- Pros：可見範圍剛好等於「需要用到的人」，不需對外公開，且組織內協作零阻力。
- Cons：**仍是「非 public」，跨 repo checkout 一樣需要憑證**——
  `github.token` 無法跨 visibility 邊界存取 internal repo，即使同一個 org。
  所以認證成本與選項 B 相同。
- 前提：org 必須由 enterprise 帳號擁有。一般免費／Team 方案沒有這個選項。

---

## 認證方案對照（選了 B 或 C 才需要）

| 方案 | 會過期 | 設定成本 | 爆炸半徑 | 建議 |
|---|---|---|---|---|
| **Classic PAT** | 是 | 最低 | 全組織同時失效；權限過大（通常是帳號層級全 repo 讀取） | ❌ 不建議 |
| **Fine-grained PAT** | 是（可設較長） | 低 | 全組織同時失效；但權限可限縮到單一 repo 唯讀 | ⚠️ 可接受的過渡方案 |
| **GitHub App token** | 否（每次換發短期 token） | 中（建一次 App、裝到 org） | 無到期問題 | ✅ **private/internal 的建議解** |
| **Deploy key** | 否 | 中 | 一把 key 綁一個 repo；消費端多時難管理 | ❌ 不適合多 repo |
| **Composite action 分發** | 否 | 中 | 讓中央 repo 以「action」形式被引用，內容隨 action 下載到 runner，繞過 checkout | ⚠️ 見下方注意事項 |

### GitHub App 的 workflow 改法

若選 B / C，把 `sync-m2-common-ai.yml` 的 checkout 段換成：

```yaml
      - name: Mint GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.AI_CONFIG_APP_CLIENT_ID }}
          private-key: ${{ secrets.AI_CONFIG_APP_KEY }}
          owner: ${{ github.repository_owner }}
          repositories: ${{ steps.central.outputs.name }}

      - name: Checkout central AI config
        uses: actions/checkout@v5
        with:
          repository: ${{ vars.CENTRAL_AI_REPO }}
          token: ${{ steps.app-token.outputs.token }}
          path: .central
```

App 只需要 **Repository permissions → Contents: Read-only**，且只安裝到中央 repo
這一個 repo。權限比 PAT 小、又不會過期。

> **Composite action 方案的注意事項**：把同步邏輯包成中央 repo 裡的 composite action，
> 消費端 `uses: <ORG>/ai-config/.github/actions/sync@v1`，理論上 action 的 repo 內容會
> 被下載到 runner（`${{ github.action_path }}`），可直接複製檔案而不需要 checkout。
> 但這依賴「private repo 的 action 可被同 org 其他 repo 使用」這項設定，
> **且 GitHub 文件明確指出：private repo 內的 action 不能被 public 或 internal repo 使用**。
> 此方案未經實測，若要採用請先在一個測試 repo 驗證，不要直接鋪到全組織。

---

## 決策樹

```text
公司政策是否允許把「不含機密的內部流程文件」放上公開 GitHub？
│
├─ 不允許 / 不確定 / 需要走核可流程
│     │
│     └─► 選 Private（或 Internal，若 org 是 enterprise）
│           └─► 認證直接用 GitHub App，不要從 PAT 開始
│                 （PAT 的到期在多 repo 場景是必然會踩，不是可能）
│
└─ 允許，且我願意承擔「歷史永久公開」的不可逆性
      │
      └─► 公開前先做完檢查清單 ↓
```

### 公開前檢查清單

- [ ] `git log -p` 全歷史掃過一遍，確認無客戶名稱、料號、成本、內部 IP、憑證
- [ ] `scripts/validate.py` 的機密偵測全綠
- [ ] `README.md` 移除或抽象化 org 名稱、內部工具名、部署環境
- [ ] 確認 `m2_` 前綴等內部命名可以對外
- [ ] 取得主管／資安的書面同意
- [ ] 設定 branch protection，避免外部 PR 直接進 main
- [ ] 開啟 secret scanning 與 push protection

---

## 初步決議（已於 2026-07-23 被推翻，保留作歷史紀錄）

> ⚠️ 以下為初步決議，已被推翻。**最終決議見下一節〈最終決議：採用 Public〉。**

**初步採用 Private + GitHub App。** 理由：

1. 這個 repo 的價值完全來自組織內部使用，公開帶來的技術好處（省掉 token）
   遠小於政策風險與不可逆性。
2. GitHub App 把 private 的主要缺點（PAT 過期導致全組織靜默失效）直接消除，
   所以 private 的實際代價只剩「一次性設定成本」。
3. Private → Public 隨時可以走；反過來救不回來。**先選可逆的那一邊。**

即使選 Private，也**維持「內容假設會被公開」的紀律**——
`copilot-instructions.md` 不放專案資訊的設計繼續沿用。這讓日後真的要公開時，
只是一次 visibility 切換，不是一場歷史清洗。

---

## 最終決議：採用 Public（2026-07-23）

先前決議為 Private + GitHub App，其成立前提是
**「GitHub App 可在 org 層級設定一次、所有 repo 繼承」**。該前提在查證後不成立：

```
gh api orgs/<ORG> -q .plan.name  →  free
```

**GitHub Free 的 org 層級 secret 與 variable 無法被 private repo 讀取**
（官方文件：Using secrets in GitHub Actions）。因此 private 方案的實際成本變成
**逐 repo 設定三項憑證**，且日後輪替私鑰須逐 repo 更新。

取得公司核可可公開後，改採 Public。理由：

| 項目 | Private（Free 方案） | Public |
|---|---|---|
| GitHub App | 需建立、產生私鑰、安裝 | 不需要 |
| 消費端設定 | 逐 repo 三項（variable ×2、secret ×1） | 無 |
| `.pem` 保管 | 每接新專案都要用到 | 不存在 |
| workflow 步驟數 | 7 | 5 |
| 方案升級壓力 | 專案變多時需升 Team | 無 |

內容本身不含機密（`copilot-instructions.md` 採自我探查設計、§6 明訂不放客戶資訊），
因此公開的唯一實質成本是**不可逆性**，已由公司核可承擔。

> **重要區別**：公開的只有中央 repo 這一個。
> 各專案 repo 維持 private —— private repo 的 workflow 讀取 public repo
> 不需要任何認證。

### 隨此決議一併移除

- GitHub App `m2-ai-config-sync`（可反安裝並刪除）
- org / repo 層級的 `AI_CONFIG_APP_CLIENT_ID`、`AI_CONFIG_APP_KEY`
- 本機的 `.pem` 私鑰檔
- workflow 的 `Resolve central repo name`、`Mint GitHub App token` 兩個步驟

### 隨此決議新增的紀律

- repo 開啟 secret scanning + push protection（公開 repo 免費）
- `main` 設 branch protection，外部 PR 不得直接合併
- `.gitignore` 保留 `*.pem`、`*.key`、`.env` 阻擋
- 任何 commit 前自問：這行內容可以被全世界看到嗎？

### 何時該重新評估

- 公司政策改變、要求收回公開 → 改 private 時**必須同時**處理認證
  （Free 方案下即逐 repo 設定，或升級 Team）。
  注意：已存在的 fork 不會隨之變 private。

---

## 待確認事項

已隨最終決議解決，保留作紀錄：

- 公司對公開 GitHub 的政策、核可流程 → **已取得核可**，故採 Public。
- org 是否為 enterprise 帳號、誰可安裝 GitHub App → 因不再採 Private/Internal，
  已不適用。
