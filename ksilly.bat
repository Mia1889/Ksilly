@echo off
:: ============================================================
::  Ksilly v2.0.0 - SillyTavern Windows Launcher
::  Auto-install Git / Node.js / Run ksilly.sh
::  Repo: https://github.com/Mia1889/Ksilly
:: ============================================================
setlocal EnableDelayedExpansion

set "VER=2.0.0"
set "REPO_RAW=https://raw.githubusercontent.com/Mia1889/Ksilly/main"
set "PROXY=https://ghfast.top/"
set "ST_DIR=%USERPROFILE%\SillyTavern"
set "TEMP_DIR=%TEMP%\ksilly_setup"
set "NEED_RESTART=0"
set "IS_ADMIN=0"
set "USE_CHINA=0"

title Ksilly v%VER% - SillyTavern
cls
echo.
echo    _  __     _ _ _
echo   ^| ^|/ /    (_) ^| ^|
echo   ^| ' / ___ _^| ^| ^|_   _
echo   ^|  ^< / __^| ^| ^| ^| ^| ^| ^|
echo   ^| . \\__ \ ^| ^| ^| ^|_^| ^|
echo   ^|_^|\_\___/_^|_^|_^\__,_^|
echo.
echo   SillyTavern Installer v%VER%  [Windows]
echo   =============================================
echo.

:: =============================================
:: Check admin
:: =============================================
net session >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "IS_ADMIN=1"
)

:: =============================================
:: Step 0: Detect network
:: =============================================
echo   [0/5] Detecting network...
curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "USE_CHINA=1"
        echo   [OK] China mainland detected, using proxy
    ) else (
        echo   [WARN] Network issue, will try anyway
    )
) else (
    echo   [OK] International network, direct connect
)
echo.

:: =============================================
:: Step 1: Check / Install Git
:: =============================================
echo   [1/5] Checking Git...
call :sub_find_git
if defined GIT_OK (
    for /f "tokens=*" %%v in ('git --version 2^>nul') do echo   [OK] %%v
    goto :step2
)

echo   [WARN] Git not found, installing...
echo.
call :sub_install_git
call :sub_refresh_path
call :sub_find_git
if not defined GIT_OK (
    echo.
    echo   =============================================
    echo   Git auto-install failed.
    echo.
    echo   Please install manually:
    echo     https://git-scm.com/download/win
    echo.
    echo   Then re-run this script.
    echo   =============================================
    echo.
    pause
    goto :cleanup
)
echo   [OK] Git installed successfully
set "NEED_RESTART=1"

:: =============================================
:: Step 2: Check / Install Node.js
:: =============================================
:step2
echo.
echo   [2/5] Checking Node.js...
call :sub_find_node
if defined NODE_OK (
    for /f "tokens=*" %%v in ('node -v 2^>nul') do echo   [OK] Node.js %%v
    goto :step2done
)

echo   [WARN] Node.js not found or too old, installing...
echo.
call :sub_install_node
call :sub_refresh_path
call :sub_find_node
if not defined NODE_OK (
    echo.
    echo   =============================================
    echo   Node.js auto-install failed.
    echo.
    echo   Please install manually (v18+):
    echo     https://nodejs.org/
    echo.
    echo   Then re-run this script.
    echo   =============================================
    echo.
    pause
    goto :cleanup
)
echo   [OK] Node.js installed successfully
set "NEED_RESTART=1"

:step2done

:: Refresh PATH if new software installed
if "!NEED_RESTART!"=="1" (
    echo.
    echo   ---------------------------------------------
    echo   Dependencies installed, refreshing PATH...
    echo   ---------------------------------------------
    echo.
    call :sub_refresh_path
    call :sub_find_git
    call :sub_find_node
    if not defined GIT_OK (
        echo   [FAIL] Git not detected after install
        echo         Please close this window and re-run
        pause
        goto :cleanup
    )
    if not defined NODE_OK (
        echo   [FAIL] Node.js not detected after install
        echo         Please close this window and re-run
        pause
        goto :cleanup
    )
    echo   [OK] All dependencies verified
)

:: Show results
echo.
echo   =============================================
for /f "tokens=*" %%v in ('git --version 2^>nul') do echo   [OK] %%v
for /f "tokens=*" %%v in ('node -v 2^>nul') do echo   [OK] Node.js %%v
for /f "tokens=*" %%v in ('npm -v 2^>nul') do echo   [OK] npm v%%v
echo   =============================================

:: =============================================
:: Step 3: Find Git Bash
:: =============================================
echo.
echo   [3/5] Locating Git Bash...
call :sub_find_bash
if not defined BASH_EXE (
    echo   [FAIL] bash.exe not found
    echo         Git install may be incomplete
    echo         Please reinstall Git for Windows
    pause
    goto :cleanup
)
echo   [OK] Bash: !BASH_EXE!

:: =============================================
:: Step 4: Get ksilly.sh
:: =============================================
echo.
echo   [4/5] Getting deploy script...

if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.tmp"
set "GOT_NEW=0"

if "!USE_CHINA!"=="1" (
    call :sub_download "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :sub_download "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
) else (
    call :sub_download "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :sub_download "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
)

if "!GOT_NEW!"=="1" (
    move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
    echo   [OK] Script updated
) else (
    del "%SH_TMP%" 2>nul
    if exist "%SH_FILE%" (
        echo   [WARN] Download failed, using cached version
    ) else (
        echo   [FAIL] Download failed and no cache found
        echo         Please check your network connection
        pause
        goto :cleanup
    )
)

:: Save BAT itself to ST dir
set "BAT_DEST=%ST_DIR%\ksilly.bat"
if not "%~f0"=="%BAT_DEST%" (
    copy /y "%~f0" "%BAT_DEST%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   [OK] Launcher saved: %BAT_DEST%
        echo       You can double-click it next time
    )
)

:: =============================================
:: Step 5: Launch via Git Bash
:: =============================================
echo.
echo   [5/5] Launching Ksilly...
echo   =============================================
echo.

:: Convert Windows backslash path to forward slash
set "SH_UNIX=!SH_FILE:\=/!"

:: Collect any passed arguments
set "PASS_ARGS="
if not "%~1"=="" set "PASS_ARGS=%*"

:: Run through Git Bash
if defined PASS_ARGS (
    "!BASH_EXE!" --login -c "bash '!SH_UNIX!' !PASS_ARGS!"
) else (
    "!BASH_EXE!" --login -c "bash '!SH_UNIX!'"
)

set "EC=!ERRORLEVEL!"
if !EC! neq 0 (
    echo.
    echo   Script exit code: !EC!
)
echo.
echo   Press any key to close...
pause >nul
goto :cleanup


:: #############################################
:: #         SUBROUTINES BELOW                 #
:: #############################################


:: =============================================
:sub_find_git
:: Sets GIT_OK=1 if git.exe is found in PATH
:: =============================================
set "GIT_OK="

:: Check PATH first
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "GIT_OK=1"
    goto :eof
)

:: Check common install locations
set "GIT_CHECK_1=%ProgramFiles%\Git\cmd\git.exe"
set "GIT_CHECK_2=%ProgramFiles(x86)%\Git\cmd\git.exe"
set "GIT_CHECK_3=%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
set "GIT_CHECK_4=%USERPROFILE%\scoop\apps\git\current\cmd\git.exe"
set "GIT_CHECK_5=C:\Git\cmd\git.exe"

for %%n in (1 2 3 4 5) do (
    if exist "!GIT_CHECK_%%n!" (
        for %%f in ("!GIT_CHECK_%%n!") do set "PATH=%%~dpf;!PATH!"
        set "GIT_OK=1"
        goto :eof
    )
)
goto :eof


:: =============================================
:sub_find_node
:: Sets NODE_OK=1 if node.exe >= v18 is found
:: =============================================
set "NODE_OK="

:: Check PATH
where node.exe >nul 2>&1
if !ERRORLEVEL! equ 0 goto :sub_fn_ver

:: Check common install locations
set "NODE_CHECK_1=%ProgramFiles%\nodejs\node.exe"
set "NODE_CHECK_2=%ProgramFiles(x86)%\nodejs\node.exe"
set "NODE_CHECK_3=%LOCALAPPDATA%\Programs\nodejs\node.exe"
set "NODE_CHECK_4=%APPDATA%\nvm\current\node.exe"
set "NODE_CHECK_5=%USERPROFILE%\scoop\apps\nodejs-lts\current\node.exe"
set "NODE_CHECK_6=%USERPROFILE%\scoop\apps\nodejs\current\node.exe"

for %%n in (1 2 3 4 5 6) do (
    if exist "!NODE_CHECK_%%n!" (
        for %%f in ("!NODE_CHECK_%%n!") do set "PATH=%%~dpf;!PATH!"
        goto :sub_fn_ver
    )
)
goto :eof

:sub_fn_ver
:: Verify version >= 18
for /f "tokens=1 delims=." %%a in ('node -v 2^>nul') do (
    set "NVER=%%a"
    set "NVER=!NVER:v=!"
)
if not defined NVER goto :eof
if !NVER! GEQ 18 (
    set "NODE_OK=1"
) else (
    echo   [WARN] Node.js v!NVER! too old, need v18+
)
goto :eof


:: =============================================
:sub_find_bash
:: Sets BASH_EXE=<path> if bash.exe is found
:: =============================================
set "BASH_EXE="

:: Method 1: Derive from git.exe location
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "tokens=*" %%i in ('where git.exe 2^>nul') do (
        set "GITEXE_DIR=%%~dpi"
    )
    if defined GITEXE_DIR (
        :: git.exe is typically in cmd\, bash.exe in ..\bin\
        if exist "!GITEXE_DIR!..\bin\bash.exe" (
            set "BASH_EXE=!GITEXE_DIR!..\bin\bash.exe"
            goto :eof
        )
        :: Or same directory
        if exist "!GITEXE_DIR!bash.exe" (
            set "BASH_EXE=!GITEXE_DIR!bash.exe"
            goto :eof
        )
    )
)

:: Method 2: Check common paths directly
set "BASH_CHECK_1=%ProgramFiles%\Git\bin\bash.exe"
set "BASH_CHECK_2=%ProgramFiles(x86)%\Git\bin\bash.exe"
set "BASH_CHECK_3=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
set "BASH_CHECK_4=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
set "BASH_CHECK_5=C:\Git\bin\bash.exe"

for %%n in (1 2 3 4 5) do (
    if exist "!BASH_CHECK_%%n!" (
        set "BASH_EXE=!BASH_CHECK_%%n!"
        goto :eof
    )
)

:: Method 3: Search where (exclude System32 WSL bash)
for /f "tokens=*" %%i in ('where bash.exe 2^>nul') do (
    echo "%%i" | findstr /i "System32" >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        set "BASH_EXE=%%i"
        goto :eof
    )
)
goto :eof


:: =============================================
:sub_install_git
:: Tries winget then direct download
:: =============================================
echo   ---------------------------------------------
echo   Installing Git for Windows...
echo   ---------------------------------------------

:: Try winget first
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   Trying winget install...
    winget install --id Git.Git --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        timeout /t 3 /nobreak >nul 2>&1
        call :sub_refresh_path
        call :sub_find_git
        if defined GIT_OK (
            echo   [OK] Git installed via winget
            goto :eof
        )
    )
    echo   [WARN] winget method failed, trying download...
)

:: Download installer
echo   Downloading Git installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "GIT_INSTALLER=%TEMP_DIR%\git-installer.exe"
set "GIT_DL_URL=https://github.com/git-for-windows/git/releases/latest/download/Git-2.49.0-64-bit.exe"
set "GIT_DL_CN=https://registry.npmmirror.com/-/binary/git-for-windows/v2.49.0.windows.1/Git-2.49.0-64-bit.exe"

if "!USE_CHINA!"=="1" (
    call :sub_download "!GIT_DL_CN!" "%GIT_INSTALLER%"
    if "!DL_OK!"=="0" call :sub_download "%PROXY%!GIT_DL_URL!" "%GIT_INSTALLER%"
    if "!DL_OK!"=="0" call :sub_download "!GIT_DL_URL!" "%GIT_INSTALLER%"
) else (
    call :sub_download "!GIT_DL_URL!" "%GIT_INSTALLER%"
    if "!DL_OK!"=="0" call :sub_download "%PROXY%!GIT_DL_URL!" "%GIT_INSTALLER%"
)

if not exist "%GIT_INSTALLER%" (
    echo   [FAIL] Git download failed
    goto :eof
)

:: Verify file size (should be > 50MB)
set "GIT_SIZE_OK=0"
for %%A in ("%GIT_INSTALLER%") do (
    if %%~zA GTR 5000000 set "GIT_SIZE_OK=1"
)
if "!GIT_SIZE_OK!"=="0" (
    echo   [FAIL] Downloaded file too small, likely corrupt
    del "%GIT_INSTALLER%" 2>nul
    goto :eof
)

echo   [OK] Download complete
echo.
echo   Installing silently (may take 1-2 minutes)...
echo   If a security prompt appears, please click YES
echo.

"%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" 2>nul

timeout /t 5 /nobreak >nul 2>&1
del "%GIT_INSTALLER%" 2>nul
goto :eof


:: =============================================
:sub_install_node
:: Tries winget then MSI download
:: =============================================
echo   ---------------------------------------------
echo   Installing Node.js LTS...
echo   ---------------------------------------------

:: Try winget
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   Trying winget install...
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        timeout /t 5 /nobreak >nul 2>&1
        call :sub_refresh_path
        call :sub_find_node
        if defined NODE_OK (
            echo   [OK] Node.js installed via winget
            goto :eof
        )
    )
    echo   [WARN] winget method failed, trying download...
)

:: Download MSI
echo   Downloading Node.js installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "NODE_INSTALLER=%TEMP_DIR%\node-installer.msi"
set "NODE_VER=20.18.0"
set "NODE_DL_MAIN=https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-x64.msi"
set "NODE_DL_CN=https://npmmirror.com/mirrors/node/v%NODE_VER%/node-v%NODE_VER%-x64.msi"

if "!USE_CHINA!"=="1" (
    call :sub_download "!NODE_DL_CN!" "%NODE_INSTALLER%"
    if "!DL_OK!"=="0" call :sub_download "!NODE_DL_MAIN!" "%NODE_INSTALLER%"
) else (
    call :sub_download "!NODE_DL_MAIN!" "%NODE_INSTALLER%"
    if "!DL_OK!"=="0" call :sub_download "!NODE_DL_CN!" "%NODE_INSTALLER%"
)

if not exist "%NODE_INSTALLER%" (
    echo   [FAIL] Node.js download failed
    goto :eof
)

:: Verify file size
set "NODE_SIZE_OK=0"
for %%A in ("%NODE_INSTALLER%") do (
    if %%~zA GTR 5000000 set "NODE_SIZE_OK=1"
)
if "!NODE_SIZE_OK!"=="0" (
    echo   [FAIL] Downloaded file too small, likely corrupt
    del "%NODE_INSTALLER%" 2>nul
    goto :eof
)

echo   [OK] Download complete
echo.
echo   Installing silently (may take 1-2 minutes)...
echo   If a security prompt appears, please click YES
echo.

if "!IS_ADMIN!"=="1" (
    msiexec /i "%NODE_INSTALLER%" /qn /norestart 2>nul
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process msiexec.exe -ArgumentList '/i','%NODE_INSTALLER%','/qn','/norestart' -Verb RunAs -Wait" 2>nul
)

timeout /t 8 /nobreak >nul 2>&1
del "%NODE_INSTALLER%" 2>nul
goto :eof


:: =============================================
:sub_download
:: %1 = URL, %2 = save path
:: Sets DL_OK=1 on success, DL_OK=0 on fail
:: =============================================
set "DL_OK=0"
set "DL_URL=%~1"
set "DL_DST=%~2"

:: Method A: curl
where curl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    curl -fSL --connect-timeout 15 --max-time 300 --progress-bar -o "%DL_DST%" "%DL_URL%" 2>nul
    if !ERRORLEVEL! equ 0 (
        if exist "%DL_DST%" (
            set "DL_FSIZE=0"
            for %%A in ("%DL_DST%") do set "DL_FSIZE=%%~zA"
            if !DL_FSIZE! GTR 100 (
                set "DL_OK=1"
                goto :eof
            )
        )
    )
)

:: Method B: PowerShell
echo   Fallback: PowerShell download...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$ProgressPreference='SilentlyContinue';try{Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_DST%' -UseBasicParsing -TimeoutSec 300}catch{exit 1}" 2>nul
if !ERRORLEVEL! equ 0 (
    if exist "%DL_DST%" (
        set "DL_FSIZE=0"
        for %%A in ("%DL_DST%") do set "DL_FSIZE=%%~zA"
        if !DL_FSIZE! GTR 100 (
            set "DL_OK=1"
            goto :eof
        )
    )
)

:: Method C: bitsadmin
bitsadmin /transfer "ksilly_dl" /download /priority foreground "%DL_URL%" "%DL_DST%" >nul 2>&1
if !ERRORLEVEL! equ 0 (
    if exist "%DL_DST%" (
        set "DL_FSIZE=0"
        for %%A in ("%DL_DST%") do set "DL_FSIZE=%%~zA"
        if !DL_FSIZE! GTR 100 (
            set "DL_OK=1"
            goto :eof
        )
    )
)
goto :eof


:: =============================================
:sub_refresh_path
:: Reload PATH from registry without restarting
:: =============================================
set "NEW_SYS_PATH="
set "NEW_USR_PATH="

for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do (
    set "NEW_SYS_PATH=%%b"
)
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do (
    set "NEW_USR_PATH=%%b"
)

if defined NEW_SYS_PATH (
    if defined NEW_USR_PATH (
        set "PATH=!NEW_SYS_PATH!;!NEW_USR_PATH!"
    ) else (
        set "PATH=!NEW_SYS_PATH!"
    )
)

:: Ensure common tool paths are included
set "EXTRA_1=%ProgramFiles%\Git\cmd"
set "EXTRA_2=%ProgramFiles%\Git\bin"
set "EXTRA_3=%ProgramFiles%\nodejs"
set "EXTRA_4=%LOCALAPPDATA%\Programs\Git\cmd"
set "EXTRA_5=%LOCALAPPDATA%\Programs\Git\bin"
set "EXTRA_6=%APPDATA%\npm"

for %%n in (1 2 3 4 5 6) do (
    if exist "!EXTRA_%%n!" (
        echo "!PATH!" | findstr /i /c:"!EXTRA_%%n!" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            set "PATH=!EXTRA_%%n!;!PATH!"
        )
    )
)
goto :eof


:: =============================================
:cleanup
:: =============================================
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" 2>nul
endlocal
exit /b 0
