@echo off
rem =====================================================================
rem  auto-merge-sync-pr.cmd — 選單式啟動器
rem  雙擊即可 approve + merge 各下游 repo 的自動同步 PR，免打指令。
rem  放置路徑：Deployment_script/auto-merge-sync-pr.cmd
rem =====================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "SCRIPT=%~dp0auto-merge-sync-pr.ps1"
set "REPOFILE=%~dp0repos.txt"

rem 優先用 pwsh（7+），找不到才退回 Windows PowerShell 5.1
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

if not exist "%SCRIPT%" (
    echo 找不到腳本：%SCRIPT%
    echo 請確認 auto-merge-sync-pr.ps1 與本檔在同一資料夾。
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo   M2 自動 PR 一鍵 Approve + Merge
echo ============================================================
echo   清單檔 : %REPOFILE%
echo   引擎   : %PS%
echo   對象   : chore/sync-m2-common-ai + chore/upgrade-sync-workflow
echo   附帶   : 自動核准卡住的 workflow run（Approve workflows to run）
echo ------------------------------------------------------------
echo   [1] 掃描   只列出待處理的自動 PR，不動任何 PR（安全）
echo   [2] 執行   approve + squash merge + 驗證 MERGED
echo   [3] 執行   同上，但不使用 --admin 強制合併
echo   [4] 編輯   開啟 repos.txt 編修清單
echo   [5] 離開
echo ============================================================
choice /c 12345 /n /m "請選擇 [1-5]: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto scan
if "%SEL%"=="2" goto apply
if "%SEL%"=="3" goto applynoadmin
if "%SEL%"=="4" goto edit
if "%SEL%"=="5" goto done
goto menu

:scan
echo.
echo === 掃描模式（dry-run，唯讀）===
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%"
echo.
pause
goto menu

:apply
echo.
echo === 執行模式：核准待核准的 workflow + approve + squash merge，被分支保護擋住時自動 --admin 強制合併 ===
choice /c YN /n /m "確定要繼續? [Y/N]: "
if errorlevel 2 goto menu
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply
echo.
pause
goto menu

:applynoadmin
echo.
echo === 執行模式（保守）：approve + squash merge，不使用 --admin ===
choice /c YN /n /m "確定要繼續? [Y/N]: "
if errorlevel 2 goto menu
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply -NoAdmin
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
