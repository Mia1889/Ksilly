@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "VER=2.0.0"
set "REPO_RAW=https://raw.githubusercontent.com/Mia1889/Ksilly/main"
set "PROXY=https://ghfast.top/"
set "ST_DIR=%USERPROFILE%\SillyTavern"
set "TEMP_DIR=%TEMP%\ksilly_setup"
set "NEED_RESTART=0"
set "IS_ADMIN=0"
set "USE_CHINA=0"

title Ksilly v%VER%
cls

echo.
echo   =================================================
echo        Ksilly - SillyTavern Deploy Script v%VER%
echo        Platform: Windows
echo   =================================================
echo.

:: =============================================
:: Check admin
:: =============================================
net session >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "IS_ADMIN=1"
)

:: =============================================
:: Detect network
:: =============================================
echo   [0/5] Detecting network...
curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "USE_CHINA=1"
        echo   [OK] China mainland detected, using mirror
    ) else (
        echo   [!!] Network issue, will try to continue
    )
) else (
    echo   [OK] International network
)
echo.

:: =============================================
:: Step 1: Check / Install Git
:: =============================================
echo   [1/5] Checking Git...
call :find_git
if defined GIT_OK (
    for /f "tokens=*" %%v in ('git --version 2^>nul') do echo   [OK] %%v
    goto :step_node
)

echo   [!!] Git not found, installing...
echo.
call :install_git
call :find_git
if not defined GIT_OK (
    echo.
    echo   ==================================================
    echo   Git auto-install failed.
    echo.
    echo   Please install manually:
    echo     https://git-scm.com/download/win
    echo.
    echo   Then re-run this script.
    echo   ==================================================
    echo.
    pause
    goto :eof_clean
)
echo   [OK] Git installed successfully
set "NEED_RESTART=1"

:: =============================================
:: Step 2: Check / Install Node.js
:: =============================================
:step_node
echo.
echo   [2/5] Checking Node.js...
call :find_node
if defined NODE_OK (
    for /f "tokens=*" %%v in ('node -v 2^>nul') do echo   [OK] Node.js %%v
    goto :step_deps_done
)

echo   [!!] Node.js not found or version too low, installing...
echo.
call :install_node
call :refresh_path
call :find_node
if not defined NODE_OK (
    echo.
    echo   ==================================================
    echo   Node.js auto-install failed.
    echo.
    echo   Please install manually (LTS, v18+):
    echo     https://nodejs.org/
    echo.
    echo   Then re-run this script.
    echo   ==================================================
    echo.
    pause
    goto :eof_clean
)
echo   [OK] Node.js installed successfully
set "NEED_RESTART=1"

:step_deps_done

:: =============================================
:: Refresh PATH if new software installed
:: =============================================
if "!NEED_RESTART!"=="1" (
    echo.
    echo   -------------------------------------------------
    echo   [OK] Dependencies installed, refreshing PATH...
    echo   -------------------------------------------------
    echo.
    call :refresh_path
    call :find_git
    call :find_node
    if not defined GIT_OK (
        echo   [!!] Git not detected after install
        echo   Please close this window and re-run ksilly.bat
        pause
        goto :eof_clean
    )
    if not defined NODE_OK (
        echo   [!!] Node.js not detected after install
        echo   Please close this window and re-run ksilly.bat
        pause
        goto :eof_clean
    )
    echo   [OK] All dependencies verified
)

:: Show versions
echo.
echo   -------------------------------------------------
for /f "tokens=*" %%v in ('git --version 2^>nul') do echo   [OK] %%v
for /f "tokens=*" %%v in ('node -v 2^>nul') do echo   [OK] Node.js %%v
for /f "tokens=*" %%v in ('npm -v 2^>nul') do echo   [OK] npm v%%v
echo   -------------------------------------------------

:: =============================================
:: Step 3: Find Git Bash
:: =============================================
echo.
echo   [3/5] Locating Git Bash...
call :find_bash
if not defined BASH_EXE (
    echo   [!!] Cannot find bash.exe
    echo   Git installation may be incomplete.
    echo   Please reinstall Git for Windows with Git Bash.
    pause
    goto :eof_clean
)
echo   [OK] Git Bash: !BASH_EXE!

:: =============================================
:: Step 4: Download ksilly.sh
:: =============================================
echo.
echo   [4/5] Downloading deploy script...

if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.tmp"
set "GOT_NEW=0"

if "!USE_CHINA!"=="1" (
    call :download_file "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :download_file "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
) else (
    call :download_file "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :download_file "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
)

if "!GOT_NEW!"=="1" (
    move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
    echo   [OK] Script downloaded
) else (
    del "%SH_TMP%" 2>nul
    if exist "%SH_FILE%" (
        echo   [!!] Download failed, using cached version
    ) else (
        echo   [!!] Download failed and no cache available
        echo   Please check your network connection
        pause
        goto :eof_clean
    )
)

:: Save this BAT to ST dir
set "BAT_DEST=%ST_DIR%\ksilly.bat"
if not "%~f0"=="%BAT_DEST%" (
    copy /y "%~f0" "%BAT_DEST%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   [OK] Launcher saved: %BAT_DEST%
        echo        You can double-click it next time
    )
)

:: =============================================
:: Step 5: Launch via Git Bash
:: =============================================
echo.
echo   [5/5] Launching Ksilly...
echo   -------------------------------------------------
echo.

set "SH_UNIX=%SH_FILE:\=/%"

set "PASS_ARGS="
if not "%~1"=="" set "PASS_ARGS=%*"

if defined PASS_ARGS (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%' !PASS_ARGS!"
) else (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%'"
)

set "EC=!ERRORLEVEL!"
if !EC! neq 0 (
    echo.
    echo   Script exit code: !EC!
)
echo.
echo   Press any key to close...
pause >nul
goto :eof_clean


:: ========================================================
::                    SUBROUTINES
:: ========================================================

:: --------------------------------------------------------
:: find_git
:: --------------------------------------------------------
:find_git
set "GIT_OK="
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "GIT_OK=1"
    goto :eof
)
for %%p in (
    "%ProgramFiles%\Git\cmd\git.exe"
    "%ProgramFiles(x86)%\Git\cmd\git.exe"
    "%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
    "%USERPROFILE%\scoop\apps\git\current\cmd\git.exe"
    "C:\Git\cmd\git.exe"
) do (
    if exist "%%~p" (
        for %%d in ("%%~dp") do set "PATH=%%~d;!PATH!"
        set "GIT_OK=1"
        goto :eof
    )
)
goto :eof

:: --------------------------------------------------------
:: find_node  (need >= v18)
:: --------------------------------------------------------
:find_node
set "NODE_OK="
where node.exe >nul 2>&1
if !ERRORLEVEL! neq 0 (
    for %%p in (
        "%ProgramFiles%\nodejs\node.exe"
        "%ProgramFiles(x86)%\nodejs\node.exe"
        "%LOCALAPPDATA%\Programs\nodejs\node.exe"
        "%APPDATA%\nvm\current\node.exe"
        "%USERPROFILE%\scoop\apps\nodejs-lts\current\node.exe"
        "%USERPROFILE%\scoop\apps\nodejs\current\node.exe"
    ) do (
        if exist "%%~p" (
            for %%d in ("%%~dp") do set "PATH=%%~d;!PATH!"
            goto :check_nver
        )
    )
    goto :eof
)
:check_nver
for /f "tokens=1 delims=." %%a in ('node -v 2^>nul') do (
    set "NVER=%%a"
    set "NVER=!NVER:v=!"
    if !NVER! GEQ 18 (
        set "NODE_OK=1"
    ) else (
        echo   [!!] Node.js v!NVER! is too old, need v18+
    )
)
goto :eof

:: --------------------------------------------------------
:: find_bash
:: --------------------------------------------------------
:find_bash
set "BASH_EXE="
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "tokens=* usebackq" %%i in (`where git.exe`) do (
        set "GIT_DIR=%%~dpi"
        if exist "!GIT_DIR!..\bin\bash.exe" (
            set "BASH_EXE=!GIT_DIR!..\bin\bash.exe"
            goto :eof
        )
        if exist "!GIT_DIR!bash.exe" (
            set "BASH_EXE=!GIT_DIR!bash.exe"
            goto :eof
        )
    )
)
for %%p in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
    "C:\Git\bin\bash.exe"
) do (
    if exist "%%~p" (
        set "BASH_EXE=%%~p"
        goto :eof
    )
)
goto :eof

:: --------------------------------------------------------
:: install_git
:: --------------------------------------------------------
:install_git
echo   -------------------------------------------------
echo   Installing Git for Windows...
echo   -------------------------------------------------

:: Method 1: winget
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   Trying winget...
    winget install --id Git.Git --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        call :refresh_path
        call :find_git
        if defined GIT_OK (
            echo   [OK] Git installed via winget
            goto :eof
        )
    )
    echo   [!!] winget failed, trying download...
)

:: Method 2: Download installer
echo   Downloading Git installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "GIT_INSTALLER=%TEMP_DIR%\git-installer.exe"
set "GIT_URL=https://github.com/git-for-windows/git/releases/latest/download/Git-2.49.0-64-bit.exe"

if "!USE_CHINA!"=="1" (
    call :download_file "%PROXY%!GIT_URL!" "%GIT_INSTALLER%"
    if "!DL_OK!"=="0" (
        call :download_file "https://registry.npmmirror.com/-/binary/git-for-windows/v2.49.0.windows.1/Git-2.49.0-64-bit.exe" "%GIT_INSTALLER%"
    )
) else (
    call :download_file "!GIT_URL!" "%GIT_INSTALLER%"
    if "!DL_OK!"=="0" (
        call :download_file "%PROXY%!GIT_URL!" "%GIT_INSTALLER%"
    )
)

if not exist "%GIT_INSTALLER%" (
    echo   [!!] Git download failed
    goto :eof
)

for %%A in ("%GIT_INSTALLER%") do (
    if %%~zA LSS 5000000 (
        echo   [!!] Downloaded file too small, may be corrupt
        del "%GIT_INSTALLER%" 2>nul
        goto :eof
    )
)

echo   [OK] Download complete, installing silently...
echo.
echo   Git is installing in background...
echo   If a security prompt appears, click Yes.
echo.

"%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" 2>nul

timeout /t 5 /nobreak >nul 2>&1
call :refresh_path
call :find_git

del "%GIT_INSTALLER%" 2>nul
goto :eof

:: --------------------------------------------------------
:: install_node
:: --------------------------------------------------------
:install_node
echo   -------------------------------------------------
echo   Installing Node.js LTS...
echo   -------------------------------------------------

:: Method 1: winget
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   Trying winget...
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        call :refresh_path
        call :find_node
        if defined NODE_OK (
            echo   [OK] Node.js installed via winget
            goto :eof
        )
    )
    echo   [!!] winget failed, trying download...
)

:: Method 2: Download MSI
echo   Downloading Node.js installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "NODE_INSTALLER=%TEMP_DIR%\node-installer.msi"
set "NODE_VER=20.18.0"

if "!USE_CHINA!"=="1" (
    call :download_file "https://npmmirror.com/mirrors/node/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    if "!DL_OK!"=="0" (
        call :download_file "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    )
) else (
    call :download_file "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    if "!DL_OK!"=="0" (
        call :download_file "https://npmmirror.com/mirrors/node/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    )
)

if not exist "%NODE_INSTALLER%" (
    echo   [!!] Node.js download failed
    goto :eof
)

for %%A in ("%NODE_INSTALLER%") do (
    if %%~zA LSS 5000000 (
        echo   [!!] Downloaded file too small, may be corrupt
        del "%NODE_INSTALLER%" 2>nul
        goto :eof
    )
)

echo   [OK] Download complete, installing silently...
echo.
echo   Node.js is installing in background...
echo   If a security prompt appears, click Yes.
echo.

if "!IS_ADMIN!"=="1" (
    msiexec /i "%NODE_INSTALLER%" /qn /norestart 2>nul
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process msiexec.exe -ArgumentList '/i','%NODE_INSTALLER%','/qn','/norestart' -Verb RunAs -Wait" 2>nul
)

timeout /t 8 /nobreak >nul 2>&1
call :refresh_path
call :find_node

del "%NODE_INSTALLER%" 2>nul
goto :eof

:: --------------------------------------------------------
:: download_file  %1=URL  %2=SavePath
:: Sets DL_OK=1 on success, DL_OK=0 on failure
:: --------------------------------------------------------
:download_file
set "DL_OK=0"
set "DL_URL=%~1"
set "DL_PATH=%~2"

:: Method A: curl
where curl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    curl -fSL --connect-timeout 15 --max-time 300 --progress-bar -o "%DL_PATH%" "%DL_URL%" 2>nul
    if !ERRORLEVEL! equ 0 (
        if exist "%DL_PATH%" (
            for %%A in ("%DL_PATH%") do (
                if %%~zA GTR 100 (
                    set "DL_OK=1"
                    goto :eof
                )
            )
        )
    )
)

:: Method B: PowerShell
echo   Trying PowerShell download...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$ProgressPreference='SilentlyContinue';try{Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_PATH%' -UseBasicParsing -TimeoutSec 300}catch{exit 1}" 2>nul
if !ERRORLEVEL! equ 0 (
    if exist "%DL_PATH%" (
        for %%A in ("%DL_PATH%") do (
            if %%~zA GTR 100 (
                set "DL_OK=1"
                goto :eof
            )
        )
    )
)

:: Method C: bitsadmin
bitsadmin /transfer "ksilly_dl" /download /priority foreground "%DL_URL%" "%DL_PATH%" >nul 2>&1
if !ERRORLEVEL! equ 0 (
    if exist "%DL_PATH%" (
        for %%A in ("%DL_PATH%") do (
            if %%~zA GTR 100 (
                set "DL_OK=1"
                goto :eof
            )
        )
    )
)

goto :eof

:: --------------------------------------------------------
:: refresh_path - Re-read PATH from registry
:: --------------------------------------------------------
:refresh_path
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do (
    set "SYS_PATH=%%b"
)
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do (
    set "USR_PATH=%%b"
)

if defined SYS_PATH (
    if defined USR_PATH (
        set "PATH=!SYS_PATH!;!USR_PATH!"
    ) else (
        set "PATH=!SYS_PATH!"
    )
)

for %%p in (
    "%ProgramFiles%\Git\cmd"
    "%ProgramFiles%\Git\bin"
    "%ProgramFiles%\nodejs"
    "%LOCALAPPDATA%\Programs\Git\cmd"
    "%LOCALAPPDATA%\Programs\Git\bin"
    "%APPDATA%\npm"
) do (
    if exist "%%~p" (
        echo "!PATH!" | findstr /i /c:"%%~p" >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            set "PATH=%%~p;!PATH!"
        )
    )
)
goto :eof


:eof_clean
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" 2>nul
endlocal
exit /b 0
