# 🎭 Ksilly - 简单 SillyTavern 部署脚本

一键部署、管理 [SillyTavern](https://github.com/SillyTavern/SillyTavern) 的傻瓜式脚本。

自动处理依赖安装、网络加速、配置引导、后台运行等所有烦人的事情。

![Shell Script](https://img.shields.io/badge/Shell-Bash-green)
![License](https://img.shields.io/badge/License-MIT-blue)

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| 🌐 智能网络检测 | 自动识别中国大陆网络环境，启用 GitHub 代理和 npm 镜像加速 |
| 📦 自动装依赖 | 自动安装 Git、Node.js 等所有依赖，支持多种 Linux 发行版 |
| 🧙 配置引导 | 交互式引导监听、白名单、认证等全部配置，不做任何默认假设 |
| 🔄 后台运行 | 可选 systemd 服务化，支持开机自启动 |
| 🛠 后期维护 | 更新、卸载、配置修改、日志查看，一站式管理 |
| 💾 安全卸载 | 卸载前询问数据备份，二次确认防止误操作 |

## 📋 支持的系统

- Ubuntu / Debian / Linux Mint
- CentOS / RHEL / Rocky / AlmaLinux
- Fedora
- Arch Linux / Manjaro
- Alpine Linux
- macOS (基本支持)

## 🚀 快速开始

### 一键运行
```
bash <(curl -fsSL https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```

大陆用户
```
bash <(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh)
```
