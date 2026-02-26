@echo off
:: ============================================================
::  Ksilly v2.0.0 - SillyTavern Windows 启动器
::  自动检测 Git Bash / WSL 并运行 ksilly.sh
::  仓库: https://github.com/Mia1889/Ksilly
:: ============================================================
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "VER=2.0.0"
set "REPO_RAW=https://raw.githubusercontent.com/Mia1889/Ksilly/main"
set "PROXY=https://ghfast.top/"
set "ST_DIR=%USERPROFILE%\SillyTavern"

title Ksilly v%VER%
cls
echo.
echo   ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
echo   ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
echo   █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
echo   ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
echo   ██║  ██╗███████║██║███████╗███████╗██║
echo   ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
echo.
echo   SillyTavern 部署脚本 v%VER%  [Windows]
echo   ───────────────────────────────────────────
echo.

:: ─────────────────────────────────────────
:: 第一步: 查找 Bash 环境
:: ─────────────────────────────────────────
echo   [1/3] 检测运行环境...

set "BASH_EXE="

:: Git Bash 常见安装路径
for %%p in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    "%USERPROFILE%\AppData\Local\Programs\Git\bin\bash.exe"
    "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
    "C:\Git\bin\bash.exe"
) do (
    if exist "%%~p" (
        set "BASH_EXE=%%~p"
        goto :found_bash
    )
)

:: 从系统 PATH 查找 (排除 System32 下的 WSL bash)
for /f "tokens=* usebackq" %%i in (`where bash.exe 2^>nul`) do (
    echo "%%i" | findstr /i "System32" >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        set "BASH_EXE=%%i"
        goto :found_bash
    )
)

:: ─── 没有 Git Bash, 尝试 WSL ───
where wsl.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   ^! 未找到 Git Bash, 检测到 WSL
    echo   ^! SillyTavern 将安装在 WSL 环境内
    echo.
    echo   正在启动 WSL...
    echo.
    wsl -- bash -c "tmpf=\"/tmp/ksilly_$$.sh\"; curl -fsSL '%REPO_RAW%/ksilly.sh' -o \"$tmpf\" 2>/dev/null || curl -fsSL '%PROXY%%REPO_RAW%/ksilly.sh' -o \"$tmpf\" 2>/dev/null; if [ -s \"$tmpf\" ]; then bash \"$tmpf\"; else echo '下载失败'; fi; rm -f \"$tmpf\""
    if !ERRORLEVEL! neq 0 (
        echo.
        echo   WSL 运行出错, 请确认 WSL 已正确安装
        pause
    )
    goto :eof_clean
)

:: ─── 什么都没有 ───
echo.
echo   ┌─────────────────────────────────────────────┐
echo   │         未找到 Git Bash 或 WSL               │
echo   ├─────────────────────────────────────────────┤
echo   │                                             │
echo   │  请安装 Git for Windows:                    │
echo   │                                             │
echo   │    https://git-scm.com/download/win         │
echo   │                                             │
echo   │  安装时请确保勾选:                          │
echo   │    [√] Git Bash Here                        │
echo   │    [√] Use Git from Windows Command Line    │
echo   │                                             │
echo   │  安装完成后重新运行本文件即可               │
echo   └─────────────────────────────────────────────┘
echo.
pause
goto :eof_clean

:found_bash
echo   √ Git Bash: %BASH_EXE%

:: ─────────────────────────────────────────
:: 第二步: 获取脚本
:: ─────────────────────────────────────────
echo   [2/3] 获取部署脚本...

if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.tmp"
set "GOT_NEW=0"

:: ── 尝试下载最新版 ──

:: 方法 A: curl 直连 (Win10+ 自带 curl)
curl -fsSL --connect-timeout 8 --max-time 30 "%REPO_RAW%/ksilly.sh" -o "%SH_TMP%" 2>nul
if !ERRORLEVEL! equ 0 (
    for %%A in ("%SH_TMP%") do if %%~zA GTR 1000 (
        move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
        set "GOT_NEW=1"
        echo   √ 已获取最新脚本
    )
)

:: 方法 B: curl 代理
if "!GOT_NEW!"=="0" (
    echo   ^! 直连失败, 尝试加速通道...
    curl -fsSL --connect-timeout 8 --max-time 30 "%PROXY%%REPO_RAW%/ksilly.sh" -o "%SH_TMP%" 2>nul
    if !ERRORLEVEL! equ 0 (
        for %%A in ("%SH_TMP%") do if %%~zA GTR 1000 (
            move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
            set "GOT_NEW=1"
            echo   √ 已获取最新脚本 (加速)
        )
    )
)

:: 方法 C: PowerShell 兜底
if "!GOT_NEW!"=="0" (
    echo   ^! curl 失败, 尝试 PowerShell...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$urls=@('%REPO_RAW%/ksilly.sh','%PROXY%%REPO_RAW%/ksilly.sh');foreach($u in $urls){try{(New-Object Net.WebClient).DownloadFile($u,'%SH_TMP%');break}catch{}}" 2>nul
    if exist "%SH_TMP%" (
        for %%A in ("%SH_TMP%") do if %%~zA GTR 1000 (
            move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
            set "GOT_NEW=1"
            echo   √ 已获取最新脚本 (PowerShell)
        )
    )
)

:: 清理临时文件
del "%SH_TMP%" 2>nul

:: 最终检查
if not exist "%SH_FILE%" (
    echo.
    echo   × 获取脚本失败且无本地缓存
    echo     请检查网络连接后重试
    echo.
    pause
    goto :eof_clean
)

if "!GOT_NEW!"=="0" (
    echo   ^! 下载失败, 使用本地缓存
)

:: ─────────────────────────────────────────
:: 保存 BAT 自身到 SillyTavern 目录
:: ─────────────────────────────────────────
set "BAT_DEST=%ST_DIR%\ksilly.bat"
if not "%~f0"=="%BAT_DEST%" (
    copy /y "%~f0" "%BAT_DEST%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   √ 启动器已保存: %BAT_DEST%
        echo     (下次可直接双击运行^)
    )
)

:: ─────────────────────────────────────────
:: 第三步: 通过 Git Bash 运行
:: ─────────────────────────────────────────
echo   [3/3] 启动 Ksilly...
echo   ───────────────────────────────────────────
echo.

:: 将 Windows 反斜杠路径转为正斜杠 (Git Bash 兼容)
set "SH_UNIX=%SH_FILE:\=/%"

:: 收集传入参数
set "PASS_ARGS="
if not "%~1"=="" (
    set "PASS_ARGS=%*"
)

:: 启动 Git Bash (--login 确保 PATH 包含 node/npm)
if defined PASS_ARGS (
    "%BASH_EXE%" --login -c "bash '%SH_UNIX%' !PASS_ARGS!"
) else (
    "%BASH_EXE%" --login -c "bash '%SH_UNIX%'"
)

:: 脚本退出后
set "EXIT_CODE=!ERRORLEVEL!"
if !EXIT_CODE! neq 0 (
    echo.
    echo   脚本退出代码: !EXIT_CODE!
    pause
)

:eof_clean
endlocal
exit /b 0
