# 🎭 Ksilly - 跨平台 SillyTavern 一键部署脚本

一键部署、管理 [SillyTavern](https://github.com/SillyTavern/SillyTavern) 的傻瓜式脚本。

自动处理依赖安装、网络加速、配置引导、后台保活等所有烦人的事情。

![Shell Script](https://img.shields.io/badge/Shell-Bash-green)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20Termux-blue)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/Version-2.0.0-orange)

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| 🖥 跨平台支持 | Linux / macOS / Windows (Git Bash) / Termux / WSL 全平台适配 |
| 🌐 智能网络检测 | 自动识别中国大陆网络，启用 GitHub 代理和 npm 镜像加速 |
| 📦 自动装依赖 | 自动安装 Git、Node.js、PM2 等所有依赖 |
| 🧙 配置引导 | 交互式引导远程访问、认证、端口等配置，不做任何默认假设 |
| 🔄 PM2 后台保活 | 通过 PM2 管理进程，支持开机自启、崩溃自动重启 |
| 🔍 智能更新 | 自动检测是否有新版本，显示更新内容后再由你决定 |
| 🌍 公网 IP 识别 | 准确获取本机、局域网、公网 IP，远程访问地址一目了然 |
| 📝 先看后改 | 所有配置修改前先展示当前状态，再交由你操作 |
| 💾 安全卸载 | 卸载前询问数据备份，二次确认防止误操作 |
| 📌 脚本自保存 | 安装后自动保存脚本到 SillyTavern 目录，后续免下载直接用 |

## 📋 支持的平台

| 平台 | 支持状态 | 备注 |
|------|----------|------|
| Ubuntu / Debian / Mint | ✅ 完整支持 | apt |
| CentOS / RHEL / Rocky / Alma | ✅ 完整支持 | yum / dnf |
| Fedora | ✅ 完整支持 | dnf |
| Arch Linux / Manjaro | ✅ 完整支持 | pacman |
| Alpine Linux | ✅ 完整支持 | apk |
| openSUSE | ✅ 完整支持 | zypper |
| macOS | ✅ 完整支持 | brew |
| Windows | ✅ 支持 | 需要 Git Bash，自动检测 |
| WSL | ✅ 完整支持 | 同 Linux |
| Termux (Android) | ✅ 支持 | pkg |

---

## 🚀 快速开始

### Linux / macOS / Termux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

### Windows（CMD 或 PowerShell）

```cmd
curl -fsSL -o ksilly.bat https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.bat && ksilly.bat
```

> Windows 需要已安装 [Git for Windows](https://git-scm.com/download/win) 和 [Node.js](https://nodejs.org/)
> 安装 Git 时确保勾选 **Git Bash Here**

### 🇨🇳 国内加速

<details>
<summary>点击展开加速命令</summary>

**Linux / macOS / Termux：**

```bash
bash <(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

**Windows：**

```cmd
curl -fsSL -o ksilly.bat https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.bat && ksilly.bat
```

</details>

### 📌 安装后再次使用

安装完成后脚本会自动保存到 SillyTavern 目录，后续无需重新下载：

```bash
# Linux / macOS / Termux
bash ~/SillyTavern/ksilly.sh
```

```cmd
# Windows（或直接双击 ksilly.bat）
%USERPROFILE%\SillyTavern\ksilly.bat
```

---

## 📖 功能说明

### 主菜单

```
  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
  ██║  ██╗███████║██║███████╗███████╗██║
  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝

  跨平台 SillyTavern 部署脚本 v2.0.0  [linux]

  ● 运行中  |  v1.12.x  |  release  |  ~/SillyTavern
  ─────────────────────────────────────────────

  安装与管理
    1)  全新安装
    2)  检查更新
    3)  卸载

  运行控制
    4)  启动
    5)  停止
    6)  重启
    7)  查看状态

  配置与维护
    8)  修改配置
    9)  查看日志
    10) 后台运行/开机自启

  0)  退出
```

### 安装流程

1. **自动检测** 运行平台和网络环境
2. **安装依赖** Git、Node.js（中国大陆自动从 npmmirror 安装）
3. **选择分支** release（稳定版）或 staging（开发版）
4. **交互配置** 远程访问、端口、认证 — 每步都有说明
5. **安装 PM2** 自动安装进程管理器
6. **防火墙放行** 自动检测 UFW / firewalld / iptables 并放行端口
7. **保存脚本** 自动保存到安装目录供后续使用

### 配置管理

所有配置项**先显示当前状态，再让你选择是否修改**：

| 配置项 | 说明 |
|--------|------|
| `listen` | 远程访问（0.0.0.0 / 127.0.0.1） |
| `port` | 端口号 |
| `whitelistMode` | 白名单模式 |
| `basicAuthMode` | 基础认证（用户名/密码） |
| `enableUserAccounts` | 用户账户系统 |
| `enableDiscreetLogin` | 离散登录模式 |

### 更新机制

更新前自动检查是否有新版本，显示落后的提交数和最近更新内容，再由你决定是否更新：

```
  ★ 发现更新!
    分支: release
    落后: 3 个提交

  最近更新内容:
    • a1b2c3d Fix: some bug
    • d4e5f6g Feature: new thing
    • g7h8i9j Update: dependency
```

### 后台保活（PM2）

使用 [PM2](https://pm2.keymetrics.io/) 替代 systemd，实现全平台统一的进程管理：

```bash
pm2 start sillytavern     # 启动
pm2 stop sillytavern      # 停止
pm2 restart sillytavern   # 重启
pm2 logs sillytavern      # 查看日志
pm2 monit                 # 实时监控
```

> PM2 支持 Linux / macOS / Windows / Termux，崩溃自动重启

---

## ⌨️ 命令行参数

支持直接传参跳过菜单：

```bash
bash ksilly.sh install     # 直接安装
bash ksilly.sh update      # 直接更新
bash ksilly.sh start       # 启动
bash ksilly.sh stop        # 停止
bash ksilly.sh restart     # 重启
bash ksilly.sh status      # 查看状态
bash ksilly.sh config      # 修改配置
bash ksilly.sh logs        # 查看日志
bash ksilly.sh uninstall   # 卸载
```

---

## 🔧 常见问题

<details>
<summary><b>Windows 提示"未找到 Git Bash"</b></summary>

请安装 [Git for Windows](https://git-scm.com/download/win)，安装时确保勾选：
- ✅ Git Bash Here
- ✅ Use Git from Windows Command Line

安装完成后重新运行 `ksilly.bat`

</details>

<details>
<summary><b>Windows 提示"未找到 Node.js"</b></summary>

请安装 [Node.js LTS](https://nodejs.org/)（≥v18），安装后重新打开终端运行

</details>

<details>
<summary><b>远程无法访问</b></summary>

1. 确认已开启远程访问（`listen: true`）
2. 确认已关闭白名单（`whitelistMode: false`）
3. 确认防火墙已放行端口（脚本会自动处理）
4. 如果是云服务器，确认**安全组**也放行了对应端口
5. 运行脚本选择「查看状态」确认访问地址

</details>

<details>
<summary><b>输入密码时屏幕没有反应</b></summary>

这是正常现象！Linux/macOS 系统输入密码时不会显示任何字符（包括 `*`），直接输入完按回车即可

</details>

<details>
<summary><b>Termux 开机自启</b></summary>

PM2 在 Termux 中无法自动设置开机自启，你可以：

1. 安装 [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) 应用
2. 创建启动脚本：
   ```bash
   mkdir -p ~/.termux/boot
   echo '#!/data/data/com.termux/files/usr/bin/sh
   pm2 start ~/SillyTavern/server.js --name sillytavern' > ~/.termux/boot/start-st.sh
   chmod +x ~/.termux/boot/start-st.sh
   ```

</details>

<details>
<summary><b>中国大陆网络安装失败</b></summary>

脚本会自动检测并使用加速代理，如果仍然失败：
1. 使用加速命令安装（见上方「国内加速」）
2. 确保能访问 `ghfast.top`
3. 尝试手动设置 npm 镜像：`npm config set registry https://registry.npmmirror.com`

</details>

---

## 📁 文件结构

```
~/SillyTavern/
├── server.js            # SillyTavern 服务端
├── config.yaml          # 配置文件（脚本自动生成）
├── data/                # 用户数据（聊天记录、角色卡等）
├── ksilly.sh            # ← 脚本自动保存，后续直接用
└── ksilly.bat           # ← Windows 启动器（Windows 下自动保存）

~/.ksilly.conf           # Ksilly 配置（安装目录、网络设置）
```

---

## 📜 License

MIT

---

## 🙏 致谢

- [SillyTavern](https://github.com/SillyTavern/SillyTavern) - 本体
- [PM2](https://pm2.keymetrics.io/) - 进程管理
- [ghfast.top](https://ghfast.top/) - GitHub 加速
```
