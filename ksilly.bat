@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

:: ============================================================
::  Ksilly v2.0.0 - SillyTavern Windows Launcher
::  https://github.com/Mia1889/Ksilly
:: ============================================================

set "VER=2.0.0"
set "REPO_RAW=https://raw.githubusercontent.com/Mia1889/Ksilly/main"
set "PROXY_1=https://ghfast.top/"
set "PROXY_2=https://gh-proxy.com/"
set "ST_DIR=%USERPROFILE%\SillyTavern"

title Ksilly v%VER%
cls
echo.
echo   ================================================================
echo.
echo    K S I L L Y   -   SillyTavern Launcher   v%VER%
echo.
echo    github.com/Mia1889/Ksilly
echo.
echo   ================================================================
echo.

:: ============================================================
:: STEP 1 - Find bash.exe (Git Bash)
:: ============================================================
echo   [1/3] Looking for Git Bash ...

set "BASH_EXE="

:: --- Check common Git install paths ---
if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
    goto :found_bash
)
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
    goto :found_bash
)
if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (
    set "BASH_EXE=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    goto :found_bash
)
if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" (
    set "BASH_EXE=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
    goto :found_bash
)
if exist "C:\Git\bin\bash.exe" (
    set "BASH_EXE=C:\Git\bin\bash.exe"
    goto :found_bash
)

:: --- Search PATH (skip System32 WSL bash) ---
for /f "tokens=* usebackq" %%i in (`where bash.exe 2^>nul`) do (
    set "_BPATH=%%i"
    echo "!_BPATH!" | findstr /i "System32" >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        set "BASH_EXE=%%i"
        goto :found_bash
    )
)

:: --- Try WSL ---
where wsl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo.
    echo   [!] Git Bash not found, but WSL detected.
    echo   [!] Launching via WSL ...
    echo.
    wsl -- bash -c "curl -fsSL '%REPO_RAW%/ksilly.sh' -o /tmp/ksilly_wsl.sh 2>/dev/null || curl -fsSL '%PROXY_1%%REPO_RAW%/ksilly.sh' -o /tmp/ksilly_wsl.sh 2>/dev/null; if [ -s /tmp/ksilly_wsl.sh ]; then bash /tmp/ksilly_wsl.sh; else echo 'Download failed'; fi; rm -f /tmp/ksilly_wsl.sh"
    goto :eof_clean
)

:: --- Nothing found ---
echo.
echo   ================================================================
echo.
echo    ERROR: Git Bash not found
echo.
echo    Please install Git for Windows:
echo.
echo      https://git-scm.com/download/win
echo.
echo    During installation, make sure to check:
echo.
echo      [x] Git Bash Here
echo      [x] Use Git from Windows Command Line
echo.
echo    After installation, run this file again.
echo.
echo   ================================================================
echo.
pause
goto :eof_clean

:found_bash
echo   [OK] Found: %BASH_EXE%

:: ============================================================
:: STEP 2 - Download / update ksilly.sh
:: ============================================================
echo   [2/3] Getting deploy script ...

if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.downloading"
set "GOT_NEW=0"

:: --- Method A: curl direct ---
where curl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    curl.exe -fsSL --connect-timeout 10 --max-time 60 "%REPO_RAW%/ksilly.sh" -o "%SH_TMP%" 2>nul
    if !ERRORLEVEL! equ 0 (
        if exist "%SH_TMP%" (
            for %%A in ("%SH_TMP%") do (
                if %%~zA GTR 1000 (
                    move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
                    set "GOT_NEW=1"
                    echo   [OK] Script downloaded (direct)
                )
            )
        )
    )
)

:: --- Method B: curl proxy 1 ---
if "!GOT_NEW!"=="0" (
    echo   [..] Direct failed, trying proxy ...
    where curl.exe >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        curl.exe -fsSL --connect-timeout 10 --max-time 60 "%PROXY_1%%REPO_RAW%/ksilly.sh" -o "%SH_TMP%" 2>nul
        if !ERRORLEVEL! equ 0 (
            if exist "%SH_TMP%" (
                for %%A in ("%SH_TMP%") do (
                    if %%~zA GTR 1000 (
                        move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
                        set "GOT_NEW=1"
                        echo   [OK] Script downloaded (proxy)
                    )
                )
            )
        )
    )
)

:: --- Method C: curl proxy 2 ---
if "!GOT_NEW!"=="0" (
    where curl.exe >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        curl.exe -fsSL --connect-timeout 10 --max-time 60 "%PROXY_2%%REPO_RAW%/ksilly.sh" -o "%SH_TMP%" 2>nul
        if !ERRORLEVEL! equ 0 (
            if exist "%SH_TMP%" (
                for %%A in ("%SH_TMP%") do (
                    if %%~zA GTR 1000 (
                        move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
                        set "GOT_NEW=1"
                        echo   [OK] Script downloaded (proxy 2)
                    )
                )
            )
        )
    )
)

:: --- Method D: PowerShell fallback ---
if "!GOT_NEW!"=="0" (
    echo   [..] curl failed, trying PowerShell ...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u='%REPO_RAW%/ksilly.sh'; try{(New-Object Net.WebClient).DownloadFile($u,'%SH_TMP%')}catch{try{(New-Object Net.WebClient).DownloadFile('%PROXY_1%'+$u,'%SH_TMP%')}catch{}}" 2>nul
    if exist "%SH_TMP%" (
        for %%A in ("%SH_TMP%") do (
            if %%~zA GTR 1000 (
                move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
                set "GOT_NEW=1"
                echo   [OK] Script downloaded (PowerShell)
            )
        )
    )
)

:: --- Cleanup temp ---
if exist "%SH_TMP%" del "%SH_TMP%" 2>nul

:: --- Final check ---
if not exist "%SH_FILE%" (
    echo.
    echo   [ERROR] Failed to download script and no local cache.
    echo           Please check your network connection.
    echo.
    echo   You can also try downloading manually:
    echo     %REPO_RAW%/ksilly.sh
    echo.
    pause
    goto :eof_clean
)

if "!GOT_NEW!"=="0" (
    echo   [!] Download failed, using local cache
)

:: ============================================================
:: Save this .bat to SillyTavern dir
:: ============================================================
set "BAT_SELF=%~f0"
set "BAT_DEST=%ST_DIR%\ksilly.bat"

:: Only copy if not already running from there
if not "%BAT_SELF%"=="%BAT_DEST%" (
    copy /y "%BAT_SELF%" "%BAT_DEST%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   [OK] Launcher saved to: %BAT_DEST%
    )
)

:: ============================================================
:: STEP 3 - Launch via Git Bash
:: ============================================================
echo   [3/3] Launching Ksilly ...
echo.
echo   ================================================================
echo.

:: Convert backslash to forward slash for bash
set "SH_UNIX=%SH_FILE:\=/%"

:: Collect arguments
set "PASS_ARGS="
set "HAS_ARGS=0"
if not "%~1"=="" (
    set "PASS_ARGS=%*"
    set "HAS_ARGS=1"
)

:: Launch Git Bash
if "!HAS_ARGS!"=="1" (
    "%BASH_EXE%" --login -c "cd ~ ; bash '%SH_UNIX%' %PASS_ARGS%"
) else (
    "%BASH_EXE%" --login -c "cd ~ ; bash '%SH_UNIX%'"
)

set "ECODE=!ERRORLEVEL!"

echo.
if !ECODE! neq 0 (
    echo   Script exited with code: !ECODE!
)
echo   Press any key to close ...
pause >nul

:eof_clean
endlocal
exit /b 0
