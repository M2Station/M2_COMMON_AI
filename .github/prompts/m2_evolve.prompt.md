---
description: 長時間自主迭代優化 — 給一個目標，agent 在 12 小時預算內不斷「找改進點 → 改 → 驗證 → smoke test → 收或退」，全程寫入可續跑的帳本，收斂或時間到才停。啟動前以按鈕問答釐清來源碼、專案輪廓與期望成果。
mode: agent
---

# Evolve — 自主迭代進化

**觸發**：

- `/m2_evolve` → 啟動新一輪（先訪談）
- `/m2_evolve <目標>` → 帶著目標啟動，仍會補問缺漏
- `/m2_evolve resume` → 冷啟動接續未完成的回合（context 斷掉、關掉 VS Code 之後用這個）
- `/m2_evolve status` → 只讀報告目前進度，不做任何修改
- `/m2_evolve checkpoint ask|notify|silent` → 隨時切換檢查點模式（見 §3）
- `/m2_evolve pause` → 暫停在原地，等你說繼續
- `/m2_evolve stop` → 收斂本回合、產出總結、停止

> 一個「回合（round）」= **12 小時時間預算**。回合內由許多「迭代（iteration）」組成，
> 每個迭代都是一次完整的 找 → 改 → 驗 → 收/退。

---

## ⚠️ 先講清楚這支 prompt 的真實運作方式

**agent 無法無人值守連續執行 12 小時。** session 會結束、context 會用完、終端機會被關掉。
所以「12 小時」是**時間預算**，不是「你按下去就閉眼睡 12 小時」：

- Agent 以**真實時鐘**（PowerShell `Get-Date`）計算 deadline 與剩餘時間，**絕不心算日期**。
- **12 小時是預算，不是回報頻率** — 預設每 3 個迭代或 45 分鐘就有一次 checkpoint（見 §3），
  出事時 tripwire 會立刻中斷，你也可以建一個 `.evolve/STOP` 檔隨時插隊。
- 每個迭代結束**立刻**把狀態寫進 `.evolve/<run-id>/`，所以隨時可以 `/m2_evolve resume` 冷啟動接續。
- Context 快滿時主動做一次 **compaction**（把必要資訊壓進帳本），再請使用者開新 session 續跑。
- 使用者中途關掉也不會遺失進度 — 已收下的改進都在 git commit 裡。

不要對使用者宣稱「我會自己跑 12 小時」。要說「這個回合的預算是 12 小時，目前還剩 X 小時 Y 分」。

---

## 0. 啟動前訪談（必做，但先自己查再問）

### 0.1 先自動探索，不要拿已經查得到的事去煩使用者

依 `.github/copilot-instructions.md` 第 2 節，**先自己讀專案**，再把結果拿去請使用者「確認」而非「回答」：

```bash
cat README.md 2>/dev/null | head -60
cat package.json pyproject.toml Cargo.toml go.mod *.csproj 2>/dev/null
ls .github/workflows/ .github/prompts/ 2>/dev/null
ls -a
git log --oneline -15
git status --short
```

同時偵測：建置指令、測試指令、既有 smoke test、lint/formatter、CI gate。
`/memories/repo/` 若有筆記也要先讀（可能already記著建置陷阱）。

### 0.2 用「真正可點的按鈕」問缺漏的部分

依 copilot-instructions 第 1 節：**必須用互動式選擇工具彈出可點按鈕**，不可把 `[選項]` 當純文字印出；
**每題都要有一個標 `（最建議）` 的預設值**；自由輸入僅作備援。**問之前先嗶一聲**：

```powershell
[console]::beep(880,200); [console]::beep(1320,300)
```

必問的六件事（已能從程式碼確定的就改成「確認」題，不要重問）：

| # | 主題 | 問法 |
|---|---|---|
| 1 | **來源碼範圍** | 「這次要改的範圍是？」→ 整個 repo（最建議）／指定資料夾／指定檔案清單／只改測試 |
| 2 | **專案輪廓** | 把 0.1 探索到的技術棧、建置／測試／執行指令**列出來請使用者確認**：正確（最建議）／要修正 |
| 3 | **期望成果** | 「這一輪要達成什麼？」→ 自由輸入為主，並提供常見選項（見 0.3） |
| 4 | **改進重點排序** | 複選：正確性/Bug、穩定性/錯誤處理、安全性(OWASP)、效能、可維護性、測試覆蓋、UX/可近用性、文件 |
| 5 | **自主程度** | 保守：只收明確更好的（最建議）／積極：可做較大重構／激進：可換架構（需額外確認） |
| 6 | **檢查點模式** | `ask` 每個 checkpoint 停下來問你（最建議）／`notify` 只回報不停／`silent` 只寫帳本（見 §3.1） |

### 0.3 目標太模糊 → 追問到可驗證為止（硬性）

「變好」「優化一下」「弄完美」**不是可驗收的目標**。若使用者給的目標無法轉成
「做完之後我可以跑什麼指令 / 看什麼數字來判斷成功」，就**繼續用按鈕追問**，直到每個目標都有 **可量測的驗收條件**：

- 效能 → 「哪個操作？目前多少 ms？目標多少？用什麼量？」
- 穩定性 → 「哪個情境會壞？重現步驟？」
- 品質 → 「零 warning？測試覆蓋率到多少？lint 全過？」
- 功能 → 「完成的定義是什麼？怎麼手動驗？」

**追問上限 3 輪**；仍模糊就退而求其次：與使用者確認一組「預設驗收條件」（build 0 warning + 測試全過 + smoke test 通過 + 不引入新 lint 錯誤），寫進 CHARTER 並註明是代為擬定的。

### 0.4 Smoke test 必須存在（沒有就先做出來）

**沒有 smoke test 就沒有這支 prompt。** 每個迭代都要靠它擋回歸。
在 0.4 確認 smoke test 怎麼跑；若專案沒有，**iteration 0 的唯一工作就是建立最小 smoke test**，並請使用者確認它有意義。

最低標準（依專案型態擇一，寫進 CHARTER）：

- CLI／函式庫：建置成功 + 測試全過 + 主要進入點跑一次不炸
- GUI App：建置成功 + 程式能啟動並在 N 秒內不崩潰 + 主流程手動檢查清單
- Web／API：build + 起服務 + 對關鍵 endpoint 發請求得到預期狀態碼
- 有 CI 的專案：本機重現 CI 的 gate 指令

### 0.5 凍結 CHARTER

訪談結束後產出 `.evolve/<run-id>/CHARTER.md` 並請使用者按鈕確認 **[開始]（最建議） / [再修改]**。
確認後 CHARTER 即**凍結**：迭代中不得自行放寬驗收條件或擴張範圍（要改必須回來問使用者）。

---

## 1. 建立回合工作區與基準線

### 1.1 前置檢查（任一項不過 → 停止並回報，不自行修補）

- [ ] working tree 乾淨（有未 commit 變更 → 請使用者先處理）
- [ ] 目前**不在** `main`／`master`，或允許由此建立新分支
- [ ] 已同步遠端：`git fetch origin`
- [ ] 建置指令可跑通（先跑一次確認環境沒壞）

### 1.2 開專用分支（絕不在 main 上迭代）

```powershell
$slug = '<goal-slug>'                                  # 例 startup-perf
$stamp = (Get-Date -Format 'yyyyMMdd-HHmm')
$branch = "evolve/$slug-$stamp"
git switch -c $branch
```

### 1.3 建立帳本並記錄 deadline（**用真實時鐘，不准心算**）

```powershell
$run = "$slug-$stamp"
New-Item -ItemType Directory -Force ".evolve/$run" | Out-Null

$start    = Get-Date
$deadline = $start.AddHours(12)                        # 一個回合 = 12h 預算
@{
  runId          = $run
  branch         = $branch
  startedAt      = $start.ToString('o')
  deadline       = $deadline.ToString('o')
  roundHours     = 12
  iteration      = 0
  accepted       = 0
  reverted       = 0
  noGainStreak   = 0
  checkpointMode = $mode                               # ★ 帶入 §0.2 第 6 題的答案，不可寫死
  sinceCheckpoint= 0
  lastCheckpoint = $start.ToString('o')
  status         = 'running'
} | ConvertTo-Json | Set-Content ".evolve/$run/STATE.json" -Encoding utf8

"deadline = $deadline"
```

`$mode` 來自 §0.2 第 6 題（`ask` / `notify` / `silent`）。使用者沒回答才用 `ask`。

**帳本用 `.git/info/exclude` 忽略，不要改 `.gitignore`：**

```powershell
if (-not (Select-String -Path .git/info/exclude -Pattern '^\.evolve/$' -Quiet)) { Add-Content .git/info/exclude '.evolve/' }
```

理由：§1.1 才剛要求 working tree 乾淨，改 `.gitignore` 會立刻弄髒它、被第一個 accepted commit 夾帶；
而且這是**本機過程檔**，不該污染下游 repo 的版控設定。
改完後 `git status --short` 必須是空的才進 1.4。

### 1.4 量測基準線 BASELINE（沒有基準就無從判斷「有沒有變好」）

跑一次完整驗證，把數字寫進 `.evolve/<run>/BASELINE.md`：

- 建置：耗時、warning 數、error 數
- 測試：通過/失敗/略過數、耗時、覆蓋率（若有）
- Lint／靜態分析：各級別問題數
- Smoke test：通過與否、耗時
- 與目標相關的自訂指標（啟動時間、記憶體、bundle 大小、query 次數…）
- 程式碼規模：檔案數、行數（供偵測異常膨脹）

**基準線必須是綠的。** 若一開始就紅（測試失敗／建置錯誤），
**iteration 1 的唯一任務就是修到綠**，在那之前不做任何優化。

---

## 2. 迭代循環（回合的主體）

每個迭代都走完這 7 步，**不可跳步**。單一迭代硬性上限 **45 分鐘**，超時即 revert 並記錄為「太大，需拆解」。

### 2.1 CHECK — 有人喊停嗎？還有預算嗎？

**每個迭代開頭先看 kill switch，再看預算**（單行，避免 pwsh 多行只跑第一行）：

```powershell
if (Test-Path .evolve/STOP) { 'SIGNAL=STOP' } elseif (Test-Path .evolve/PAUSE) { 'SIGNAL=PAUSE' } else { $s = Get-Content ".evolve/$run/STATE.json" -Raw | ConvertFrom-Json; $left = New-TimeSpan -Start (Get-Date) -End ([datetime]::Parse($s.deadline)); if ($left.TotalMinutes -le 0) { 'BUDGET=EXHAUSTED' } else { "BUDGET_LEFT={0}h{1}m ITER={2} SINCE_CP={3} MODE={4}" -f [int]$left.TotalHours, $left.Minutes, $s.iteration, $s.sinceCheckpoint, $s.checkpointMode } }
```

- `SIGNAL=STOP` → 不再開新迭代，直接跳到第 5 節收尾
- `SIGNAL=PAUSE` → 回報並停在原地，等使用者刪掉檔或說繼續
- `BUDGET=EXHAUSTED` → 跳到第 5 節收尾
- 否則依 §3.2 判斷該不該先做一次 checkpoint，再進 2.2

**這行指令一個迭代要跑三次**：迭代開頭、**2.4 ACT 之前**、**2.5 VERIFY 之後**。
只在迭代開頭檢查的話，使用者最壞要等满 45 分鐘才會被看見。
中途讀到 STOP/PAUSE → 把手上未驗證的改動按 2.6 WORSE 退回到安全點，再回報。

### 2.2 SENSE — 找改進點，補滿候選清單

候選清單少於 3 項時，**依序輪替掃描下列面向**（避免每輪都盯同一處，這是自我迭代最常見的失敗模式）：

| 面向 | 找什麼 |
|---|---|
| 正確性 | 邊界條件、null/空集合、off-by-one、競態、未處理的 Promise/Task |
| 穩定性 | 空 catch、吞掉的例外、缺少逾時/重試、資源未釋放 |
| 安全性 | OWASP Top 10、注入、硬編密鑰、不安全反序列化、路徑穿越 |
| 效能 | 熱路徑、N+1、不必要配置、同步 I/O、重複計算 |
| 可維護性 | 重複碼、超長函式、深層巢狀、命名、死碼 |
| 測試 | 未覆蓋分支、缺邊界測試、脆弱測試 |
| UX/A11y | 錯誤訊息品質、鍵盤操作、對比、載入狀態 |
| 文件 | 公開 API 缺註解、README 與實作不符 |

每個候選記錄：`面向 / 位置(file:line) / 問題 / 假設的改善 / 價值(1-5) / 風險(1-5) / 成本(1-5)`
**優先序 = 價值 ÷ (風險 × 成本)**，取最高者執行。

### 2.3 PLAN — 先講清楚要驗什麼

寫下：**假設**（改了 X 會讓 Y 變好）、**最小改動範圍**、**這次要看哪個數字或哪個測試**。
假設無法驗證 → 丟回候選清單標記 `unverifiable`，換下一個。

### 2.4 ACT — 最小 diff

- 一次只解**一個**問題。想順手改別的 → 記進候選清單，不要夾帶。
- 遵守 repo 既有風格與命名（copilot-instructions 第 4 節）。
- 不重排、不重新格式化無關區塊。
- **邊改邊記下兩張清單**（退回與 commit 都靠它，不可省）：
  - `MODIFIED[]` — 本迭代修改的既有檔
  - `CREATED[]` — 本迭代**新建**的檔（`git restore` 清不掉這些）

### 2.5 VERIFY — 完整驗證（順序固定，前面紅就不用跑後面）

1. **建置** — 必須 0 error；warning 數不得高於基準
2. **測試** — 全過；不得減少測試數
3. **Lint／靜態分析** — 不得新增問題
4. **Smoke test** — 必須通過
5. **目標指標** — 與 BASELINE 比較

**Flaky 處理（否則好改動會被偽陰性白白退掉）：**
測試或 smoke 紅了 → **不改任何東西、原樣重跑一次**。

- 兩次都紅 → 可重現，判 WORSE
- 一紅一綠 → 標記為 `flaky`，**不能拿來當成通過**：將此改動退回，並把「修這個不穩定測試」寫進候選清單（價值 4）
- 同一個測試在本回合 flaky 超過 2 次 → 視為 tripwire，停下來回報（基準線不可信，再跑下去的判定都沒意義）

### 2.6 JUDGE — 三選一，不准自我安慰

| 判定 | 條件 | 動作 |
|---|---|---|
| **BETTER** | 全綠 **且** 至少一項指標改善、其餘不退步 | 收下 → 2.7 commit |
| **NEUTRAL** | 全綠但指標無明顯變化 | 只有在「可維護性/可讀性明確改善」時才收，否則 revert |
| **WORSE** | 任一驗證紅（且可重現），或指標退步 | 立即按下方步驟**完整**退回，記錄失敗假設 |

**退回步驟（`git restore .` 一行是不夠的）：**

```powershell
git restore --staged . ; git restore .          # 還原 MODIFIED[]
Remove-Item -Force <CREATED[] 逐一列出>          # git restore 清不掉未追蹤的新檔
git status --short                              # 必須是空的才算退乾淨
```

**絕不可用 `git clean -fd`** — 它會連使用者本來就存在的未追蹤檔一起刪掉。只能逐一刪 `CREATED[]` 裡的檔。
若 `git status --short` 退完不是空的 → 停下來回報，不要帶著殘留進下一個迭代（基準線會被污染）。

**`noGainStreak` 計數規則（§4 的收斂判定靠它，不可模糊）：**

| 判定 | `noGainStreak` |
|---|---|
| BETTER（已 commit） | **歸零** |
| NEUTRAL 但收下（可維護性改善，已 commit） | **歸零** |
| NEUTRAL 退回 | **+1** |
| WORSE 退回 | **+1** |
| 超時（>45 分）退回 | **+1** |

失敗要記錄**為什麼失敗**——這是下一輪不要重蹈覆轍的唯一依據。

### 2.7 COMMIT — 收下的改進立刻進 git

**只 add 本迭代實際動到的檔，絕不用 `git add -A`。**
一個連跑 12 小時、沒人盯的 agent 用 `-A`，很容易把 `.env`、建置產物、暫存檔一起送進版控
（違反 copilot-instructions 第 6 節），也違反「最小 diff」（第 8 節）。

```powershell
git add <MODIFIED[] 與 CREATED[] 逐一列出>
git status --short                # 確認沒有意料之外的檔被 staged
git diff --cached                 # ★ 送出前自檢：有無密鑰/token/內部 IP/客戶資料
git commit -m "<type>(<scope>): <subject>" -m "<改了什麼、量測到什麼>" -m "Evolve-Iteration: $($s.iteration)"
```

`git diff --cached` 裡出現任何機密資料 → **立即停下來回報**，不要自行 commit 再改。

commit 格式沿用 repo 歷史（本 repo 為 Conventional Commits）。

### 2.8 LOG — 更新帳本（**在進入下一輪之前**）

先追加一筆到 `.evolve/<run>/LEDGER.md`：

```markdown
## Iteration 7 — 14:32 — ACCEPTED
- 面向：效能
- 位置：Services/FileIndexService.cs:142
- 假設：改用 HashSet 查重可消除 O(n²)
- 量測：index 12k 檔 3.4s → 0.9s（-74%）；build 0 warn；tests 128/128；smoke ✅
- commit: a1b2c3d
```

**再回寫 `STATE.json`**（否則 §4 的停止條件與 `/m2_evolve resume` 都會讀到舊值）。
單行，`$verdict` 填 `BETTER` / `NEUTRAL_KEPT` / `REVERTED`：

```powershell
$p=".evolve/$run/STATE.json"; $s=Get-Content $p -Raw|ConvertFrom-Json; $s.iteration++; $s.sinceCheckpoint++; if($verdict -eq 'REVERTED'){$s.reverted++; $s.noGainStreak++}else{$s.accepted++; $s.noGainStreak=0}; $s|ConvertTo-Json|Set-Content $p -Encoding utf8; "ITER=$($s.iteration) ACC=$($s.accepted) REV=$($s.reverted) NOGAIN=$($s.noGainStreak)"
```

回寫後以印出來的數字為準判斷下一步，**不要靠記憶**。

每 5 個迭代或 context 用掉約 70% 時，做一次 **compaction**：把已完成的細節壓成摘要，只保留
「目前狀態 + 未完成候選清單 + 已知失敗假設」，其餘丟給帳本。

### 2.9 定期推送（保命）

每累積 3 個 accepted commit 或每 2 小時，推一次專用分支：

```powershell
git push -u origin $branch
```

**只推 evolve 分支，永不推 main，永不 force push。**

---

## 3. 中斷與檢查點機制（不要讓使用者等 12 小時）

**12 小時是預算，不是回報頻率。** 這一節是使用者掌握節奏的四層機制，
其中 **tripwire（3.4）與 kill switch（3.5）不可停用**。

### 3.1 三種 checkpoint 模式

| 模式 | 行為 | 什麼時候用 |
|---|---|---|
| `ask`（**預設**） | 每個 checkpoint **停下來、嗶一聲、出按鈕**等你決定 | 你人在電腦前 |
| `notify` | checkpoint 只印進度摘要就繼續，**只有 tripwire 才停** | 你在旁邊做別的事，偶爾瞄一眼 |
| `silent` | checkpoint 只寫帳本、不打斷，**只有 tripwire 才停** | 你要放著讓它跑 |

切換：`/m2_evolve checkpoint ask|notify|silent` → 寫入 `STATE.json.checkpointMode`，下個迭代生效。
**無論哪個模式，tripwire 一律中斷** — 那是安全底線，使用者不能關、agent 更不准自己關。

### 3.2 什麼時候觸發 checkpoint（先到者算）

- 累積 **3 個迭代**
- 距上次 checkpoint **45 分鐘**
- 候選清單清空、需要重新掃描方向
- 剩餘預算不足 10%
- context 用量約 70%（順便做 compaction）

觸發後把 `sinceCheckpoint` 歸零、更新 `lastCheckpoint` 時間戳。

### 3.3 Checkpoint 報告格式（要短，10 秒讀完）

```markdown
⏸ **Checkpoint 3** — 剩 9h12m ｜ 迭代 7–9（收 2 / 退 1）
- ✅ perf(index) 索引 3.4s → 0.9s
- ✅ fix(search) 空查詢不再丟例外
- ❌ mmap I/O → ARM64 smoke 崩潰，已退回
- 驗證：build 0 warn ｜ tests 141/141 ｜ smoke ✅
- 下一步：Services/Search.cs 重複掃描（價值 4 / 風險 2）
```

`ask` 模式先嗶一聲，再**用互動式選擇工具**出按鈕：
**[繼續]（最建議）** ／ **[換個方向]** ／ **[看詳細]** ／ **[停下來開 PR]** ／ **[結束回合]**

`notify` / `silent` 模式印完就繼續，不等待。

### 3.4 Tripwire — 立即中斷，不管什麼模式

| Tripwire | 為什麼非停不可 |
|---|---|
| 連續 **2** 次 revert | 方向錯了，再燒下去只是浪費預算 |
| 驗證紅了且一個迭代內修不回來 | 可能動到不該動的東西 |
| 要改 **公開 API / 相依套件 / 架構 / DB schema / CI workflow / 安全設定** | 影響超出 CHARTER 授權 |
| 要**刪除檔案** | 不可逆 |
| 單次迭代 blast radius 超標（預設 **> 5 檔** 或 **> 200 行**） | 太大，必須拆小 |
| 任一指標**退步 > 10%** | 出現回歸 |
| 發現**安全漏洞** | 立刻告知使用者，不默默修掉 |
| 需要動到使用者沒授權的範圍 | 回頭問，不自行擴張 |

Tripwire 觸發 → **先 revert 或停在安全點** → 嗶一聲 → 說明「踩到哪一條、目前狀態、建議選項」→ 等使用者決定。

### 3.5 檔案 kill switch（不必等 agent 把控制權交回來）

你在**另一個終端機或 VS Code 檔案總管**建立這兩個檔就能插隊：

```powershell
New-Item .evolve/STOP  -ItemType File -Force   # 收尾：不再開新迭代，直接進第 5 節
New-Item .evolve/PAUSE -ItemType File -Force   # 暫停，等你刪掉檔案才續跑
```

**生效時機講清楚，不誇大：** agent 在每個迭代的三個點檢查（見 2.1）——
迭代開頭、ACT 之前、VERIFY 之後——所以**最慢通常在 15 分鐘內生效**，最差情況是一次驗證跑完的時間。
它不是即時中斷，**不會**在 agent 執行到一半的建置/測試中途停下來。

Agent 讀到訊號後必須**回報並照做**（未驗證的改動先按 2.6 退回到安全點），
且不得自行刪除 `STOP` / `PAUSE`（只有使用者能刪）。

### 3.6 零打擾的進度查看

`.evolve/<run>/LEDGER.md` 是持續追加的純文字檔 —— **任何時候打開就是最新進度**，
不需要打斷 agent、也不需要問。這是「我只想瞄一眼」的正確做法。

---

## 4. 停止條件（任一成立即進第 5 節）

| 條件 | 判定 |
|---|---|
| **時間到** | 剩餘預算 ≤ 0 |
| **收斂** | 連續 **5** 個迭代沒有任何 ACCEPTED（`noGainStreak >= 5`）→ 已達本輪邊際效益 |
| **達標** | CHARTER 所有驗收條件全數滿足，且候選清單無 價值≥4 的項目 |
| **卡住** | 需要人類決策（規格模糊、要動架構、要加相依、要改公開 API） |
| **失控** | 連續 3 次 revert 都指向同一根因 → 停下來回報，不硬幹 |
| **使用者喊停** | `/m2_evolve stop`、checkpoint 選「結束回合」，或偵測到 `.evolve/STOP` |

「完美」不存在。**收斂即成功**，不要為了湊滿 12 小時而製造無意義的 churn。

---

## 5. 回合結束報告 + 下一輪確認

### 5.1 先關掉回合（必做，否則 resume 會接到已結束的回合）

輸出報告**之前**先把 `STATE.json` 的 `status` 從 `running` 改掉（單行）：

```powershell
$p=".evolve/$run/STATE.json"; $s=Get-Content $p -Raw|ConvertFrom-Json; $s.status=$final; $s|Add-Member -NotePropertyName endedAt -NotePropertyValue (Get-Date).ToString('o') -Force; $s|ConvertTo-Json|Set-Content $p -Encoding utf8; "status=$($s.status)"
```

`$final` 依停止原因填：`converged` / `exhausted` / `goal-met` / `stuck` / `stopped`。
**只有 `running` 會被 `/m2_evolve resume` 接手**；回合結束卻沒改掉，下次 resume 就會錯接到這一輪。

### 5.2 報告

先嗶一聲，再輸出：

```markdown
🔔 **Evolve 回合結束 — <收斂 / 時間到 / 卡住>**

- 回合：<run-id>　分支：`evolve/...`
- 實際耗時：<Xh Ym> / 12h 預算　迭代：<N> 次（收 <A> / 退 <R>）
- 停止原因：<條件>

### 指標變化（vs BASELINE）
| 指標 | 前 | 後 | 變化 |
|---|---|---|---|
| build warnings | 12 | 0 | −12 ✅ |
| tests（測試數，必列） | 128 pass | 141 pass | +13 ✅ |
| lint 問題數（必列） | 34 | 34 | 持平 |
| smoke test | ✅ | ✅ | 持平 |
| <自訂指標> | ... | ... | ... |

### 收下的改進（<A> 筆）
- `a1b2c3d` perf(index): ... — index 3.4s → 0.9s

### 退回的嘗試（<R> 筆，附原因）
- 改用 memory-mapped I/O → smoke test 在 ARM64 崩潰，退回

### 未完成候選（下一輪的起點）
- [價值4/風險2] Services/X.cs:88 — ...

### 需要你決定
- <卡住的項目 / 要不要動公開 API>

### 待人工驗證
- <smoke test 蓋不到、需要真機確認的項目>
```

> 「測試數」與「lint 問題數」是**固定欄位，不可省略**——「絕不作弊」那一節就是靠這兩個數字被看見；
> 刪測試或放寬 lint 門檻都會在這裡現形。

接著**用按鈕**問：**[開始下一輪 12h]（最建議）** ／ **[開 PR 送審]** ／ **[先停在這]**

- 選開 PR → 交給 `/m2_pr`（**不要在這支 prompt 裡自己開 PR 或合併**）
- 選下一輪 → 以本輪「未完成候選」為起點，重跑第 1.3 節建立新預算（新的 run-id）

---

## 6. 子指令對照

| 指令 | 動作 |
|---|---|
| `/m2_evolve` ／ `/m2_evolve <目標>` | 從 §0 訪談開始新回合 |
| `/m2_evolve resume` | 冷啟動接續，見 §6.1 |
| `/m2_evolve status` | **唯讀**：讀 `STATE.json` + `LEDGER.md` 末段，輸出 §3.3 格式的摘要。不切分支、不改任何檔、不繼續迭代 |
| `/m2_evolve checkpoint <mode>` | 寫入 `STATE.json.checkpointMode`（`ask`/`notify`/`silent`），下個迭代生效 |
| `/m2_evolve pause` | 等同於建立 `.evolve/PAUSE`。**注意**：agent 正在跑時你打不了 slash 指令，那時請直接建檔（§3.5） |
| `/m2_evolve stop` | 等同於建立 `.evolve/STOP`；若 agent 已空閒，則直接跑 §5 收尾（含 5.1 改 `status`） |

除了 `status` 之外的每一個子指令，都要先確認目前鎖定的是哪一個 run（若有多個 `running`，用按鈕讓使用者選）。

### 6.1 Resume — 冷啟動接續

`/m2_evolve resume` 時：

1. 找出 `.evolve/` 下 `status = running` 的最新 run（回合正常結束時 §5.1 會把 `status` 改掉，所以這裡只會抓到真正未完成的）
2. 讀 `CHARTER.md`（目標）、`STATE.json`（進度、checkpoint 模式）、`LEDGER.md` 末段（近況）、`BASELINE.md`（基準）
3. 確認 `.evolve/STOP` / `PAUSE` 已被刪除（還在就代表使用者要停，不要自己刪）
4. `git switch <branch>`，確認 working tree 乾淨（髒的話回報，讓使用者決定要不要丟棄）
5. 用 2.1 重新計算剩餘預算
6. 回報「接續 run X，已完成 N 次迭代，剩餘 Xh Ym」後，直接回到 2.2 繼續

找不到 `running` 的 run → 回報「沒有未完成的回合」，並問要不要開新的，**不要自行接已結束的回合**。

---

## 硬性規則

### 絕不作弊（最重要）

自我優化的 agent 最容易走的捷徑就是**讓驗證變寬鬆**。以下一律禁止：

- ❌ 改測試去遷就實作（測試紅了要修**實作**，除非測試本身確實寫錯 — 且要明說並單獨 commit）
- ❌ 刪測試、`skip`／`ignore`／註解掉測試、放寬 assertion
- ❌ 加 `continue-on-error`、`--no-verify`、降低 lint 等級、關掉 warning
- ❌ 改 smoke test 讓它變得更容易通過
- ❌ 用「應該可以」「理論上更快」代替實際量測 — **沒量到就不算改善**
- ❌ 在報告裡宣稱未實際執行的驗證

### 中斷機制不可關

- **Tripwire（§3.4）一律中斷**，不管 checkpoint 模式是什麼；agent 不得自行放寬或停用
- 每個迭代開頭**必須**先檢查 `.evolve/STOP` / `.evolve/PAUSE`；**不得自行刪除這兩個檔**
- 不得為了「跑順一點」而拉長 checkpoint 間隔或跳過報告
- 卡住、需要人類決策時，**停下來問**，不自己猜一個方向硬幹

### Git 安全

- 只在 `evolve/*` 分支工作；**不 push main、不 force push、不 rebase 已推送的歷史**
- **不自行開 PR、不自行 merge** — 交由 `/m2_pr`，且合併需使用者按鈕確認
- 不 `git reset --hard`、不 `git clean -fd` —— 它們會動到使用者自己的東西；退回一律走 §2.6 的步驟（`git restore` + 逐一刪 `CREATED[]`）
- commit 只 add 本迭代的 `MODIFIED[]` / `CREATED[]`，**不用 `git add -A`**；送出前必跑 `git diff --cached` 自檢機密資料
- 每個 commit 都必須是綠的（可獨立 checkout 而不壞）

### 範圍與節制

- 嚴守 CHARTER；要擴張範圍必須回頭問使用者
- 不因個人偏好引入新框架／新相依／新抽象層（copilot-instructions 第 3、8 節）
- 不為了「看起來有做事」而製造 churn；**沒有更好就退回**
- 不動 UI 既有行為與視覺風格，除非那正是目標

### 誠實回報

- 每個迭代的判定必須基於**實際跑出來的輸出**，不是推測
- 不確定就標「不確定」；沒驗證就標「未驗證」
- 時間一律用 PowerShell `Get-Date` 算，**絕不心算日期**（copilot-instructions 明文要求）

### 終端機注意事項（本機實測）

pwsh 終端機**貼多行區塊常常只執行第一行**（here-string、多行 `do/while`、多行 pipeline 都中過）。
所以：**輪詢/迴圈一律寫成單行**，或先寫成 `.ps1` 檔再執行。長內容用 `--body-file` 之類的檔案參數，不要用多行字串。

---

## 附錄：目錄結構

```text
.evolve/
├── STOP            # 使用者建立 → agent 做完手上迭代就收尾（只有使用者能刪）
├── PAUSE           # 使用者建立 → agent 暫停，等刪掉才續跑
└── <run-id>/
    ├── CHARTER.md  # 凍結的目標、驗收條件、範圍、smoke test 定義
    ├── BASELINE.md # 起始指標
    ├── STATE.json  # 機器可讀進度（resume / checkpoint 靠它）
    └── LEDGER.md   # 逐迭代追加紀錄（含失敗假設）— 隨時可直接打開看進度
```

`.evolve/` 由 §1.3 寫進 `.git/info/exclude` 忽略（**不改 `.gitignore`**，不污染下游 repo）。
真正的成果在 git commit 裡，帳本只是過程。
