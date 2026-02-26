# Ksilly - 简单 SillyTavern 部署脚本

一键傻瓜式部署 [SillyTavern](https://github.com/SillyTavern/SillyTavern)，自动检测网络环境，中国大陆用户自动加速。

## ✨ 功能特性

- 🌐 自动检测网络环境，中国大陆自动启用镜像加速
- 📦 自动安装 Git、Node.js 等依赖
- ⚙️ 交互式引导配置（监听地址、白名单、认证等）
- 🔒 支持 basicAuth 用户名密码认证
- 🚀 支持 systemd 后台运行和开机自启动
- 🛠️ 内置 `ksilly` 管理命令
- 🖥️ 支持 Ubuntu / Debian / CentOS / Fedora / Arch / Alpine

## 🚀 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh | sudo bash
