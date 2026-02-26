@echo off
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
echo   ===================================================
echo    Ksilly v%VER% - SillyTavern Auto Deploy (Windows)
echo   ===================================================
echo.

net session >nul 2>&1
if !ERRORLEVEL! equ 0 set "IS_ADMIN=1"

echo   [0/5] Detecting network...
set "NET_OK=0"
curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "NET_OK=1"
    echo         International network - direct connect
) else (
    curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "USE_CHINA=1"
        set "NET_OK=1"
        echo         China mainland - using mirror
    ) else (
        echo         Network issue - will try anyway
    )
)
echo.

echo   [1/5] Checking Git...
call :find_git
if defined GIT_OK (
    for /f "tokens=*" %%v in ('git --version 2^>nul') do echo         Found: %%v
    goto :step2
)
echo         Not found. Installing...
call :install_git
call :refresh_path
call :find_git
if not defined GIT_OK (
    echo.
    echo   ==================================================
    echo    FAILED: Git auto-install did not succeed.
    echo.
    echo    Please install Git for Windows manually:
    echo      https://git-scm.com/download/win
    echo.
    echo    After installing, re-run this script.
    echo   ==================================================
    pause
    goto :cleanup
)
echo         Git installed OK
set "NEED_RESTART=1"

:step2
echo.
echo   [2/5] Checking Node.js...
call :find_node
if defined NODE_OK (
    for /f "tokens=*" %%v in ('node -v 2^>nul') do echo         Found: Node.js %%v
    goto :step2done
)
echo         Not found or too old. Installing...
call :install_node
call :refresh_path
call :find_node
if not defined NODE_OK (
    echo.
    echo   ==================================================
    echo    FAILED: Node.js auto-install did not succeed.
    echo.
    echo    Please install Node.js LTS (v18+) manually:
    echo      https://nodejs.org/
    echo.
    echo    After installing, re-run this script.
    echo   ==================================================
    pause
    goto :cleanup
)
echo         Node.js installed OK
set "NEED_RESTART=1"

:step2done

if "!NEED_RESTART!"=="1" (
    echo.
    echo   ---------------------------------------------------
    echo    Refreshing environment...
    echo   ---------------------------------------------------
    call :refresh_path
    call :find_git
    call :find_node
    if not defined GIT_OK (
        echo.
        echo    Git not detected. Please close and re-run.
        pause
        goto :cleanup
    )
    if not defined NODE_OK (
        echo.
        echo    Node.js not detected. Please close and re-run.
        pause
        goto :cleanup
    )
)

echo.
echo   ---------------------------------------------------
for /f "tokens=*" %%v in ('git --version 2^>nul') do echo    %%v
for /f "tokens=*" %%v in ('node -v 2^>nul') do echo    Node.js %%v
for /f "tokens=*" %%v in ('npm -v 2^>nul') do echo    npm v%%v
echo   ---------------------------------------------------

echo.
echo   [3/5] Locating Git Bash...
call :find_bash
if not defined BASH_EXE (
    echo         Cannot find bash.exe
    echo         Please reinstall Git for Windows
    pause
    goto :cleanup
)
echo         OK: !BASH_EXE!

echo.
echo   [4/5] Downloading deploy script...
if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.tmp"
set "GOT_NEW=0"

if "!USE_CHINA!"=="1" (
    call :dl "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :dl "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
) else (
    call :dl "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"
    if "!GOT_NEW!"=="0" (
        call :dl "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
)

if "!GOT_NEW!"=="1" (
    move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
    echo         Script updated
) else (
    del "%SH_TMP%" 2>nul
    if exist "%SH_FILE%" (
        echo         Download failed, using cached copy
    ) else (
        echo         Download failed, no cache. Check network.
        pause
        goto :cleanup
    )
)

set "BAT_DEST=%ST_DIR%\ksilly.bat"
if not "%~f0"=="%BAT_DEST%" (
    copy /y "%~f0" "%BAT_DEST%" >nul 2>&1
)

echo.
echo   [5/5] Launching...
echo   ---------------------------------------------------
echo.

set "SH_UNIX=%SH_FILE:\=/%"
set "ARGS="
if not "%~1"=="" set "ARGS=%*"

if defined ARGS (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%' !ARGS!"
) else (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%'"
)

echo.
pause
goto :cleanup


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
    "C:\Git\cmd\git.exe"
) do (
    if exist "%%~p" (
        for %%d in ("%%~dp") do set "PATH=%%~d;!PATH!"
        set "GIT_OK=1"
        goto :eof
    )
)
goto :eof


:find_node
set "NODE_OK="
set "FOUND_NODE=0"
where node.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "FOUND_NODE=1"
    goto :chkver
)
for %%p in (
    "%ProgramFiles%\nodejs\node.exe"
    "%ProgramFiles(x86)%\nodejs\node.exe"
    "%LOCALAPPDATA%\Programs\nodejs\node.exe"
    "%APPDATA%\nvm\current\node.exe"
) do (
    if exist "%%~p" (
        for %%d in ("%%~dp") do set "PATH=%%~d;!PATH!"
        set "FOUND_NODE=1"
        goto :chkver
    )
)
goto :eof
:chkver
for /f "tokens=1 delims=." %%a in ('node -v 2^>nul') do (
    set "NV=%%a"
    set "NV=!NV:v=!"
    if !NV! GEQ 18 set "NODE_OK=1"
)
goto :eof


:find_bash
set "BASH_EXE="
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "tokens=*" %%i in ('where git.exe 2^>nul') do (
        set "GD=%%~dpi"
        if exist "!GD!..\bin\bash.exe" (
            set "BASH_EXE=!GD!..\bin\bash.exe"
            goto :eof
        )
    )
)
for %%p in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    "C:\Git\bin\bash.exe"
) do (
    if exist "%%~p" (
        set "BASH_EXE=%%~p"
        goto :eof
    )
)
goto :eof


:install_git
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo         Trying winget...
    winget install --id Git.Git --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    call :refresh_path
    call :find_git
    if defined GIT_OK goto :eof
)
echo         Downloading Git installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "GI=%TEMP_DIR%\git-setup.exe"
set "GU=https://github.com/git-for-windows/git/releases/latest/download/Git-2.49.0-64-bit.exe"
if "!USE_CHINA!"=="1" (
    call :dl "%PROXY%!GU!" "%GI%"
    if "!DL_OK!"=="0" call :dl "https://registry.npmmirror.com/-/binary/git-for-windows/v2.49.0.windows.1/Git-2.49.0-64-bit.exe" "%GI%"
) else (
    call :dl "!GU!" "%GI%"
    if "!DL_OK!"=="0" call :dl "%PROXY%!GU!" "%GI%"
)
if not exist "%GI%" goto :eof
for %%A in ("%GI%") do if %%~zA LSS 5000000 (del "%GI%" 2>nul & goto :eof)
echo         Installing silently (1-2 min)...
"%GI%" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" 2>nul
timeout /t 5 /nobreak >nul 2>&1
del "%GI%" 2>nul
call :refresh_path
goto :eof


:install_node
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo         Trying winget...
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    call :refresh_path
    call :find_node
    if defined NODE_OK goto :eof
)
echo         Downloading Node.js installer...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "NI=%TEMP_DIR%\node-setup.msi"
set "NV=20.18.0"
if "!USE_CHINA!"=="1" (
    call :dl "https://npmmirror.com/mirrors/node/v%NV%/node-v%NV%-x64.msi" "%NI%"
    if "!DL_OK!"=="0" call :dl "https://nodejs.org/dist/v%NV%/node-v%NV%-x64.msi" "%NI%"
) else (
    call :dl "https://nodejs.org/dist/v%NV%/node-v%NV%-x64.msi" "%NI%"
    if "!DL_OK!"=="0" call :dl "https://npmmirror.com/mirrors/node/v%NV%/node-v%NV%-x64.msi" "%NI%"
)
if not exist "%NI%" goto :eof
for %%A in ("%NI%") do if %%~zA LSS 5000000 (del "%NI%" 2>nul & goto :eof)
echo         Installing silently (1-2 min)...
if "!IS_ADMIN!"=="1" (
    msiexec /i "%NI%" /qn /norestart 2>nul
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process msiexec.exe -ArgumentList '/i','%NI%','/qn','/norestart' -Verb RunAs -Wait" 2>nul
)
timeout /t 8 /nobreak >nul 2>&1
del "%NI%" 2>nul
call :refresh_path
goto :eof


:dl
set "DL_OK=0"
set "DU=%~1"
set "DP=%~2"
where curl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    curl -fSL --connect-timeout 15 --max-time 300 --progress-bar -o "%DP%" "%DU%" 2>nul
    if !ERRORLEVEL! equ 0 (
        if exist "%DP%" (
            for %%A in ("%DP%") do if %%~zA GTR 100 set "DL_OK=1"
            if "!DL_OK!"=="1" goto :eof
        )
    )
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$ProgressPreference='SilentlyContinue';try{Invoke-WebRequest -Uri '%DU%' -OutFile '%DP%' -UseBasicParsing -TimeoutSec 300}catch{exit 1}" 2>nul
if !ERRORLEVEL! equ 0 (
    if exist "%DP%" (
        for %%A in ("%DP%") do if %%~zA GTR 100 set "DL_OK=1"
        if "!DL_OK!"=="1" goto :eof
    )
)
bitsadmin /transfer "ksilly" /download /priority foreground "%DU%" "%DP%" >nul 2>&1
if exist "%DP%" (
    for %%A in ("%DP%") do if %%~zA GTR 100 set "DL_OK=1"
)
goto :eof


:refresh_path
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SP=%%b"
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "UP=%%b"
if defined SP (
    if defined UP (set "PATH=!SP!;!UP!") else (set "PATH=!SP!")
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
        if !ERRORLEVEL! neq 0 set "PATH=%%~p;!PATH!"
    )
)
goto :eof


:cleanup
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" 2>nul
endlocal
exit /b 0
