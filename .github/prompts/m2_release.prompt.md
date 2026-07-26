---
description: PR-based CI release — bump version, open & merge PR, tag, push tag; CI builds & publishes. 附錄 A 為 Release CI 產出規格（Portable + Setup、靜默安裝契約）。
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
- **若本次任務是「建置或修改發版 CI / 安裝檔」而非「發一版」，直接跳到附錄 A**，不要跑第 1～5 節的發版流程。

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
  （附錄 A 的修改屬於「重新定義發版產出規格」，**必須另開 PR**，不得夾在發版 PR 內，也不得在發版中途進行。）
- tag 已存在時停止並回報，不使用 `-f` 覆寫、不刪除既有 tag。
- 版本號格式、tag 格式、commit / PR 文案一律比對 repo 歷史後沿用。
- 任何步驟出現與預期不符（版本號不一致、branch 非乾淨、pull 非 fast-forward）→ 停下來回報，不自行修補。

---

# 附錄 A：Release CI 產出規格（Portable + Setup + 靜默安裝）

> **何時讀這段**：建置或修改本 repo 的 build / release CI、安裝檔腳本；或把這份規格套到其他 M2 app repo。
> **發一版的日常流程不需要讀這段**（第 1～5 節即可）。
> 這是一份 **驗收契約**，不是步驟流程；不得在發版中途依據它去改 workflow。

目的：讓 **M2_APEX 內建的自動更新器**（`Services/UpdateService.cs`）能在 Settings → Quick Picks 按
**Install / Check Update** 時全自動下載＋靜默安裝，而不是把使用者丟去瀏覽器手動下載。
更新器 **只認檔名與 exit code，不做簽章驗證**，下列規則不符就會退回手動下載。

## A.0 動手前先讀出本 repo 現況（必做）

```bash
cat README.md | head -40                  # app 名稱、安裝位置
ls .github/workflows/                     # 既有 release workflow 與觸發條件
ls installer/ *.iss 2>/dev/null           # 是否已有 Inno Setup 腳本
git tag --sort=-v:refname | head -5       # tag 格式
gh release view --json tagName,assets     # 目前 release 實際產出的資產檔名
```

- 依實際技術棧調整（.NET / Electron / Python…），**不要照抄別的 repo 的 workflow**。
- 若目前是 electron-builder（NSIS），見 A.4 的「非 Inno Setup」段。

## A.1 每次發版必須產出的 4 個資產

| # | 種類 | 架構 | 說明 |
|---|---|---|---|
| 1 | Portable | x64 | 單一 exe，免安裝、雙擊即跑 |
| 2 | Portable | arm64 | 同上（Windows on ARM） |
| 3 | Setup | x64 | 安裝程式，支援靜默安裝 |
| 4 | Setup | arm64 | 同上 |

**兩種版本都要出，缺一不可**：Portable 給不想安裝的人，Setup 給 M2_APEX 自動更新用。

## A.2 資產檔名規則（硬性，APEX 靠檔名判斷）

APEX 的 `PickAsset()` / `IsInstallerAsset()` 實際規則：

```text
必須 .exe 結尾
架構判斷：arm64 機器 → 檔名含 "arm64"
          x64   機器 → 檔名含 "x64" 且不含 "arm64"
安裝檔判斷：檔名含 "setup"（不分大小寫）→ 才會靜默安裝，否則開瀏覽器
優先序：同架構的 setup > 同架構任一 exe > 任一 exe
```

**採用的命名**（`<APP>` 換成實際名稱，`<X.Y.Z>` 為版本號）：

```text
<APP>-<X.Y.Z>-win-x64.exe            ← Portable x64      （不可含 setup）
<APP>-<X.Y.Z>-win-arm64.exe          ← Portable arm64    （不可含 setup）
<APP>-<X.Y.Z>-Setup-x64.exe          ← Setup x64
<APP>-<X.Y.Z>-Setup-arm64.exe        ← Setup arm64
```

規則細節：

- 每個檔名 **必須帶且只帶一個架構 token**（`x64` 或 `arm64`）。沒有架構 token 的 exe 只會被當最後備援。
- Portable **絕對不可**出現 `setup` 字樣，否則會被誤當安裝檔靜默執行。
- Setup **必須**出現 `setup` 字樣。
- **不要上傳其他 `.exe` 資產**（測試檔、工具等），會干擾挑選。`.blockmap`、`.yml`、`.txt` 不受影響（非 `.exe` 結尾）。

## A.3 Portable 版要求

- 單一檔案、self-contained，目標機器 **不需先裝 runtime**。
- .NET 範例：

```powershell
dotnet publish <APP>.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true `
  -p:Version=<X.Y.Z> `
  -o publish/win-x64
```

- 不寫入 `%ProgramFiles%`，設定檔放 `%APPDATA%` 或 exe 同目錄。

## A.4 Setup 版要求（靜默安裝）

### A.4.1 必須能被這組參數靜默驅動

M2_APEX 一律用這組參數啟動安裝檔（`UpdateService.InstallAppAsync`）：

```powershell
Start-Process -FilePath '<setup>.exe' `
  -ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait -PassThru
```

- 這是 **Inno Setup** 的參數集 → **安裝程式必須是 Inno Setup 6+**。
- 成功時 **exit code 必須為 0**；非 0 一律視為安裝失敗。
- 過程中 **不可跳任何視窗、UAC 或需要按確認的對話框**。
- **舊版正在執行時，仍必須能靜默覆蓋升級並回報 exit code 0**（硬性條件）。
  自動更新的实際場景就是「使用者開著 app 按 Check Update」，安裝檔不得因偵測到執行中而中止、等待或要求使用者手動關閉。
  實作需兩邊配合：
  - 安裝檔側：`.iss` 必須設 `AppMutex` 與 `CloseApplications=yes`（見 A.4.2）。
  - **app 側：程式啟動時必須建立同名的 named single-instance mutex**（例 `<APP>.SingleInstance`），否則 `AppMutex` 偵測不到，檔案會因被鎖定而替換失敗。

### A.4.2 Inno Setup 腳本關鍵設定

```ini
[Setup]
AppId={{<固定不變的 GUID>}
AppName=<APP>
AppVersion={#AppVersion}
DefaultDirName={autopf}\<APP>
OutputBaseFilename=<APP>-{#AppVersion}-Setup-{#Arch}

; 靜默安裝不得觸發 UAC：per-user 安裝
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; 讓安裝程式能偵測並關閉執行中的本體（配合 /CLOSEAPPLICATIONS）
AppMutex=<APP>.SingleInstance
CloseApplications=yes
RestartApplications=no

; 32-bit 的 Inno 主程式在 64-bit OS 上若不開 64-bit 模式，
; 提權安裝會誤裝進 Program Files (x86)（ARM64 上實測會踩到）
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Run]
; 安裝後啟動：加 skipifsilent，靜默模式下不可自動開 app
; 若 app manifest 是 highestAvailable，必須加 shellexec，否則 CreateProcess 會回 740
Filename: "{app}\<APP>.exe"; Description: "{cm:LaunchProgram,<APP>}"; \
  Flags: nowait postinstall skipifsilent shellexec
```

- `AppId` **一經發布就不可更改**，否則升級會變成裝出第二份。
- 每個架構各編一次：`ISCC.exe /DAppVersion=<X.Y.Z> /DArch=x64 /DSourceExe=... /DOutDir=dist installer\<APP>.iss`

### A.4.3 若目前不是 Inno Setup（例如 electron-builder / NSIS）

electron-builder 產出的是 **NSIS**，靜默參數是 `/S`，收到 `/SILENT` 會被忽略 → 仍會跳安裝精靈。
兩條路，擇一：

- **（建議）改用 Inno Setup 產生 Setup 資產**，與其他 M2 app 一致。
- 或維持 NSIS，但必須回報給 M2_APEX 增加 NSIS 分支；在那之前該 app 的自動更新不會生效。

## A.5 安裝結果必須讓 M2_APEX 找得到、比得出版本

### A.5.1 安裝位置

必須落在 M2_APEX `Assets/default-app-list.json` 該 app 的 `SearchDirs` 之一：

```text
%LOCALAPPDATA%\Programs\<APP>      ← per-user 安裝（PrivilegesRequired=lowest 的落點）
%ProgramFiles%\<APP>
%ProgramFiles(x86)%\<APP>
```

`DefaultDirName={autopf}\<APP>` 同時滿足前兩者。

### A.5.2 exe 檔名

必須符合 catalog 的 `ExeNames`，例如 `M2_LOG.exe`（或 `M2LOG.exe`）。

### A.5.3 exe 版本資訊必須是純 `X.Y.Z`

APEX 用 `FileVersionInfo.ProductVersion`（退而求其次 `FileVersion`）跟 GitHub tag 比大小，
而它的解析器 **不接受 `+` 建置中繼資料**：

```text
"0.1.6"          → 0.1.6   ✅
"0.1.6-beta"     → 0.1.6   ✅（後綴會被丟掉）
"0.1.6+a1b2c3d"  → 0.1.0   ❌ patch 被解析成 0，會誤判成「沒有更新」
```

- .NET 專案務必在 csproj 加上，避免 SourceLink 附加 git sha：

```xml
<IncludeSourceRevisionInInformationalVersion>false</IncludeSourceRevisionInInformationalVersion>
```

- 並在 publish 時傳 `-p:Version=<X.Y.Z>`。

## A.6 Release CI 必做事項清單

依序實作，每一項都要有對應的 workflow step：

1. **觸發條件**：`on: push: tags: [ 'v*.*.*' ]`，另備 `workflow_dispatch` 手動輸入版號。
2. **權限**：`permissions: contents: write`（建立 release 用）。
3. **解析版號**：由 tag 去掉 `v` 前綴取得；**驗證必須符合 `^\d+\.\d+\.\d+$`，不符就 fail**。
4. **矩陣建置**：`strategy.matrix.rid: [ win-x64, win-arm64 ]`，跑在 `windows-latest`。
5. **建 Portable**：single-file self-contained publish，版號注入 exe。
6. **搬 Portable 到 dist**：更名為 `<APP>-<X.Y.Z>-win-<arch>.exe`。
7. **安裝 Inno Setup**：`choco install innosetup --no-progress -y`（需 6.3+ 才支援 `arm64` 架構值）。
8. **編 Setup**：以 `/DAppVersion /DArch /DSourceExe /DOutDir` 呼叫 `ISCC.exe`，
   **檢查 `$LASTEXITCODE` 非 0 就 throw**，輸出到 `dist/`。
9. **靜默安裝自我驗證（強烈建議）**：在 runner 上實跑一次，確保契約沒壞：

```powershell
$p = Start-Process "dist/<APP>-$ver-Setup-$arch.exe" `
     -ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Silent install failed: $($p.ExitCode)" }

$exe = "$env:LOCALAPPDATA\Programs\<APP>\<APP>.exe"
if (-not (Test-Path $exe)) { throw "Installed exe not found at $exe" }

$pv = (Get-Item $exe).VersionInfo.ProductVersion
if ($pv -notmatch '^\d+\.\d+\.\d+') { throw "ProductVersion '$pv' is not X.Y.Z" }
```

10. **執行中覆蓋升級驗證（對應 A.4.1 硬性條件，必做）**：啟動剛裝好的 app，再跑一次同一份安裝檔：

```powershell
$app = Start-Process $exe -PassThru
Start-Sleep -Seconds 5                      # 等 mutex 建立

$p2 = Start-Process "dist/<APP>-$ver-Setup-$arch.exe" `
      -ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait -PassThru
if ($p2.ExitCode -ne 0) { throw "Silent upgrade over running app failed: $($p2.ExitCode)" }

Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
```

   若 app 在 runner 上無法啟動（需互動桌面等），**至少靜態把關鍵字守住**，不符就 fail：

```powershell
$iss = Get-Content "installer/<APP>.iss" -Raw
foreach ($k in 'AppMutex=','CloseApplications=yes') {
    if ($iss -notmatch [regex]::Escape($k)) { throw "installer script is missing '$k'" }
}
```

11. **檔名守門（建議）**：發布前掃 `dist/*.exe`，驗證
    「恰好 4 個 exe」「每個都帶單一架構 token」「Setup 含 `setup`、Portable 不含」，不符就 fail。
12. **上傳 artifact**：`if-no-files-found: error`。
13. **建立 Release**（`softprops/action-gh-release@v2`）：
    - `tag_name: v<X.Y.Z>`
    - `generate_release_notes: true`（release body 會顯示在 APEX 的更新提示）
    - `files: dist/*.exe`
    - **`draft: false`、`prerelease: false`** — 兩者任一為 true，`/releases/latest` 就抓不到，
      APEX 會顯示「已是最新版」。
14. **不要覆蓋既有 tag 的 release 資產**；發錯版就發下一個 patch。

## A.7 會讓自動更新失效的常見地雷

| 症狀 | 原因 |
|---|---|
| 按 Check Update 直接開瀏覽器 | 資產檔名不含 `setup`；或 release 是 draft/prerelease；或 GitHub API 被限流（每小時 60 次）走 redirect fallback |
| 下載完卻跳出安裝精靈 | 安裝檔不是 Inno Setup（NSIS 只認 `/S`） |
| 安裝跳 UAC 卡住 | `PrivilegesRequired` 不是 `lowest` |
| app 開著時升級失敗、exit code 非 0，或裝完還是舊版 | `.iss` 缺 `AppMutex` / `CloseApplications=yes`，或 **app 本體沒建同名 single-instance mutex** → exe 被鎖定替換失敗（違反 A.4.1 硬性條件） |
| 明明有新版卻說「已是最新版」 | 已安裝 exe 的 `ProductVersion` 含 `+gitsha`，patch 被解析成 0 |
| 裝完 APEX 仍顯示 Install（沒偵測到） | 安裝路徑不在 catalog 的 `SearchDirs`，或 exe 檔名不在 `ExeNames` |
| 裝出兩份程式 | `AppId` 被改過 |
| ARM64 裝進 Program Files (x86) | 少了 `ArchitecturesInstallIn64BitMode` |

## A.8 驗收清單（發版後逐項確認）

- [ ] `gh release view --json assets` 列出 **恰好 4 個 `.exe`**，檔名符合 A.2 規則
- [ ] release 非 draft、非 prerelease，tag 為 `vX.Y.Z`
- [ ] Portable 在乾淨機器雙擊可跑
- [ ] Setup 以 `/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` 執行，exit code 0、全程無視窗
- [ ] 安裝後 exe 落在 `%LOCALAPPDATA%\Programs\<APP>\`，`ProductVersion` 為純 `X.Y.Z`
- [ ] **app 執行中再跑一次靜默安裝，仍回報 exit code 0 且成功覆蓋升級**（A.4.1 硬性條件）
- [ ] 在 M2_APEX Settings → Quick Picks 按 **Check Update**，全程無瀏覽器、自動裝好

## A.9 同步登記到 M2_APEX（一次性）

新 app 首次發版後，確認 M2_APEX 的 `Assets/default-app-list.json` 有對應項目，
四個欄位必須與實際安裝結果一致：

```json
{
  "Label": "<APP>",
  "Arguments": "\"{path}\"",
  "ExeNames": [ "<APP>", "<APPNoUnderscore>" ],
  "SearchDirs": [
    "%LOCALAPPDATA%\\Programs\\<APP>",
    "%ProgramFiles%\\<APP>",
    "%ProgramFiles(x86)%\\<APP>"
  ],
  "Repo": "M2Station/<APP>"
}
```

`Repo` 缺漏 → Settings 不會顯示 Install / Check Update 按鈕。
