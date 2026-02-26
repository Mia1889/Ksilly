@echo off
:: ============================================================
::  Ksilly v2.0.0 - SillyTavern Windows 全自动部署启动器
::  自动安装 Git / Node.js / 运行 ksilly.sh
::  仓库: https://github.com/Mia1889/Ksilly
:: ============================================================
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

title Ksilly v%VER% - SillyTavern 部署
cls

:: ─────────────────────────────────────────
:: Banner
:: ─────────────────────────────────────────
echo.
echo   ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
echo   ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
echo   █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
echo   ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
echo   ██║  ██╗███████║██║███████╗███████╗██║
echo   ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
echo.
echo   SillyTavern 全自动部署 v%VER%  [Windows]
echo   ─────────────────────────────────────────────
echo.

:: ─────────────────────────────────────────
:: 检查管理员权限
:: ─────────────────────────────────────────
net session >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "IS_ADMIN=1"
)

:: ─────────────────────────────────────────
:: 检测网络环境 (中国大陆?)
:: ─────────────────────────────────────────
echo   [0/5] 检测网络环境...
curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "USE_CHINA=1"
        echo   √ 检测到中国大陆网络, 将使用加速通道
    ) else (
        echo   ! 网络连接异常, 将尝试继续
    )
) else (
    echo   √ 国际网络直连
)
echo.

:: ─────────────────────────────────────────
:: 第一步: 检查/安装 Git
:: ─────────────────────────────────────────
echo   [1/5] 检查 Git...
call :find_git
if defined GIT_OK (
    echo   √ Git 已安装
    goto :check_node
)

echo   × 未找到 Git, 正在自动安装...
echo.
call :install_git
if not defined GIT_OK (
    echo.
    echo   ┌──────────────────────────────────────────────┐
    echo   │  Git 自动安装失败                             │
    echo   │                                              │
    echo   │  请手动安装 Git for Windows:                  │
    echo   │  https://git-scm.com/download/win            │
    echo   │                                              │
    echo   │  安装完成后重新运行本脚本                     │
    echo   └──────────────────────────────────────────────┘
    echo.
    pause
    goto :eof_clean
)

:: ─────────────────────────────────────────
:: 第二步: 检查/安装 Node.js
:: ─────────────────────────────────────────
:check_node
echo.
echo   [2/5] 检查 Node.js...
call :find_node
if defined NODE_OK (
    echo   √ Node.js 已安装
    goto :check_deps_done
)

echo   × 未找到 Node.js (或版本过低^), 正在自动安装...
echo.
call :install_node
if not defined NODE_OK (
    echo.
    echo   ┌──────────────────────────────────────────────┐
    echo   │  Node.js 自动安装失败                         │
    echo   │                                              │
    echo   │  请手动安装 Node.js LTS (≥v18):               │
    echo   │  https://nodejs.org/                         │
    echo   │                                              │
    echo   │  安装完成后重新运行本脚本                     │
    echo   └──────────────────────────────────────────────┘
    echo.
    pause
    goto :eof_clean
)

:check_deps_done

:: ─── 如果新安装了软件需要重启脚本刷新 PATH ───
if "!NEED_RESTART!"=="1" (
    echo.
    echo   ─────────────────────────────────────────────
    echo   √ 依赖安装完成, 正在刷新环境...
    echo   ─────────────────────────────────────────────
    echo.

    :: 刷新 PATH
    call :refresh_path

    :: 再次验证
    call :find_git
    call :find_node

    if not defined GIT_OK (
        echo   ! Git 安装后未生效, 请关闭此窗口重新运行
        pause
        goto :eof_clean
    )
    if not defined NODE_OK (
        echo   ! Node.js 安装后未生效, 请关闭此窗口重新运行
        pause
        goto :eof_clean
    )
    echo   √ 环境验证通过
)

:: 显示检测结果
echo.
echo   ─────────────────────────────────────────────
for /f "tokens=*" %%v in ('git --version 2^>nul') do echo   √ %%v
for /f "tokens=*" %%v in ('node -v 2^>nul') do echo   √ Node.js %%v
for /f "tokens=*" %%v in ('npm -v 2^>nul') do echo   √ npm v%%v
echo   ─────────────────────────────────────────────

:: ─────────────────────────────────────────
:: 第三步: 定位 Bash
:: ─────────────────────────────────────────
echo.
echo   [3/5] 定位 Git Bash...
call :find_bash
if not defined BASH_EXE (
    echo   × 找不到 bash.exe (Git 安装可能不完整)
    echo     请重新安装 Git for Windows 并确保勾选 Git Bash
    pause
    goto :eof_clean
)
echo   √ Git Bash: !BASH_EXE!

:: ─────────────────────────────────────────
:: 第四步: 获取/更新 ksilly.sh
:: ─────────────────────────────────────────
echo.
echo   [4/5] 获取部署脚本...

if not exist "%ST_DIR%" mkdir "%ST_DIR%" 2>nul

set "SH_FILE=%ST_DIR%\ksilly.sh"
set "SH_TMP=%ST_DIR%\ksilly.sh.tmp"
set "GOT_NEW=0"

:: 根据网络环境选择下载源
if "!USE_CHINA!"=="1" (
    :: 中国: 先代理后直连
    call :download_file "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"

    if "!GOT_NEW!"=="0" (
        call :download_file "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
) else (
    :: 国际: 先直连后代理
    call :download_file "%REPO_RAW%/ksilly.sh" "%SH_TMP%"
    if "!DL_OK!"=="1" set "GOT_NEW=1"

    if "!GOT_NEW!"=="0" (
        call :download_file "%PROXY%%REPO_RAW%/ksilly.sh" "%SH_TMP%"
        if "!DL_OK!"=="1" set "GOT_NEW=1"
    )
)

if "!GOT_NEW!"=="1" (
    move /y "%SH_TMP%" "%SH_FILE%" >nul 2>&1
    echo   √ 脚本已更新
) else (
    del "%SH_TMP%" 2>nul
    if exist "%SH_FILE%" (
        echo   ! 下载失败, 使用本地缓存版本
    ) else (
        echo   × 获取脚本失败且无本地缓存, 请检查网络
        pause
        goto :eof_clean
    )
)

:: ─── 保存 BAT 自身 ───
set "BAT_DEST=%ST_DIR%\ksilly.bat"
if not "%~f0"=="%BAT_DEST%" (
    copy /y "%~f0" "%BAT_DEST%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   √ 启动器已保存: %BAT_DEST%
        echo     下次可直接双击运行
    )
)

:: ─────────────────────────────────────────
:: 第五步: 运行脚本
:: ─────────────────────────────────────────
echo.
echo   [5/5] 启动 Ksilly...
echo   ─────────────────────────────────────────────
echo.

:: Windows 路径转 Unix 路径
set "SH_UNIX=%SH_FILE:\=/%"

:: 收集参数
set "PASS_ARGS="
if not "%~1"=="" set "PASS_ARGS=%*"

:: 启动 Git Bash
if defined PASS_ARGS (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%' !PASS_ARGS!"
) else (
    "!BASH_EXE!" --login -c "bash '%SH_UNIX%'"
)

set "EC=!ERRORLEVEL!"
if !EC! neq 0 (
    echo.
    echo   脚本退出代码: !EC!
)
echo.
echo   按任意键关闭窗口...
pause >nul
goto :eof_clean


:: ╔════════════════════════════════════════════╗
:: ║            子 程 序 区 域                   ║
:: ╚════════════════════════════════════════════╝

:: ─────────────────────────────────────────
:: find_git - 查找 Git
:: 设置 GIT_OK=1 如果找到
:: ─────────────────────────────────────────
:find_git
set "GIT_OK="
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set "GIT_OK=1"
    goto :eof
)
:: 检查常见安装路径
for %%p in (
    "%ProgramFiles%\Git\cmd\git.exe"
    "%ProgramFiles(x86)%\Git\cmd\git.exe"
    "%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
    "%USERPROFILE%\scoop\apps\git\current\cmd\git.exe"
    "C:\Git\cmd\git.exe"
) do (
    if exist "%%~p" (
        :: 加入 PATH
        for %%d in ("%%~dp") do set "PATH=%%~d;!PATH!"
        set "GIT_OK=1"
        goto :eof
    )
)
goto :eof

:: ─────────────────────────────────────────
:: find_node - 查找 Node.js (≥v18)
:: 设置 NODE_OK=1 如果找到且版本符合
:: ─────────────────────────────────────────
:find_node
set "NODE_OK="
where node.exe >nul 2>&1
if !ERRORLEVEL! neq 0 (
    :: 检查常见安装路径
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
            goto :check_node_ver
        )
    )
    goto :eof
)
:check_node_ver
:: 获取主版本号并检查 ≥ 18
for /f "tokens=1 delims=." %%a in ('node -v 2^>nul') do (
    set "NVER=%%a"
    set "NVER=!NVER:v=!"
    if !NVER! GEQ 18 (
        set "NODE_OK=1"
    ) else (
        echo   ! 当前 Node.js v!NVER! 版本过低, 需要 ≥v18
    )
)
goto :eof

:: ─────────────────────────────────────────
:: find_bash - 查找 bash.exe (Git Bash)
:: 设置 BASH_EXE=<路径>
:: ─────────────────────────────────────────
:find_bash
set "BASH_EXE="
:: 从 git.exe 位置推算 bash.exe
where git.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "tokens=* usebackq" %%i in (`where git.exe`) do (
        set "GIT_PATH=%%~dpi"
        :: git.exe 在 cmd/, bash.exe 在 ../bin/
        if exist "!GIT_PATH!..\bin\bash.exe" (
            set "BASH_EXE=!GIT_PATH!..\bin\bash.exe"
            goto :eof
        )
        :: 或者同目录
        if exist "!GIT_PATH!bash.exe" (
            set "BASH_EXE=!GIT_PATH!bash.exe"
            goto :eof
        )
    )
)
:: 常见路径搜索
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

:: ─────────────────────────────────────────
:: install_git - 自动安装 Git
:: ─────────────────────────────────────────
:install_git
echo   ─────────────────────────────────────────────
echo   正在安装 Git for Windows...
echo   ─────────────────────────────────────────────

:: 方法1: winget (Windows 10 21H2+ / Windows 11)
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   尝试通过 winget 安装...
    winget install --id Git.Git --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        call :refresh_path
        call :find_git
        if defined GIT_OK (
            echo   √ Git 通过 winget 安装成功
            set "NEED_RESTART=1"
            goto :eof
        )
    )
    echo   ! winget 安装未成功, 尝试其他方式...
)

:: 方法2: 下载安装包 (静默安装)
echo   正在下载 Git 安装包...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "GIT_INSTALLER=%TEMP_DIR%\git-installer.exe"

:: 获取最新版下载链接 (64位)
set "GIT_URL=https://github.com/git-for-windows/git/releases/latest/download/Git-2.49.0-64-bit.exe"

if "!USE_CHINA!"=="1" (
    set "GIT_DL_URL=%PROXY%!GIT_URL!"
) else (
    set "GIT_DL_URL=!GIT_URL!"
)

call :download_file "!GIT_DL_URL!" "%GIT_INSTALLER%"
if "!DL_OK!"=="0" (
    :: 尝试另一个源
    if "!USE_CHINA!"=="1" (
        call :download_file "https://registry.npmmirror.com/-/binary/git-for-windows/v2.49.0.windows.1/Git-2.49.0-64-bit.exe" "%GIT_INSTALLER%"
    ) else (
        call :download_file "%PROXY%!GIT_URL!" "%GIT_INSTALLER%"
    )
)

if exist "%GIT_INSTALLER%" (
    for %%A in ("%GIT_INSTALLER%") do (
        if %%~zA GTR 5000000 (
            echo   √ 下载完成, 正在静默安装 (可能需要1-2分钟^)...
            echo.
            echo   ┌─────────────────────────────────────────────┐
            echo   │  Git 正在后台安装中, 请勿关闭此窗口...      │
            echo   │  如弹出安全提示请点击"是"                   │
            echo   └─────────────────────────────────────────────┘
            echo.

            :: 静默安装参数
            "%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" 2>nul
            set "GIT_EXIT=!ERRORLEVEL!"

            :: 等待安装完成
            timeout /t 5 /nobreak >nul 2>&1

            call :refresh_path
            call :find_git
            if defined GIT_OK (
                echo   √ Git 安装成功
                set "NEED_RESTART=1"
                del "%GIT_INSTALLER%" 2>nul
                goto :eof
            ) else (
                echo   ! 安装程序已执行但 Git 未检测到
                echo     可能需要重启终端
            )
        ) else (
            echo   ! 下载的文件过小, 可能不完整
        )
    )
) else (
    echo   ! Git 安装包下载失败
)

del "%GIT_INSTALLER%" 2>nul
goto :eof

:: ─────────────────────────────────────────
:: install_node - 自动安装 Node.js
:: ─────────────────────────────────────────
:install_node
echo   ─────────────────────────────────────────────
echo   正在安装 Node.js LTS...
echo   ─────────────────────────────────────────────

:: 方法1: winget
where winget.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    echo   尝试通过 winget 安装...
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e --silent 2>nul
    if !ERRORLEVEL! equ 0 (
        call :refresh_path
        call :find_node
        if defined NODE_OK (
            echo   √ Node.js 通过 winget 安装成功
            set "NEED_RESTART=1"
            goto :eof
        )
    )
    echo   ! winget 安装未成功, 尝试其他方式...
)

:: 方法2: 下载 MSI 安装包
echo   正在下载 Node.js 安装包...
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%" 2>nul
set "NODE_INSTALLER=%TEMP_DIR%\node-installer.msi"
set "NODE_VER=20.18.0"

:: 选择下载源
if "!USE_CHINA!"=="1" (
    set "NODE_DL=https://npmmirror.com/mirrors/node/v%NODE_VER%/node-v%NODE_VER%-x64.msi"
) else (
    set "NODE_DL=https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-x64.msi"
)

call :download_file "!NODE_DL!" "%NODE_INSTALLER%"

:: 备用源
if "!DL_OK!"=="0" (
    if "!USE_CHINA!"=="1" (
        call :download_file "https://nodejs.org/dist/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    ) else (
        call :download_file "https://npmmirror.com/mirrors/node/v%NODE_VER%/node-v%NODE_VER%-x64.msi" "%NODE_INSTALLER%"
    )
)

if exist "%NODE_INSTALLER%" (
    for %%A in ("%NODE_INSTALLER%") do (
        if %%~zA GTR 5000000 (
            echo   √ 下载完成, 正在静默安装 (可能需要1-2分钟^)...
            echo.
            echo   ┌─────────────────────────────────────────────┐
            echo   │  Node.js 正在后台安装中, 请勿关闭此窗口...  │
            echo   │  如弹出安全提示请点击"是"                   │
            echo   └─────────────────────────────────────────────┘
            echo.

            :: MSI 静默安装
            if "!IS_ADMIN!"=="1" (
                msiexec /i "%NODE_INSTALLER%" /qn /norestart 2>nul
            ) else (
                :: 尝试通过 PowerShell 提权安装
                powershell -NoProfile -ExecutionPolicy Bypass -Command ^
                    "Start-Process msiexec.exe -ArgumentList '/i','%NODE_INSTALLER%','/qn','/norestart' -Verb RunAs -Wait" 2>nul
            )

            :: 等待安装完成
            timeout /t 8 /nobreak >nul 2>&1

            call :refresh_path
            call :find_node
            if defined NODE_OK (
                echo   √ Node.js 安装成功
                set "NEED_RESTART=1"
                del "%NODE_INSTALLER%" 2>nul
                goto :eof
            ) else (
                echo   ! 安装程序已执行但 Node.js 未检测到
                echo     可能需要重启终端
            )
        ) else (
            echo   ! 下载的文件过小, 可能不完整
        )
    )
) else (
    echo   ! Node.js 安装包下载失败
)

del "%NODE_INSTALLER%" 2>nul
goto :eof

:: ─────────────────────────────────────────
:: download_file - 通用下载函数
:: 参数: %1=URL  %2=保存路径
:: 设置: DL_OK=1 成功, DL_OK=0 失败
:: ─────────────────────────────────────────
:download_file
set "DL_OK=0"
set "DL_URL=%~1"
set "DL_PATH=%~2"

:: 方法A: curl (Win10 1803+ 自带)
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

:: 方法B: PowerShell
echo   使用 PowerShell 下载...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$ProgressPreference='SilentlyContinue';try{Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%DL_PATH%' -UseBasicParsing -TimeoutSec 300}catch{exit 1}" 2>nul
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

:: 方法C: bitsadmin (兜底)
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

:: ─────────────────────────────────────────
:: refresh_path - 刷新 PATH 环境变量
:: 从注册表重新读取, 不需要重启终端
:: ─────────────────────────────────────────
:refresh_path
:: 从注册表读取系统 PATH 和用户 PATH
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

:: 确保常见路径在 PATH 中
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
:: 清理临时目录
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" 2>nul
endlocal
exit /b 0
