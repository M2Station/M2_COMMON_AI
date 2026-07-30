@echo off
rem =====================================================================
rem  trigger-sync-now.cmd — 選單式啟動器
rem  雙擊即可對 repos.txt 內所有 repo 立刻觸發 sync-m2-common-ai.yml，免打指令。
rem  放置路徑：Deployment_script/trigger-sync-now.cmd
rem =====================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "SCRIPT=%~dp0trigger-sync-now.ps1"
set "REPOFILE=%~dp0repos.txt"

rem 優先用 pwsh（7+），找不到才退回 Windows PowerShell 5.1
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

if not exist "%SCRIPT%" (
    echo 找不到腳本：%SCRIPT%
    echo 請確認 trigger-sync-now.ps1 與本檔在同一資料夾。
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo   M2 同步 workflow 立即觸發工具
echo ============================================================
echo   清單檔 : %REPOFILE%
echo   引擎   : %PS%
echo   對象   : .github/workflows/sync-m2-common-ai.yml
echo ------------------------------------------------------------
echo   [1] 預覽   只檢查哪些 repo 可觸發，不送出（安全）
echo   [2] 觸發   立刻觸發全部 repo，不等 run 結束
echo   [3] 觸發   立刻觸發並等每個 run 跑完，回報成功／失敗
echo   [4] 編輯   開啟 repos.txt 編修清單
echo   [5] 離開
echo ============================================================
choice /c 12345 /n /m "請選擇 [1-5]: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto preview
if "%SEL%"=="2" goto run
if "%SEL%"=="3" goto runwait
if "%SEL%"=="4" goto edit
if "%SEL%"=="5" goto done
goto menu

:preview
echo.
echo === 預覽模式（dry-run，唯讀）===
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%"
echo.
pause
goto menu

:run
echo.
echo === 觸發模式：對清單內每個 repo 送出 workflow_dispatch ===
choice /c YN /n /m "確定要繼續? [Y/N]: "
if errorlevel 2 goto menu
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply
echo.
pause
goto menu

:runwait
echo.
echo === 觸發並等待：送出後等每個 run 跑完（每個上限 10 分鐘）===
choice /c YN /n /m "確定要繼續? [Y/N]: "
if errorlevel 2 goto menu
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply -Wait
echo.
pause
goto menu

:edit
if not exist "%REPOFILE%" (
    >"%REPOFILE%" echo # 一行一個 repo：owner/name 或 GitHub URL；# 開頭與空行忽略
)
notepad "%REPOFILE%"
goto menu

:done
endlocal
exit /b 0
