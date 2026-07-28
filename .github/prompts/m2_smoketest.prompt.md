---
description: App smoke test 全流程 — 先探索既有 smoketest_script/，沒有就建立、有就依新功能補測試，接著 review/refine 腳本並實際執行，最後輸出量化報告與明確的 bug／改善清單。涵蓋安裝、執行、設定、使用者體驗、效能五個面向。
mode: agent
---

# Smoke Test — 建立、精修、執行、量化

**觸發**：

- `/m2_smoketest` → 完整流程（探索 → 建立／補強 → review/refine → 執行 → 報告）
- `/m2_smoketest scan` → **唯讀**：只做探索與覆蓋缺口分析，不改檔、不執行
- `/m2_smoketest init` → 只建立／補強腳本，**不執行**
- `/m2_smoketest review` → 只審既有腳本，**不改、不跑**
- `/m2_smoketest run` → 只執行既有腳本並出報告，**不改腳本**
- `/m2_smoketest <路徑>` → 指定腳本或目錄（可與上面子指令並用）

> 用途：在 `/m2_pr` 之前、或 `/m2_release` 之前，確認這個 App
> **裝得起來、跑得起來、設定改得動、用起來沒壞、效能沒退步**。
>
> 這支 prompt **只驗證與回報，不修 App 的 bug** —— 發現問題交還使用者或 `/m2_review`。
> 它只會修改 `smoketest_script/` 底下的東西，而且逐項確認才改。

---

## 0. 先對齊專案規範（必做，不可略過）

依 `.github/copilot-instructions.md` 第 2 節，**先自己讀專案**，不要拿查得到的事去問使用者：

```bash
cat .github/copilot-instructions.md 2>/dev/null     # 專案編碼規範
cat README.md 2>/dev/null | head -60                # 用途、啟動方式
cat package.json pyproject.toml *.csproj Cargo.toml go.mod 2>/dev/null   # 技術棧、scripts
ls .github/workflows/ 2>/dev/null                   # CI 是否已有驗證步驟
git log --oneline -15
```

- 技術棧、建置指令、產物路徑、**安裝形態**（installer／portable／npm／pip／docker／服務）
  一律**從實際檔案判斷**；判斷不出來就用按鈕問，**不要猜**。
- `/memories/repo/` 若有筆記先讀（可能已記著建置或環境陷阱）。
- 專案已有測試框架（pytest／vitest／xunit／playwright）→ **優先沿用**，
  不為了 smoke test 引入新框架（copilot-instructions 第 3 節）。

---

## 1. 探索既有 smoke test（第一步，不可略過）

**約定目錄：`smoketest_script/`**（本組織的標準位置）。先看它，再掃其他常見位置：

```powershell
Test-Path smoketest_script
Get-ChildItem -Recurse smoketest_script -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime
```

```powershell
Get-ChildItem -Recurse -File -Filter *smoke* -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|bin|obj)\\' } | Select-Object -First 50 FullName
Select-String -Path package.json,.github/workflows/*.yml -Pattern 'smoke' -ErrorAction SilentlyContinue
```

判定三選一，**報告時要明說是哪一種**：

| 狀態 | 判定依據 | 下一步 |
|---|---|---|
| **A. 不存在** | 全 repo 找不到任何 smoke test | → §2 建立 |
| **B. 已存在** | `smoketest_script/` 內有可執行的腳本 | → §3 缺口分析 → 補測試 |
| **C. 存在但在別處** | 例如 `tests/smoke.spec.ts`、CI 內嵌步驟、`scripts/verify.ps1` | **不另起爐灶** |

**C 一定要問，不可自作主張**：beep 後用互動式選擇工具彈按鈕 ——
**[沿用既有位置]（最建議）／[遷入 smoketest_script/]／[兩邊都留，我自己決定]**。
重複造一套 smoke test 是最糟的結果：兩套都會慢慢腐爛。

找不到就說找不到，**不要假裝掃過**。掃過哪些路徑要列出來。

---

## 2. 沒有 → 建立最小可用的 smoke test

### 2.1 先確認能不能建（缺一不可）

| 必要資訊 | 用途 |
|---|---|
| 建置指令 + 產物路徑 | INS 案例的輸入 |
| App 啟動方式（exe／CLI／服務／URL） | RUN 案例的輸入 |
| 安裝形態（installer／portable／套件管理器） | INS 案例怎麼寫 |
| 設定檔位置與格式 | CFG 案例的輸入 |
| 最在意的效能指標 | PERF 案例的門檻 |

查不到的**用按鈕問**（先 beep）。
**絕不自己編一個假的路徑寫進腳本** —— 那種腳本第一次跑就爆，比沒有還糟。

### 2.2 目錄結構（約定）

```text
smoketest_script/
├── run-smoketest.ps1        # 唯一進入點
├── cases/
│   ├── install.ps1          # INS
│   ├── runtime.ps1          # RUN
│   ├── settings.ps1         # CFG
│   ├── ux.ps1               # UX
│   └── perf.ps1             # PERF
├── lib/
│   ├── harness.ps1          # 案例註冊、計時、逾時、結果收集、JSON 輸出
│   └── env.ps1              # 沙箱建立／還原（§6.1 的安全要求）
├── baseline.json            # 效能基準（第一次跑自動產生）
├── manual-checklist.md      # 無法自動化的人工檢查項
├── .gitignore               # 內容只有 `results/`（見下方）
└── results/
    └── <yyyyMMdd-HHmmss>/
        ├── result.json      # ★ 機器可讀，報告一律以它為準
        ├── report.md
        └── logs/
```

`results/` 為每次執行的產物，不要推進版控。**在 `smoketest_script/.gitignore` 寫入 `results/`** 即可
—— 巢狀 `.gitignore` 對子目錄有效，且位於本 prompt 允許改動的範圍內，會跟腳本一起進版控。
**不要動 repo 根目錄的 `.gitignore`**（那會在使用者 repo 留下沒被要求的變更，也牵拖本檔硬性規則）。

### 2.3 語言選擇

- **預設 PowerShell `.ps1`** —— Windows 桌面 App、有 installer、要碰登錄檔／服務／程序時最順。
- **統計、量測分析、產報表可用 Python `.py`**，兩者混用完全可以：
  `run-smoketest.ps1` 當進入點，`analyze.py` 吃 `result.json` 算中位數與離散度。
- 跨平台或前端專案 → 跟著專案既有 runner 走（npm script／pytest／playwright）。
- **`.ps1` 只要含中文就必須存成 UTF-8 with BOM** ——
  否則 Windows PowerShell 5.1 會以 cp950 解析，吃掉引號與換行，造成語法錯誤。

### 2.4 harness 的輸出契約（硬性）

報告**不能靠 agent 讀 stdout 猜**，一定要有機器可讀輸出。`result.json` 欄位固定：

```json
{
  "app": "M2_APEX",
  "version": "0.4.1",
  "startedAt": "2026-07-28T10:00:00+08:00",
  "durationSec": 96.4,
  "environment": { "os": "Windows 11 26100", "arch": "x64", "runner": "local", "installMode": "portable" },
  "summary": { "total": 45, "passed": 42, "failed": 2, "flaky": 0, "skipped": 1, "manual": 6 },
  "cases": [
    {
      "id": "SMK-INS-001",
      "area": "install",
      "title": "portable 解壓後可直接執行",
      "status": "pass",
      "durationMs": 1840,
      "expected": "exit code 0",
      "actual": "exit code 0",
      "message": "",
      "evidence": "logs/ins-001.log"
    }
  ],
  "metrics": [
    {
      "name": "cold_start_ms",
      "value": 1420,
      "unit": "ms",
      "samples": [1402, 1420, 1455],
      "baseline": 1380,
      "threshold": 2000,
      "direction": "lower-is-better",
      "verdict": "pass"
    }
  ]
}
```

- `status` ∈ `pass`／`fail`／`flaky`／`skip`／`manual`
  —— **`manual`、`skip`、`flaky` 一律不算通過**。
- 退出碼：`0` 全過｜`1` 有 `fail`｜`2` **腳本或環境本身有問題**
  （跟「測試失敗」分開，否則 CI 紅了看不出是 App 壞還是測試壞）。
- 每個案例都要有**逾時**，逾時記成 `fail` 且 `message` 標 `timeout`，不可無限等。

---

## 3. 已存在 → 依新功能做覆蓋缺口分析

### 3.1 先算出「新功能」的實際範圍（不憑印象）

```powershell
git log -1 --format=%H -- smoketest_script     # 腳本最後一次更新的 commit
git diff <該 commit>..HEAD --stat
git log <該 commit>..HEAD --oneline
```

查不到（腳本剛建、或從未 commit）→ 退而用**最近一個 tag** 或 `main...HEAD`，
並在報告中**明說用的是哪個基準**，不要含糊帶過。

### 3.2 從 diff 抽出「需要被 smoke 的東西」

| diff 裡的訊號 | 要補什麼測試 |
|---|---|
| 新的 CLI 參數／子指令 | RUN：帶該參數跑一次不炸、`--help` 有列出 |
| 新的設定項 | CFG：預設值正確、改了會生效、非法值被擋、舊設定檔可升級 |
| 新的視窗／頁面／流程 | UX：能開啟、關鍵元素存在、能返回；無法自動化 → 進 manual checklist |
| 安裝相關（installer、打包、檔名、簽章、自動更新） | INS：安裝／靜默安裝／升級覆蓋／解除安裝／捷徑與關聯 |
| 新相依套件、runtime 版本變更 | INS：**乾淨環境**下可啟動（缺 runtime 會不會無聲失敗） |
| 熱路徑、演算法、I/O、批次大小變更 | PERF：對應指標 + 門檻 |
| 資料格式／schema 變更 | CFG：舊檔可讀（向後相容）、新檔寫出後可再讀回 |
| **修過的 bug** | 一條回歸案例 —— **bug 修了沒測試 = 一定會再犯** |
| 移除的功能 | 刪掉對應案例（不是註解掉），並在報告說明刪了什麼 |

### 3.3 先輸出缺口表給人看，再動手

```markdown
| 新功能／變更 | 位置 | 現有覆蓋 | 缺口 | 建議新增 |
|---|---|---|---|---|
| 新增 `--export-xlsx` | src/cli.js:88 | 無 | 完全未覆蓋 | SMK-RUN-012：匯出後檔案存在且可開啟 |
| 設定新增 `autoBackup` | src/config.js:34 | 只驗了預設值 | 非法值未驗 | SMK-CFG-009：填非布林值要被擋 |
```

- **只加真的有價值的案例**，不為了湊數量而加 —— smoke test 變慢、變脆，就沒人跑了。
- 動手前 beep + 按鈕確認要加哪些：**[全部加]（最建議）／[只加我勾的]／[先不加]**。

---

## 4. 五大覆蓋面與案例規範

案例 ID：`SMK-<AREA>-<NNN>`，`AREA` ∈ `INS`｜`RUN`｜`CFG`｜`UX`｜`PERF`。
**ID 一旦發出去就不重用**（刪掉的案例編號不要回收，否則歷史報告會對不上）。

### 4.1 安裝 INS

- 建置產物存在且完整：檔案數、大小合理、**版本號正確**（最常見的低級錯就是忘了 bump）
- Portable：解壓即可執行，不依賴系統安裝
- Installer：靜默安裝成功、目標路徑正確、退出碼正確
- **升級覆蓋安裝**：舊設定與使用者資料保留
- 解除安裝：檔案清乾淨、使用者資料依規則保留或移除、無殘留服務／排程
- **乾淨環境**：缺少 runtime 時錯誤訊息看得懂（不是無聲失敗或跳系統錯誤框）
- 簽章／完整性（若專案有簽）

### 4.2 執行 RUN

- 啟動不崩潰，**N 秒內**進入可用狀態（N 寫在腳本裡，不是憑感覺）
- 主流程 happy path 完整走一次
- `--version` / `--help` 正常且版本號與產物一致
- 正常關閉：退出碼 0、**無殘留 process**、無 lock 檔殘留
- 無 unhandled exception：掃 App log／stderr／Windows Event Log
- 重複啟動的行為（single instance／多開）符合預期

### 4.3 設定 CFG

- 首次啟動可產生預設設定，且可被讀回
- 每個設定項：**改 → 重啟 → 仍生效**（只驗「寫得進去」不夠）
- 非法值／損壞的設定檔 → 明確錯誤或安全回退，**不可靜默吃掉**
- 舊版設定檔可升級（向後相容）
- 設定寫在正確路徑（不亂寫進程式安裝目錄）
- 重設為預設值可用

### 4.4 使用者體驗 UX

**誠實界線**：能自動化的自動化；不能的就寫進 `manual-checklist.md` 並標 `manual`。

- 可自動化：頁面／視窗能開、關鍵元素存在、能返回、錯誤訊息非空且不是原始堆疊、
  鍵盤 Tab 走得通、離線／無權限時有明確提示、截圖比對抓明顯破圖
- 只能人工：視覺一致性、動畫順暢度、文案語氣、真實操作手感

**絕對禁止**：把沒實際驗證的 UX 項目寫成 `pass`。沒驗就是 `manual`。

### 4.5 效能 PERF

- 至少量：冷啟動時間、熱啟動時間、主要操作耗時、記憶體峰值、產物大小
- **每項至少跑 3 次取中位數**，記錄所有樣本與離散度；**單次量測不得當結論**
- 量測前先暖機一次並丟棄該次結果
- 門檻寫在腳本／`baseline.json` 裡，**不是報告時才現編**
- **首次執行**：只寫入 baseline，明確標「首次基準，本次不做回歸判定」
- 記錄機器狀態（是否插電、CPU 型號、是否有其他負載）——
  否則跨機比較沒有意義，這點要在報告裡誠實標註

---

## 5. REVIEW & REFINE 腳本（跑之前先審）

依 `/m2_review` 的分級（🔴 Blocker／🟡 Should fix／🔵 Nit）輸出，
每項附 `檔案:行號` + 問題 + 可直接套用的修法，**逐項按鈕確認再改**。

Smoke test 腳本專屬的檢查點：

| 檢查 | 為什麼是問題 | 級別 |
|---|---|---|
| 空 `catch {}`、`\|\| true`、`-ErrorAction SilentlyContinue` 包住整段 | **假通過** —— 比沒測更危險 | 🔴 |
| 只跑不驗（沒有任何 assertion） | 永遠 pass，形同裝飾 | 🔴 |
| 硬編路徑 `C:\Users\xxx`、寫死版本號／機器名 | 換一台機器就爛 | 🔴 |
| 帳密、token、真實客戶資料 | 違反 copilot-instructions 第 6 節 | 🔴 |
| 會刪使用者資料／覆蓋真實設定／改系統狀態卻不還原 | 破壞性，見 §6.1 | 🔴 |
| 固定 `Start-Sleep` 當等待 | flaky 的頭號來源 → 改輪詢條件 + 逾時 | 🟡 |
| 案例互相依賴 | 一個倒全部倒，看不出真正壞在哪 | 🟡 |
| 沒有逾時 | hang 住整條 CI | 🟡 |
| 失敗訊息沒有「期望 vs 實際」 | 看到紅字也不知道要查什麼 | 🟡 |
| 整組跑超過 10 分鐘 | 太慢就沒人跑，smoke test 的價值在快 | 🟡 |

Refine 原則：**最小變更**、沿用專案既有風格與命名、不引入新框架、不順手重排無關區塊。

---

## 6. 執行（含環境安全，這節不可跳）

### 6.1 執行前的沙箱與備份（硬性）

smoke test 會「安裝」「改設定」，**本質上是破壞性的**。執行前必須：

- 安裝測試一律在**可還原的隔離環境**：temp 目錄／專用測試路徑／容器／VM。
- 設定測試**先備份**使用者真實設定檔，或用環境變數把設定路徑導到隔離目錄；跑完**一定還原**。
- 記錄執行前狀態（安裝清單、相關服務、設定檔 hash），跑完比對並回報殘留。
- **絕不**：刪除使用者資料目錄、解除安裝使用者正在用的正式版、
  改系統層設定而不還原、`git clean -fd`、`Remove-Item -Recurse -Force` 打到使用者目錄。

需要動到系統層（登錄檔、服務、驅動、憑證、防火牆、環境變數）→
**停下來 beep + 按鈕確認**，並先說明「會改什麼、怎麼還原」。

### 6.2 跑

```powershell
pwsh -File smoketest_script/run-smoketest.ps1 -OutDir smoketest_script/results
"exit=$LASTEXITCODE"
```

- **一次跑完整組**；不要只跑一半就下結論。
- 過程輸出全部存進 `results/<stamp>/logs/`，報告要能連回去。
- 整組要有總逾時；hang 住能自己中止並記為 `fail`（原因 `timeout`）。
- pwsh 貼多行區塊常只執行第一行 → 輪詢／迴圈寫成單行，或寫成 `.ps1` 再執行。

### 6.3 Flaky 處理（否則結論不可信）

案例紅了 → **不改任何東西、原樣重跑該案例一次**：

- 兩次都紅 → `fail`（可重現）
- 一紅一綠 → `flaky`，**不得算通過**，並列入 §8.2 改善清單
- 同一案例在本次執行 flaky ≥ 2 次 → 這組結果不可信，**停下來回報**，不要硬出報告

### 6.4 執行後還原

還原 §6.1 備份的一切，並**輸出還原結果**。
還原失敗要在報告最上方明說（🔴），不可默默略過 —— 使用者的機器被留了殘留物，他有權立刻知道。

---

## 7. 量化報告（10 秒看懂）

**資料來源一律是 `result.json`**，不靠印象、不補一個「應該會過」的數字。
輸出到 chat，同時寫入 `smoketest_script/results/<stamp>/report.md`。

```markdown
# 🧪 Smoke Test — <App> <version>　2026-07-28 10:02
環境：Windows 11 26100 / x64 / portable　耗時：1m36s　退出碼：1

## 總分
**通過率 42/45 = 93.3%**　❌ FAIL 2　⚠️ FLAKY 0　⏭️ SKIP 1　✋ MANUAL 6（未計入分母）

| 面向 | 案例 | ✅ | ❌ | ⚠️ | ⏭️ | ✋ | 通過率 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 安裝 INS | 10 | 10 | 0 | 0 | 0 | 1 | 100% |
| 執行 RUN | 12 | 11 | 1 | 0 | 0 | 0 | 91.7% |
| 設定 CFG | 9 | 9 | 0 | 0 | 0 | 1 | 100% |
| 體驗 UX | 8 | 6 | 1 | 0 | 1 | 4 | 75.0% |
| 效能 PERF | 6 | 6 | 0 | 0 | 0 | 0 | 100% |

## ❌ 失敗（2）
1. **SMK-RUN-007｜關閉後無殘留 process**　`cases/runtime.ps1:64`
   - 期望：`0` 個殘留　實際：`1`（`M2_APEX.exe` PID 21844）
   - 重現：啟動 → 開主視窗 → 關閉 → 3 秒後查 process
   - 日誌：`results/20260728-1002/logs/run-007.log`

## 效能 vs 基準
| 指標 | 基準 | 本次（中位數/3 次） | 變化 | 門檻 | 判定 |
|---|---:|---:|---:|---:|:--:|
| 冷啟動 | 1380 ms | 1420 ms | +2.9% | ≤ 2000 | ✅ |
| 記憶體峰值 | 214 MB | 268 MB | **+25.2%** | ≤ 300 | ⚠️ |
> 樣本離散度：冷啟動 1402/1420/1455（±3.7%）｜機器：插電、無其他負載

## ✋ 待人工驗證（6）
（列出 manual checklist 未勾的項目 —— **這些不是通過**）

## 環境還原
✅ 設定檔已還原　✅ 測試安裝路徑已清除　✅ 無殘留服務

## 結論
🔴 **不可放行** — SMK-RUN-007 為 process 洩漏，會連帶影響升級覆蓋與解除安裝。
```

報告規則：

- 通過率分母 **= pass + fail + flaky + skip，不含 manual**；但 manual 數量必須出現在報告上。
- 沒跑到的面向標 **`未涵蓋`**，不可省略讓報告看起來很完整。
- 效能表沒有 baseline 時，寫「首次基準，不做回歸判定」，**不要編一個門檻**。
- 結論二選一：**可放行** / **不可放行**，不寫「大致上還行」這種話。

---

## 8. Bug 與改善清單（明確，不寫空話）

分成兩類，**不可混在一起**：

### 8.1 App 的 Bug（要修 code）

每筆必須有：

- 嚴重度：🔴 Blocker（不可放行）／🟡 Major／🔵 Minor
- `檔案:行號`（找得到的話；找不到就標「未定位」，不要瞎猜一個）
- 重現步驟（可照著重現，不是「有時候會」）
- **期望 vs 實際**
- 影響範圍（`grep` 確認過的呼叫端，不憑印象）
- 對應案例 ID

**這支 prompt 不修 App 的 bug** —— 只回報，交給使用者或 `/m2_review`。

### 8.2 Smoke test 本身要改善的地方

例如：覆蓋缺口、flaky 案例、跑太久、斷言太弱、依賴本機環境、失敗訊息不足以定位。
每筆給**具體修法**（可直接套用），不寫「建議加強測試」這種空話。

最後 beep + 按鈕：
**[修 smoke test 的問題]（最建議）／[產出 App bug 清單給我]／[先這樣]**

---

## 9. 子指令對照

| 指令 | 探索 | 改腳本 | 執行 | 出報告 |
|---|:--:|:--:|:--:|:--:|
| `/m2_smoketest` | ✅ | ✅（逐項確認） | ✅ | ✅ |
| `/m2_smoketest scan` | ✅ | ❌ | ❌ | 只出缺口分析 |
| `/m2_smoketest init` | ✅ | ✅ | ❌ | 只列新增了什麼 |
| `/m2_smoketest review` | ✅ | ❌ | ❌ | 只出 review 結果 |
| `/m2_smoketest run` | ✅ | ❌ | ✅ | ✅ |

---

## 硬性規則

### 絕不作弊（最重要）

- ❌ 為了讓報告好看而放寬門檻、註解掉案例、弱化斷言、加 `-ErrorAction SilentlyContinue`
- ❌ 把 `manual` / `skip` / `flaky` 算成通過，或把失敗案例從分母移除
- ❌ 宣稱跑過但實際沒跑 —— 報告裡**每個數字都必須來自 `result.json`**
- ❌ 沒實際量測就下效能結論（「應該沒變慢」不算數）
- ❌ 用單次量測下效能結論
- ❌ 改 App 的程式碼讓 smoke test 變綠（那是修 bug，不是這支 prompt 的事）

### 環境安全

- 破壞性動作只能在可還原的隔離環境；跑完必還原並**回報還原結果**
- 不刪使用者資料、不解除安裝使用者正在用的正式版、不改系統設定卻不還原
- 禁用 `git clean -fd`、`git reset --hard`，以及打到使用者目錄的 `Remove-Item -Recurse -Force`
- 要動系統層（登錄檔／服務／驅動／憑證／防火牆）→ **停下來問**

### 範圍

- **只改 `smoketest_script/` 底下的東西**，且逐項確認；不改 App 程式碼
- 不為 smoke test 引入新測試框架或新相依（專案已有的優先沿用）
- 不改 CI workflow（要把 smoke test 接進 CI 是另一件事，先問）
- **不 commit、不 push、不開 PR** —— 交給 `/m2_review` → `/m2_pr`

### 誠實回報

- 每個判定都要有實際輸出佐證；不確定標「不確定」，沒驗證標「未驗證」
- 找不到既有 smoke test 就說找不到，並列出掃過哪些路徑
- 第一次建立腳本時，明說「這是初版，覆蓋面有限」，不吹成完整驗證
- 時間與耗時一律用 PowerShell `Get-Date` 算，**絕不心算**

### 終端機與編碼

- pwsh 貼多行區塊常只執行第一行（here-string、多行迴圈都中過）→
  輪詢／迴圈寫成單行，或寫成 `.ps1` 檔再執行
- `.ps1` 只要含中文，一律存成 **UTF-8 with BOM**（Windows PowerShell 5.1 的 cp950 陷阱）

### `auto` 不適用

`/m2_smoketest` **不支援 `auto`** —— 安裝與設定測試會實際動到你的機器，
那些確認節點不能被免除。要少打擾就用 `/m2_smoketest run`（只跑不改）。
