@echo off
rem =====================================================================
rem  update-sync-workflow.cmd — 選單式啟動器
rem  雙擊即可執行 update-sync-workflow.ps1，免打指令。
rem  放置路徑：Deployment_script/update-sync-workflow.cmd
rem =====================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "SCRIPT=%~dp0update-sync-workflow.ps1"
set "REPOFILE=%~dp0repos.txt"

rem 優先用 pwsh（7+），找不到才退回 Windows PowerShell 5.1
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

if not exist "%SCRIPT%" (
    echo 找不到腳本：%SCRIPT%
    echo 請確認 update-sync-workflow.ps1 與本檔在同一資料夾。
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo   M2 Sync Workflow 批次更新工具
echo ============================================================
echo   清單檔 : %REPOFILE%
echo   引擎   : %PS%
echo ------------------------------------------------------------
echo   [1] 掃描   只回報 相同／不同，不動任何 repo（安全）
echo   [2] 更新   對不同／缺少的 repo 開 PR
echo   [3] 編輯   開啟 repos.txt 編修清單
echo   [4] 離開
echo ============================================================
choice /c 1234 /n /m "請選擇 [1-4]: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto scan
if "%SEL%"=="2" goto apply
if "%SEL%"=="3" goto edit
if "%SEL%"=="4" goto done
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
echo === 更新模式：將對「不同／缺少」的 repo 開真正的 PR ===
choice /c YN /n /m "確定要繼續? [Y/N]: "
if errorlevel 2 goto menu
set "ASSIGNEE="
set /p "ASSIGNEE=PR assignee（GitHub 帳號，直接 Enter 略過）: "
echo.
if "%ASSIGNEE%"=="" (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply
) else (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RepoFile "%REPOFILE%" -Apply -Assignee "%ASSIGNEE%"
)
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
