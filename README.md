# Ksilly

**SillyTavern 一键部署管理脚本**

[![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20|%20macOS%20|%20Termux-blue)](https://github.com/Mia1889/Ksilly)
[![Version](https://img.shields.io/badge/Version-2.2.3-purple)](https://github.com/Mia1889/Ksilly)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

一条命令完成 SillyTavern 的安装、配置、HTTPS、插件管理、后台运行与更新

</div>

---

## ✨ 功能特性

| 类别 | 功能 |
|:----:|------|
| 🚀 | **一键安装** — 自动安装 Node.js、Git 等全部依赖，克隆仓库并完成配置 |
| 🔒 | **HTTPS 支持** — 通过 Caddy 反代实现 HTTPS，支持 Let's Encrypt 自动证书或自签证书 |
| 🧩 | **插件管理** — 内置常用插件一键安装 / 更新 / 卸载，自动适配国内外网络源 |
| 🌏 | **国内加速** — 自动检测网络环境，大陆用户自动启用 GitHub 代理 + npm 镜像 |
| 📱 | **多平台支持** — Linux 服务器 / macOS / Android Termux 全覆盖 |
| 🔧 | **交互式配置** — 引导式设置监听、端口、认证、白名单、多账户等选项 |
| 🔄 | **PM2 后台运行** — 关闭终端不中断，崩溃自动重启，支持开机自启 |
| 🛡️ | **防火墙管理** — 自动识别并放行 UFW / firewalld / iptables 端口 |
| 📦 | **一键更新** — 自动备份配置，拉取最新代码，更新依赖后恢复配置 |
| 🗑️ | **完整卸载** — 停止进程、清理服务与 HTTPS 配置、可选备份数据，干净彻底 |

---

## 📋 环境要求

| 平台 | 要求 |
|------|------|
| **Linux** | Debian / Ubuntu / CentOS / RHEL / Arch / Alpine 等主流发行版 |
| **macOS** | 需要 Homebrew |
| **Termux** | Android 7.0+，建议安装 Termux:Boot（用于开机自启） |

> 脚本会自动安装 Node.js (≥18)、Git、PM2 等依赖，无需提前准备

---

## 🚀 快速开始

### 一键运行

**国内网络（使用加速镜像）：**

```bash
curl -O https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh && chmod +x ksilly.sh && ./ksilly.sh
```

**国际网络（直连 GitHub）：**

```bash
curl -O https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh && chmod +x ksilly.sh && ./ksilly.sh
```

> Linux 和 Termux 使用相同的命令，脚本会自动识别运行环境

### 命令行模式

安装完成后也可以直接通过参数调用：

```bash
bash ksilly.sh install     # 安装
bash ksilly.sh start       # 启动
bash ksilly.sh stop        # 停止
bash ksilly.sh restart     # 重启
bash ksilly.sh status      # 查看状态
bash ksilly.sh update      # 更新
bash ksilly.sh plugins     # 插件管理
bash ksilly.sh https       # HTTPS 管理
bash ksilly.sh uninstall   # 卸载
```

不带参数则进入交互式菜单。

---

## 📖 使用说明

### 主菜单

```
  安装与管理
     1) 安装
     2) 更新
     3) 卸载

  运行控制
     4) 启动
     5) 停止
     6) 重启
     7) 查看状态

  配置与维护
     8) 修改配置
     9) 后台运行管理 (PM2)
    10) 插件管理
    11) HTTPS 管理 (Caddy)

     0) 退出
```

### 安装流程

执行安装后，脚本会依次完成：

1. **环境检测** — 识别操作系统和包管理器
2. **网络检测** — 判断是否需要使用国内加速镜像
3. **依赖安装** — 自动安装 Git、Node.js 等
4. **克隆仓库** — 可选 `release`（稳定版）或 `staging`（开发版）
5. **配置向导** — 交互式设置监听、端口、认证等
6. **HTTPS 配置** — 开启公网监听时可选配置 HTTPS（Caddy 反代）
7. **插件安装** — 可选安装推荐插件（全部安装 / 逐个选择 / 跳过）
8. **后台运行** — 可选配置 PM2 后台运行和开机自启

### 配置管理

通过菜单 `8) 修改配置` 可随时调整：

| 选项 | 说明 |
|------|------|
| 监听模式 | 开启后允许局域网 / 外网设备访问 |
| 端口 | 默认 8000，可自定义 |
| 白名单模式 | 限制仅白名单 IP 可访问 |
| 基础认证 | HTTP 用户名 / 密码认证 |
| 多账户系统 | 多用户独立数据 |
| 隐蔽登录 | 登录页不显示用户信息 |
| HTTPS 管理 | 进入 Caddy / HTTPS 配置子菜单 |

---

## 🔒 HTTPS 管理

通过菜单 `11) HTTPS 管理` 或 `bash ksilly.sh https` 进入。

### 两种证书模式

| 模式 | 适用场景 | 说明 |
|------|----------|------|
| **Let's Encrypt** | 有域名 + 公网服务器 | Caddy 自动申请和续签证书，浏览器无警告 |
| **自签证书** | 无域名 / 内网使用 | 自动生成 10 年有效期证书，浏览器需手动信任 |

### 工作原理

```
客户端 ──HTTPS:443──▶ Caddy (反向代理) ──HTTP:8000──▶ SillyTavern
```

启用 HTTPS 后：
- Caddy 监听 443 端口处理 TLS 加密
- SillyTavern 改为仅本地监听，由 Caddy 反代转发
- 原始 HTTP 端口不再对外暴露

### HTTPS 管理菜单

```
  1) 启用/重新配置 HTTPS
  2) 移除 HTTPS (恢复 HTTP)
  3) 重新生成自签证书
  4) 重启 Caddy
  5) 查看 Caddy 日志
  6) 查看 Caddyfile

  0) 返回
```

> Termux 环境不支持 HTTPS / Caddy 功能

---

## 🧩 插件管理

通过菜单 `10) 插件管理` 进入。

### 收录插件

| 插件 | 说明 | 国际源 | 国内源 |
|------|------|--------|--------|
| **酒馆助手** (JS-Slash-Runner) | 为酒馆提供更强大的脚本运行能力 | [GitHub](https://github.com/N0VI028/JS-Slash-Runner) | [GitLab](https://gitlab.com/novi028/JS-Slash-Runner) |
| **提示词模板** (ST-Prompt-Template) | 提供提示词模板管理功能 | [GitHub](https://github.com/zonde306/ST-Prompt-Template) | [Codeberg](https://codeberg.org/zonde306/ST-Prompt-Template) |

### 插件菜单

```
  安装插件
    1) 安装 酒馆助手
    2) 安装 提示词模板
    3) 全部安装

  更新插件
    4) 更新 酒馆助手
    5) 更新 提示词模板
    6) 全部更新

  卸载插件
    7) 卸载 酒馆助手
    8) 卸载 提示词模板
    9) 全部卸载

    0) 返回主菜单
```

### 网络源选择

脚本会根据网络环境自动选择最佳源：

| 网络环境 | 优先源 | 失败回退 |
|----------|--------|----------|
| 大陆网络 | GitLab / Codeberg 镜像 | GitHub 代理加速 |
| 国际网络 | GitHub 直连 | 镜像源回退 |

> 插件安装 / 更新 / 卸载后，脚本会自动提示重启 SillyTavern 以使变更生效

---

## 🔧 PM2 后台管理

通过菜单 `9) 后台运行管理` 可以：

- 启动 / 停止 / 重启 SillyTavern
- 查看实时日志或历史日志
- 设置 / 移除开机自启
- 管理 PM2 进程

---

## 📱 Termux 使用说明

1. 安装 [Termux](https://f-droid.org/packages/com.termux/)（推荐从 F-Droid 下载）
2. 打开 Termux，粘贴上方安装命令运行
3. 如需开机自启，安装 [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) 并在脚本中配置

> Termux 环境下脚本会自动使用 `pkg` 包管理器，无需 root 权限
>
> HTTPS (Caddy) 功能在 Termux 下不可用

---

## 📁 文件说明

```
~/SillyTavern/                                          # 默认安装目录（可自定义）
├── server.js                                           # SillyTavern 主程序
├── config.yaml                                         # 运行配置
├── default.yaml                                        # 默认配置模板
├── data/                                               # 用户数据（聊天记录、角色卡等）
├── ksilly.sh                                           # 管理脚本副本
├── public/scripts/extensions/third-party/              # 第三方插件目录
│   ├── JS-Slash-Runner/                                # 酒馆助手插件
│   └── ST-Prompt-Template/                             # 提示词模板插件
└── ...

~/.ksilly.conf                                          # Ksilly 脚本配置
/etc/caddy/Caddyfile                                    # Caddy 配置（启用 HTTPS 后）
/etc/caddy/certs/                                       # 自签证书目录（自签模式）
```

---

## ❓ 常见问题

<details>
<summary><b>国内克隆失败 / 下载超时</b></summary>

脚本已内置多个 GitHub 代理自动切换。如仍失败：
- 检查网络连接是否正常
- 尝试更换网络环境（如手机热点）
- 手动设置代理后重试
</details>

<details>
<summary><b>插件安装失败</b></summary>

- 脚本会自动切换国际 / 国内源，两个源都失败时请检查网络
- 确认 SillyTavern 已正确安装且目录结构完整
- 手动检查插件目录是否存在：`ls ~/SillyTavern/public/scripts/extensions/third-party/`
- 也可以手动 `git clone` 到上述目录后重启 SillyTavern
</details>

<details>
<summary><b>插件安装后不生效</b></summary>

- 安装 / 更新 / 卸载插件后需要重启 SillyTavern
- 脚本会自动提示重启，也可以手动通过菜单 `6) 重启` 操作
- 在 SillyTavern 网页端进入 扩展 → 管理扩展 确认插件已加载
</details>

<details>
<summary><b>端口被占用</b></summary>

修改端口号（菜单 8 → 选项 2），或查看占用进程：
```bash
lsof -i :8000
# 或
ss -tlnp | grep 8000
```
</details>

<details>
<summary><b>远程设备无法访问</b></summary>

请确认以下几点：
1. 监听模式已开启（`listen: true`）
2. 白名单模式已关闭（`whitelistMode: false`）
3. 防火墙已放行对应端口
4. **云服务器**需在安全组中放行端口
</details>

<details>
<summary><b>HTTPS 配置后无法访问</b></summary>

- 确认 Caddy 正在运行：通过菜单 `11) HTTPS 管理` 查看状态
- 确认 443 端口已在防火墙和云服务器安全组中放行
- Let's Encrypt 模式需要确保域名已正确解析到服务器公网 IP
- 自签证书模式浏览器会显示安全警告，点击「高级」→「继续访问」即可
- 查看 Caddy 日志排查问题：菜单 `11` → `5) 查看 Caddy 日志`
</details>

<details>
<summary><b>自签证书浏览器显示不安全</b></summary>

这是正常现象。自签证书不被公开 CA 信任，但数据传输仍然是加密的：
- **Chrome**：点击「高级」→「继续前往」
- **Firefox**：点击「高级」→「接受风险并继续」
- **Edge**：点击「详细信息」→「继续转到此网页」

如需消除警告，可配置域名并切换到 Let's Encrypt 模式。
</details>

<details>
<summary><b>Termux 后台被杀</b></summary>

- 在 Android 设置中关闭 Termux 的电池优化
- 安装 Termux:Boot 并在脚本中配置开机自启
- 运行 `termux-wake-lock` 保持后台
</details>

<details>
<summary><b>更新后配置丢失</b></summary>

不会丢失。脚本更新前会自动备份配置到 `~/.ksilly_backup_日期时间/`，更新完成后自动恢复。
</details>

---

## 📄 许可证

[MIT License](LICENSE)

---

<div align="center">

**如果觉得好用，给个 ⭐ Star 吧~**
