# Ksilly

**简单、快速、一键部署 SillyTavern**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-green.svg)]()
[![Platform](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Termux-lightgrey.svg)]()

一键完成 SillyTavern 的安装、配置、后台运行与日常维护
无需任何技术基础，全程中文交互引导

</div>

---

## ✨ 功能特性

| 功能 | 说明 |
|:---:|------|
| 🚀 **一键安装** | 自动安装 Git、Node.js、npm 等全部依赖，克隆仓库并完成配置 |
| 🌐 **网络自适应** | 自动检测网络环境，中国大陆用户启用 GitHub 代理与 npm 镜像 |
| 📱 **Termux 适配** | 完整支持 Android Termux 环境运行 |
| 🔄 **PM2 后台保活** | 使用 PM2 管理进程，关闭终端也不中断，支持自动重启 |
| 🔒 **安全配置** | 引导式配置监听、白名单、HTTP 基础认证，远程访问更安全 |
| 🛡️ **防火墙管理** | 自动检测 UFW / firewalld / iptables 并放行端口 |
| 📦 **智能更新** | 先检查远端是否有新提交，再由用户决定是否更新，自动备份配置 |
| ⚙️ **配置管理** | 可视化展示当前配置状态，逐项修改，修改后提示重启 |
| 🗑️ **干净卸载** | 一键卸载并清理服务、防火墙规则，可选备份聊天数据 |

---

## 📋 环境要求

| 项目 | 要求 |
|:---:|------|
| **操作系统** | Ubuntu / Debian / CentOS / RHEL / Fedora / Arch / Alpine / macOS / Android (Termux) |
| **Node.js** | v18+ （脚本会自动安装） |
| **网络** | 能访问 GitHub（中国大陆自动走代理） |
| **权限** | Linux 需 root 或 sudo 权限（Termux 除外） |

---

## 🚀 快速开始

### 一键运行

**国际网络：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

**中国大陆加速：**

```bash
bash <(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

### Termux 用户

先安装基础依赖，再运行脚本：

```bash
pkg update && pkg install -y curl
bash <(curl -fsSL https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

> 安装完成后，脚本会自动保存到 `~/SillyTavern/ksilly.sh`，后续维护直接运行：
>
> ```bash
> bash ~/SillyTavern/ksilly.sh
> ```

---

## 📖 使用指南

### 主菜单

运行脚本后进入交互式主菜单：

```
  ● SillyTavern v1.12.x | ~/SillyTavern

  ──────────────────────────────────────────

  安装与管理
    1) 安装 SillyTavern
    2) 更新 SillyTavern
    3) 卸载 SillyTavern

  运行控制
    4) 启动
    5) 停止
    6) 重启
    7) 查看状态

  配置与维护
    8) 修改配置
    9) 后台运行管理 (PM2)

    0) 退出
```

### 命令行模式

也支持直接传参执行，适合脚本调用或 SSH 快捷操作：

```bash
bash ksilly.sh install     # 安装
bash ksilly.sh update      # 更新
bash ksilly.sh start       # 启动
bash ksilly.sh stop        # 停止
bash ksilly.sh restart     # 重启
bash ksilly.sh status      # 查看状态
bash ksilly.sh uninstall   # 卸载
```

---

## ⚙️ 安装流程详解

执行安装后，脚本会依次完成以下步骤：

```
1. 检测运行环境（操作系统 / Termux）
2. 检测网络环境（国际 / 中国大陆）
3. 安装系统依赖（curl、git 等）
4. 安装 Node.js v20.x
5. 克隆 SillyTavern 仓库（可选 release / staging 分支）
6. 安装 npm 依赖
7. 交互式配置向导
   ├── 监听模式（本机 / 远程访问）
   ├── 端口设置
   ├── 白名单模式
   ├── HTTP 基础认证（用户名 + 密码）
   └── 防火墙自动放行
8. PM2 后台运行设置（可选开机自启）
9. 保存管理脚本到安装目录
```

---

## 🔧 配置管理

选择主菜单 `8) 修改配置` 进入配置管理界面：

```
  当前配置
  ──────────────────────────────────────────
    监听模式       开启
    端口           8000
    白名单模式     关闭
    基础认证       开启
    用户账户系统   关闭
    隐蔽登录       关闭
```

支持修改的配置项：

| 配置项 | 说明 |
|--------|------|
| `listen` | 监听模式，开启后允许远程设备访问 |
| `port` | 服务端口号，默认 8000 |
| `whitelistMode` | 白名单模式，开启后仅允许指定 IP 访问 |
| `basicAuthMode` | HTTP 基础认证，访问需输入用户名密码 |
| `enableUserAccounts` | 用户账户系统，可创建多个独立用户 |
| `enableDiscreetLogin` | 隐蔽登录模式，登录页不显示用户信息 |

> **设计理念：** 每项配置修改前会先展示当前状态，由用户确认后再修改；修改后若服务正在运行，会提示是否重启生效。

---

## 🔄 更新机制

选择主菜单 `2) 更新 SillyTavern`：

```
  ▸ 检查更新

    当前版本: 1.12.9
    当前分支: release

  ✓ 连接远程仓库...

  ⚠ 发现 3 个新提交可更新

  ? 是否更新 SillyTavern? (y/n):
```

更新流程：
1. **先检查** — 连接远端仓库，对比本地与远端提交差异
2. **再决定** — 显示有多少个新提交，由用户选择是否更新
3. **自动备份** — 更新前自动备份 `config.yaml`
4. **拉取代码** — 优先快速合并，失败则强制同步
5. **恢复配置** — 更新后自动恢复配置文件

---

## 📱 Termux 说明

Ksilly 完整支持 Android Termux 环境，以下为适配细节：

| 项目 | 适配方式 |
|------|----------|
| 包管理器 | 使用 `pkg` 替代 apt/yum |
| 权限 | 无需 root / sudo |
| 防火墙 | 自动跳过（Termux 无防火墙） |
| 后台运行 | PM2 管理进程 |
| 开机自启 | 通过 Termux:Boot 应用实现 |
| IP 获取 | 适配 Termux 网络接口 |

### Termux 开机自启

开启开机自启需要安装 [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) 应用：

1. 从 F-Droid 安装 Termux:Boot
2. 运行一次 Termux:Boot（初始化）
3. 在 Ksilly 的 PM2 管理菜单中选择"设置开机自启"

---

## 🛡️ PM2 后台管理

选择主菜单 `9) 后台运行管理 (PM2)` 进入管理界面：

```
  PM2 后台运行状态
  ──────────────────────────────────────────
    PM2        已安装 (5.4.3)
    进程状态   ● 运行中
    开机自启   ● 已配置

  1) 安装/更新 PM2
  2) 启动 (PM2 后台)
  3) 停止
  4) 重启
  5) 查看日志
  6) 设置开机自启
  7) 移除开机自启
  8) 从 PM2 中移除进程
```

常用 PM2 命令（也可直接在终端使用）：

```bash
pm2 list                    # 查看所有进程
pm2 logs sillytavern        # 查看实时日志
pm2 restart sillytavern     # 重启
pm2 stop sillytavern        # 停止
```

> 从旧版本升级的用户如果之前使用 systemd 管理服务，脚本会自动检测并提供迁移到 PM2 的选项。

---

## 🌐 访问地址

安装完成或查看状态时，脚本会自动显示所有可用的访问地址：

```
  访问地址:
    本机访问   → http://127.0.0.1:8000
    局域网访问 → http://192.168.1.100:8000
    公网访问   → http://203.0.113.50:8000
```

- **本机访问**：仅在运行 SillyTavern 的设备上可用
- **局域网访问**：同一网络下的其他设备可用（需开启监听）
- **公网访问**：外网设备可用（需开启监听 + 端口放行 + 云服务器安全组放行）

---

## 📁 文件结构

```
~/
├── SillyTavern/             # SillyTavern 安装目录
│   ├── server.js            # 主程序
│   ├── config.yaml          # 用户配置文件
│   ├── default.yaml         # 默认配置模板
│   ├── ksilly.sh            # 管理脚本（自动保存）
│   ├── data/                # 用户数据（聊天记录、角色卡等）
│   └── ...
└── .ksilly.conf             # Ksilly 脚本配置（安装路径、网络环境等）
```

---

## ❓ 常见问题

<details>
<summary><b>Q: 安装时 GitHub 克隆失败</b></summary>

中国大陆用户请使用加速命令安装：

```bash
bash <(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

如果代理也不可用，可以尝试手动设置代理或使用 VPN。

</details>

<details>
<summary><b>Q: 远程设备无法访问</b></summary>

请逐项检查：
1. **监听模式** — 确认已开启（`listen: true`）
2. **白名单** — 建议关闭（`whitelistMode: false`）
3. **防火墙** — 运行脚本的防火墙管理功能放行端口
4. **安全组** — 云服务器用户需在控制台放行对应端口的 TCP 入站规则
5. **IP 地址** — 确认使用的是正确的公网 IP 或局域网 IP

</details>

<details>
<summary><b>Q: 输入密码时屏幕没有反应</b></summary>

这是正常的安全行为。Linux/macOS/Termux 系统在终端输入密码时不会显示任何字符（包括星号），直接输入完成后按回车即可。

</details>

<details>
<summary><b>Q: 如何切换 release 和 staging 分支</b></summary>

目前需要卸载后重新安装并选择不同分支，或手动操作：

```bash
cd ~/SillyTavern
git checkout staging   # 或 release
git pull
npm install
```

</details>

<details>
<summary><b>Q: 如何备份数据</b></summary>

SillyTavern 的用户数据存储在 `data/` 目录下，备份此目录和 `config.yaml` 即可：

```bash
cp -r ~/SillyTavern/data ~/SillyTavern_backup/
cp ~/SillyTavern/config.yaml ~/SillyTavern_backup/
```

卸载时脚本也会询问是否备份数据。

</details>

<details>
<summary><b>Q: Termux 关闭后 SillyTavern 停止了</b></summary>

请确保：
1. 已使用 PM2 后台模式启动（主菜单 → 启动 → 后台运行）
2. 在 Termux 通知栏中点击"Acquire wakelock"保持后台运行
3. 如需开机自启，安装 Termux:Boot 并在 PM2 管理菜单中配置

</details>

<details>
<summary><b>Q: 从旧版 Ksilly 升级</b></summary>

直接运行新版脚本即可，脚本会自动：
- 读取已有的安装配置
- 检测旧版 systemd 服务并提供迁移到 PM2 的选项
- 保留所有用户数据和配置

</details>

---

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源许可。

SillyTavern 本身的许可证请参考 [SillyTavern 官方仓库](https://github.com/SillyTavern/SillyTavern)。

---

<div align="center">

**如果觉得有帮助，请给个 ⭐ Star 支持一下！**

Made with ❤️ by [Mia1889](https://github.com/Mia1889)

</div>
