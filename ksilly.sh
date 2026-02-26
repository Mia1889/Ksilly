#!/bin/bash
#
#  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
#  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
#  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
#  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
#  ██║  ██╗███████║██║███████╗███████╗██║
#  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
#
#  Ksilly - 简单 SillyTavern 部署脚本
#  作者: Mia1889
#  仓库: https://github.com/Mia1889/Ksilly
#  版本: 2.0.0
#  支持: Linux / macOS / Windows(Git Bash) / Termux
#

set -o pipefail

# =====================================================================
#  全局常量
# =====================================================================
SCRIPT_VERSION="2.0.0"
KSILLY_CONF="$HOME/.ksilly.conf"
DEFAULT_INSTALL_DIR="$HOME/SillyTavern"
SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh"
PM2_APP_NAME="SillyTavern"
MIN_NODE_VERSION=18
GITHUB_PROXIES=(
    "https://ghfast.top/"
    "https://gh-proxy.com/"
    "https://mirror.ghproxy.com/"
)

# =====================================================================
#  颜色
# =====================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# =====================================================================
#  全局变量
# =====================================================================
PLATFORM=""          # linux | macos | windows | termux
OS_TYPE=""           # ubuntu | centos | arch | ...
PKG_MANAGER=""       # apt | yum | dnf | pacman | apk | brew | pkg | none
IS_CHINA=false
GITHUB_PROXY=""
INSTALL_DIR=""
CURRENT_USER=$(whoami)
NEED_SUDO=""

# =====================================================================
#  打印工具
# =====================================================================
print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'BANNER'
  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
  ██║  ██╗███████║██║███████╗███████╗██║
  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}SillyTavern 部署管理脚本 v${SCRIPT_VERSION}${NC}  ${DIM}by Mia1889${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✔${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✖${NC} $1"; }
success() { echo -e "  ${GREEN}✔${NC} $1"; }
step()    { echo -e "\n  ${CYAN}▶ $1${NC}"; }

divider() { echo -e "  ${DIM}─────────────────────────────────────────────${NC}"; }

confirm() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO])     return 1 ;;
            *) warn "请输入 y 或 n" ;;
        esac
    done
}

read_input() {
    local prompt="$1" default="${2:-}" result=""
    if [[ -n "$default" ]]; then
        echo -ne "  ${BLUE}▸${NC} ${prompt} ${DIM}[${default}]${NC}: " >&2
    else
        echo -ne "  ${BLUE}▸${NC} ${prompt}: " >&2
    fi
    read -r result
    [[ -z "$result" && -n "$default" ]] && result="$default"
    echo "$result"
}

read_password() {
    local prompt="$1" result=""
    echo -e "  ${DIM}提示: 输入密码时屏幕不会显示任何字符，这是正常的安全行为${NC}" >&2
    while [[ -z "$result" ]]; do
        echo -ne "  ${BLUE}▸${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        [[ -z "$result" ]] && warn "密码不能为空，请重新输入"
    done
    echo "$result"
}

pause() { echo ""; read -rp "  按 Enter 继续..."; }

format_bool() {
    if [[ "${1:-false}" == "true" ]]; then
        echo -e "${GREEN}开启${NC}"
    else
        echo -e "${DIM}关闭${NC}"
    fi
}

# =====================================================================
#  sed 跨平台兼容
# =====================================================================
sed_i() {
    if [[ "$PLATFORM" == "macos" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# =====================================================================
#  YAML 配置读写 (简易)
# =====================================================================
get_yaml_val() {
    local key="$1" file="$2"
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 \
        | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | tr -d '\r\n "'\'''
}

set_yaml_val() {
    local key="$1" value="$2" file="$3"
    if grep -qE "^\s*${key}:" "$file" 2>/dev/null; then
        sed_i "s|^\([[:space:]]*\)${key}:.*|\1${key}: ${value}|" "$file"
    else
        echo "${key}: ${value}" >> "$file"
    fi
}

get_port() {
    local p; p=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml")
    [[ "$p" =~ ^[0-9]+$ ]] && echo "$p" || echo "8000"
}

# =====================================================================
#  平台检测
# =====================================================================
command_exists() { command -v "$1" &>/dev/null; }

detect_platform() {
    local uname_s; uname_s=$(uname -s 2>/dev/null || echo "Unknown")
    case "$uname_s" in
        Linux*)
            if [[ -d /data/data/com.termux ]]; then
                PLATFORM="termux"
            elif grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
                PLATFORM="linux"  # WSL 视为 Linux
            else
                PLATFORM="linux"
            fi
            ;;
        Darwin*)  PLATFORM="macos"   ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *)        PLATFORM="linux"   ;;
    esac
}

detect_os() {
    step "检测系统环境..."

    detect_platform

    case "$PLATFORM" in
        termux)
            OS_TYPE="termux"; PKG_MANAGER="pkg"
            info "平台: Termux (Android)"
            ;;
        windows)
            OS_TYPE="windows"; PKG_MANAGER="none"
            info "平台: Windows ($(uname -s))"
            ;;
        macos)
            OS_TYPE="macos"; PKG_MANAGER="brew"
            info "平台: macOS"
            ;;
        linux)
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release; OS_TYPE="$ID"
            elif [[ -f /etc/redhat-release ]]; then
                OS_TYPE="centos"
            else
                OS_TYPE="unknown"
            fi
            case "$OS_TYPE" in
                ubuntu|debian|linuxmint|pop|kali|deepin|zorin)
                    PKG_MANAGER="apt"; info "平台: Linux ($OS_TYPE, apt)" ;;
                centos|rhel|rocky|almalinux|fedora|ol)
                    PKG_MANAGER="yum"; command_exists dnf && PKG_MANAGER="dnf"
                    info "平台: Linux ($OS_TYPE, $PKG_MANAGER)" ;;
                arch|manjaro|endeavouros)
                    PKG_MANAGER="pacman"; info "平台: Linux ($OS_TYPE, pacman)" ;;
                alpine)
                    PKG_MANAGER="apk"; info "平台: Alpine Linux" ;;
                *)
                    PKG_MANAGER="unknown"; warn "未识别的发行版: $OS_TYPE" ;;
            esac
            ;;
    esac
}

get_sudo() {
    if [[ "$PLATFORM" == "termux" || "$PLATFORM" == "windows" ]]; then
        NEED_SUDO=""; return
    fi
    if [[ "$EUID" -eq 0 ]]; then
        NEED_SUDO=""
    elif command_exists sudo; then
        NEED_SUDO="sudo"
    else
        error "需要 root 权限但未找到 sudo"; exit 1
    fi
}

# =====================================================================
#  网络检测
# =====================================================================
detect_network() {
    step "检测网络环境..."
    local china_test=false

    if curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" &>/dev/null; then
        if ! curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" &>/dev/null; then
            china_test=true
        fi
    fi

    if [[ "$china_test" == false ]]; then
        local cc; cc=$(curl -s --connect-timeout 5 --max-time 8 "https://ipapi.co/country_code/" 2>/dev/null || true)
        [[ "$cc" == "CN" ]] && china_test=true
    fi

    if [[ "$china_test" == true ]]; then
        IS_CHINA=true
        info "中国大陆网络 — 自动启用加速镜像"
        find_github_proxy
    else
        IS_CHINA=false
        info "国际网络 — 直连 GitHub"
    fi
}

find_github_proxy() {
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "可用代理: ${proxy}"
            return 0
        fi
    done
    warn "未找到可用代理，将尝试直连"
    GITHUB_PROXY=""
}

get_github_url() {
    local url="$1"
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && echo "${GITHUB_PROXY}${url}" || echo "$url"
}

# =====================================================================
#  IP 检测
# =====================================================================
get_local_ip() {
    local ip=""
    if command_exists ip; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1 2>/dev/null || true)
        [[ -z "$ip" ]] && ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 2>/dev/null || true)
    fi
    [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi
    echo "${ip:-未知}"
}

get_public_ip() {
    local ip=""
    local services=(
        "https://ifconfig.me"
        "https://ip.sb"
        "https://api.ipify.org"
        "https://ipinfo.io/ip"
        "https://myip.ipip.net/ip"
    )
    for svc in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 3 --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
}

show_access_info() {
    local port; port=$(get_port)
    local listen_val; listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
    echo ""
    info "本地访问: ${CYAN}http://127.0.0.1:${port}${NC}"
    if [[ "$listen_val" == "true" ]]; then
        local lan_ip; lan_ip=$(get_local_ip)
        local pub_ip; pub_ip=$(get_public_ip)
        [[ "$lan_ip" != "未知" ]] && info "局域网:   ${CYAN}http://${lan_ip}:${port}${NC}"
        if [[ -n "$pub_ip" ]]; then
            info "公网访问: ${CYAN}http://${pub_ip}:${port}${NC}"
        else
            warn "公网 IP 获取失败，请在服务器控制台查看"
        fi
    fi
}

# =====================================================================
#  配置管理
# =====================================================================
load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        source "$KSILLY_CONF" 2>/dev/null || true
        INSTALL_DIR="${KSILLY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    else
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    fi
}

save_config() {
    cat > "$KSILLY_CONF" <<CONF
KSILLY_INSTALL_DIR="${INSTALL_DIR}"
KSILLY_IS_CHINA="${IS_CHINA}"
KSILLY_GITHUB_PROXY="${GITHUB_PROXY}"
CONF
}

check_installed() {
    load_config
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/server.js" ]] && return 0
    if [[ -d "$DEFAULT_INSTALL_DIR" && -f "$DEFAULT_INSTALL_DIR/server.js" ]]; then
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"; save_config; return 0
    fi
    return 1
}

# =====================================================================
#  依赖安装
# =====================================================================
check_node_version() {
    command_exists node || return 1
    local v; v=$(node -v | sed 's/v//' | cut -d. -f1)
    [[ "$v" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_dependencies() {
    step "检查并安装依赖..."
    case "$PLATFORM" in
        termux)   install_deps_termux  ;;
        windows)  install_deps_windows ;;
        macos)    install_deps_unix    ;;
        linux)    install_deps_unix    ;;
    esac
}

install_deps_termux() {
    info "更新 Termux 包索引..."
    pkg update -y 2>&1 | tail -1
    info "安装 git, nodejs, curl..."
    pkg install -y git nodejs-lts curl 2>&1 | tail -1
    if command_exists git && check_node_version; then
        success "依赖就绪: Git $(git --version | awk '{print $3}'), Node $(node -v)"
    else
        # 尝试 nodejs 包名
        pkg install -y nodejs 2>&1 | tail -1
        check_node_version || { error "Node.js 安装失败"; exit 1; }
    fi
    # npm 镜像
    [[ "$IS_CHINA" == true ]] && npm config set registry https://registry.npmmirror.com
}

install_deps_windows() {
    local missing=()
    command_exists git  || missing+=("Git     → https://git-scm.com/")
    command_exists node || missing+=("Node.js → https://nodejs.org/  (LTS)")
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "以下软件未安装，请手动安装后重试:"
        for m in "${missing[@]}"; do echo -e "    ${RED}✖${NC} $m"; done
        exit 1
    fi
    check_node_version || { error "Node.js 版本过低 (当前 $(node -v)，需 v${MIN_NODE_VERSION}+)"; exit 1; }
    success "依赖就绪: Git $(git --version | awk '{print $3}'), Node $(node -v)"
    [[ "$IS_CHINA" == true ]] && npm config set registry https://registry.npmmirror.com
}

install_deps_unix() {
    get_sudo

    # 更新包缓存
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get update -qq 2>/dev/null ;;
        yum)    $NEED_SUDO yum makecache -q  2>/dev/null ;;
        dnf)    $NEED_SUDO dnf makecache -q  2>/dev/null ;;
        pacman) $NEED_SUDO pacman -Sy --noconfirm 2>/dev/null ;;
        apk)    $NEED_SUDO apk update       2>/dev/null ;;
        brew)   brew update 2>/dev/null ;;
    esac

    # Git
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') ✓"
    else
        info "安装 Git..."
        case "$PKG_MANAGER" in
            apt)    $NEED_SUDO apt-get install -y -qq git ;;
            yum)    $NEED_SUDO yum install -y -q git ;;
            dnf)    $NEED_SUDO dnf install -y -q git ;;
            pacman) $NEED_SUDO pacman -S --noconfirm git ;;
            apk)    $NEED_SUDO apk add git ;;
            brew)   brew install git ;;
            *)      error "请手动安装 git"; exit 1 ;;
        esac
        command_exists git || { error "Git 安装失败"; exit 1; }
        success "Git 安装完成"
    fi

    # curl / wget / tar
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils 2>/dev/null ;;
        yum)    $NEED_SUDO yum install -y -q curl wget tar xz 2>/dev/null ;;
        dnf)    $NEED_SUDO dnf install -y -q curl wget tar xz 2>/dev/null ;;
        pacman) $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz 2>/dev/null ;;
        apk)    $NEED_SUDO apk add curl wget tar xz 2>/dev/null ;;
    esac

    # Node.js
    if check_node_version; then
        info "Node.js $(node -v) ✓"
    else
        [[ "$(command_exists node && node -v || true)" ]] && warn "Node.js 版本过低 ($(node -v))，需 v${MIN_NODE_VERSION}+"
        install_nodejs
    fi

    [[ "$IS_CHINA" == true ]] && { npm config set registry https://registry.npmmirror.com; info "npm 镜像: npmmirror ✓"; }
}

install_nodejs() {
    step "安装 Node.js v20.x..."
    if [[ "$IS_CHINA" == true ]]; then
        install_nodejs_binary "https://npmmirror.com/mirrors/node"
    else
        case "$PKG_MANAGER" in
            apt)
                $NEED_SUDO apt-get install -y -qq ca-certificates curl gnupg
                $NEED_SUDO mkdir -p /etc/apt/keyrings
                curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                    | $NEED_SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
                    | $NEED_SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
                $NEED_SUDO apt-get update -qq
                $NEED_SUDO apt-get install -y -qq nodejs
                ;;
            yum|dnf)
                curl -fsSL https://rpm.nodesource.com/setup_20.x | $NEED_SUDO bash -
                $NEED_SUDO $PKG_MANAGER install -y nodejs
                ;;
            pacman) $NEED_SUDO pacman -S --noconfirm nodejs npm ;;
            apk)    $NEED_SUDO apk add nodejs npm ;;
            brew)   brew install node@20 ;;
            *)      install_nodejs_binary ;;
        esac
    fi
    hash -r 2>/dev/null || true
    check_node_version || { error "Node.js 安装失败"; exit 1; }
    success "Node.js $(node -v), npm $(npm -v) ✓"
}

install_nodejs_binary() {
    local mirror="${1:-https://nodejs.org/dist}"
    local ver="v20.18.0"
    local arch=""
    case "$(uname -m)" in
        x86_64|amd64)  arch="x64"    ;;
        aarch64|arm64) arch="arm64"  ;;
        armv7l)        arch="armv7l" ;;
        *) error "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
    esac
    local fn="node-${ver}-linux-${arch}.tar.xz"
    local url="${mirror}/${ver}/${fn}"
    local tmp; tmp=$(mktemp -d)
    info "下载: $url"
    curl -fSL --progress-bar -o "${tmp}/${fn}" "$url" || { error "下载失败"; exit 1; }
    cd "$tmp"; tar xf "$fn"
    get_sudo
    $NEED_SUDO cp -rf "node-${ver}-linux-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
    $NEED_SUDO cp -rf "node-${ver}-linux-${arch}"/{bin,include,lib} /usr/local/
    cd - >/dev/null; rm -rf "$tmp"; hash -r 2>/dev/null || true
}

# =====================================================================
#  PM2 进程管理
# =====================================================================
ensure_pm2() {
    if command_exists pm2; then return 0; fi

    # 尝试 PATH 中查找
    local npm_prefix; npm_prefix=$(npm config get prefix 2>/dev/null || true)
    if [[ -n "$npm_prefix" && -x "$npm_prefix/bin/pm2" ]]; then
        export PATH="$PATH:$npm_prefix/bin"
        command_exists pm2 && return 0
    fi

    step "安装 PM2 进程管理器..."
    case "$PLATFORM" in
        termux|windows)
            npm install -g pm2 2>&1 | tail -2
            ;;
        *)
            npm install -g pm2 2>/dev/null || {
                get_sudo
                $NEED_SUDO npm install -g pm2 2>&1 | tail -2
            }
            ;;
    esac

    # 再次确认 PATH
    npm_prefix=$(npm config get prefix 2>/dev/null || true)
    [[ -n "$npm_prefix" ]] && export PATH="$PATH:$npm_prefix/bin"

    command_exists pm2 && { success "PM2 $(pm2 -v 2>/dev/null) ✓"; return 0; }
    error "PM2 安装失败"; return 1
}

pm2_is_running() {
    command_exists pm2 || return 1
    local pid; pid=$(pm2 pid "$PM2_APP_NAME" 2>/dev/null || true)
    [[ -n "$pid" && "$pid" != "0" && "$pid" =~ ^[0-9]+$ ]]
}

pm2_start() {
    ensure_pm2 || return 1
    if pm2_is_running; then
        warn "SillyTavern 已在运行"
        show_access_info
        return 0
    fi
    step "启动 SillyTavern (PM2)..."
    cd "$INSTALL_DIR"
    pm2 start server.js --name "$PM2_APP_NAME" --cwd "$INSTALL_DIR" 2>/dev/null
    pm2 save --force 2>/dev/null || true
    cd - >/dev/null
    sleep 2
    if pm2_is_running; then
        success "SillyTavern 已启动"
        show_access_info
    else
        error "启动失败，查看日志: pm2 logs $PM2_APP_NAME"
    fi
}

pm2_stop() {
    if ! pm2_is_running; then
        info "SillyTavern 未在运行"
        return 0
    fi
    step "停止 SillyTavern..."
    pm2 stop "$PM2_APP_NAME" 2>/dev/null || true
    pm2 save --force 2>/dev/null || true
    success "SillyTavern 已停止"
}

pm2_restart() {
    ensure_pm2 || return 1
    if ! pm2_is_running; then
        pm2_start; return
    fi
    step "重启 SillyTavern..."
    pm2 restart "$PM2_APP_NAME" 2>/dev/null
    pm2 save --force 2>/dev/null || true
    sleep 2
    if pm2_is_running; then
        success "SillyTavern 已重启"
        show_access_info
    else
        error "重启失败"
    fi
}

pm2_logs() {
    if ! command_exists pm2; then
        warn "PM2 未安装"; return 1
    fi
    echo ""
    info "最近 50 行日志:"
    divider
    pm2 logs "$PM2_APP_NAME" --lines 50 --nostream 2>/dev/null || warn "无日志可显示"
}

pm2_setup_startup() {
    ensure_pm2 || return 1

    echo ""
    echo -e "  ${BOLD}当前状态:${NC}"
    if pm2_is_running; then
        echo -e "    PM2 进程: ${GREEN}● 运行中${NC}"
    else
        echo -e "    PM2 进程: ${RED}● 未运行${NC}"
    fi

    # 检查是否已配置 startup
    local startup_configured=false
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        # 检查 systemd 中是否有 pm2 相关服务
        if command_exists systemctl && systemctl list-unit-files 2>/dev/null | grep -q "pm2-${CURRENT_USER}"; then
            startup_configured=true
        fi
    fi
    if [[ "$startup_configured" == true ]]; then
        echo -e "    开机自启: ${GREEN}● 已配置${NC}"
    else
        echo -e "    开机自启: ${DIM}● 未配置${NC}"
    fi
    echo ""
    divider
    echo ""

    echo -e "  ${GREEN}1)${NC} 启动 SillyTavern 后台进程"
    echo -e "  ${GREEN}2)${NC} 停止后台进程"
    echo -e "  ${GREEN}3)${NC} 配置开机自启"
    echo -e "  ${GREEN}4)${NC} 取消开机自启"
    echo ""
    echo -e "  ${RED}0)${NC} 返回"
    echo ""

    local choice; choice=$(read_input "请选择")

    case "$choice" in
        1) pm2_start ;;
        2) pm2_stop ;;
        3)
            case "$PLATFORM" in
                linux|macos)
                    if ! pm2_is_running; then
                        warn "请先启动 SillyTavern 再配置自启"
                        if confirm "是否先启动?"; then pm2_start; else return; fi
                    fi
                    info "配置开机自启..."
                    local cmd; cmd=$(pm2 startup 2>&1 | grep -E '^\s*sudo' | head -1)
                    if [[ -n "$cmd" ]]; then
                        info "执行: $cmd"
                        eval "$cmd" 2>/dev/null || true
                    else
                        pm2 startup 2>/dev/null || true
                    fi
                    pm2 save --force 2>/dev/null || true
                    success "开机自启已配置"
                    ;;
                termux)
                    warn "Termux 不支持系统级开机自启"
                    info "可将启动命令加入 ~/.bashrc 实现打开终端时自动启动"
                    ;;
                windows)
                    warn "Windows 开机自启需使用 pm2-installer"
                    info "参考: https://github.com/jessety/pm2-installer"
                    ;;
            esac
            ;;
        4)
            pm2 unstartup 2>/dev/null || true
            pm2 save --force 2>/dev/null || true
            success "开机自启已取消"
            ;;
        0) return ;;
    esac
}

# 迁移旧的 systemd 服务
migrate_legacy_systemd() {
    [[ "$PLATFORM" != "linux" ]] && return
    command_exists systemctl || return

    if systemctl list-unit-files "sillytavern.service" &>/dev/null 2>&1; then
        echo ""
        warn "检测到旧版 systemd 服务 (sillytavern.service)"
        info "本脚本已改用 PM2 管理进程，建议移除旧服务"
        if confirm "是否移除 systemd 服务?"; then
            get_sudo
            $NEED_SUDO systemctl stop sillytavern 2>/dev/null || true
            $NEED_SUDO systemctl disable sillytavern 2>/dev/null || true
            $NEED_SUDO rm -f /etc/systemd/system/sillytavern.service
            $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
            success "systemd 服务已移除"
        fi
    fi
}

# =====================================================================
#  防火墙管理
# =====================================================================
open_firewall_port() {
    local port="$1"
    [[ "$PLATFORM" != "linux" ]] && return
    get_sudo

    step "检查防火墙..."
    local found=false

    # UFW
    if command_exists ufw; then
        local st; st=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$st" | grep -qi "active"; then
            found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW: 端口 $port 已放行"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW: 已放行端口 $port/tcp"
            fi
        fi
    fi

    # firewalld
    if command_exists firewall-cmd; then
        local st; st=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$st" == "running" ]]; then
            found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 $port 已放行"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld: 已放行端口 $port/tcp"
            fi
        fi
    fi

    # iptables 兜底
    if [[ "$found" == false ]] && command_exists iptables; then
        local drops; drops=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || true)
        if [[ "$drops" -gt 0 ]]; then
            found=true
            if ! $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
                command_exists iptables-save && $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
                success "iptables: 已放行端口 $port/tcp"
            else
                info "iptables: 端口 $port 已放行"
            fi
        fi
    fi

    [[ "$found" == false ]] && info "未检测到活动防火墙"
    warn "云服务器用户请确保安全组也已放行端口 ${port}/tcp"
}

remove_firewall_port() {
    local port="$1"
    [[ "$PLATFORM" != "linux" ]] && return
    get_sudo
    if command_exists ufw; then
        $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
    fi
    if command_exists firewall-cmd; then
        $NEED_SUDO firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null || true
        $NEED_SUDO firewall-cmd --reload 2>/dev/null || true
    fi
}

# =====================================================================
#  脚本自保存
# =====================================================================
save_script_copy() {
    [[ ! -d "$INSTALL_DIR" ]] && return
    local target="$INSTALL_DIR/ksilly.sh"
    local src="${BASH_SOURCE[0]:-$0}"

    # 如果是从文件运行
    if [[ -f "$src" && "$src" != "/dev/"* && "$src" != "/proc/"* ]]; then
        cp "$src" "$target" 2>/dev/null || true
    else
        # 从 pipe 运行，下载一份
        local url="$SCRIPT_RAW_URL"
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && url="${GITHUB_PROXY}${url}"
        curl -fsSL "$url" -o "$target" 2>/dev/null || \
        curl -fsSL "$SCRIPT_RAW_URL" -o "$target" 2>/dev/null || true
    fi

    if [[ -f "$target" ]]; then
        chmod +x "$target"
        info "管理脚本已保存: ${CYAN}${target}${NC}"
        info "后续运行: ${CYAN}bash ${target}${NC}"
    fi
}

# =====================================================================
#  SillyTavern 克隆
# =====================================================================
clone_sillytavern() {
    step "安装 SillyTavern..."
    INSTALL_DIR=$(read_input "安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" ]]; then
            warn "目录已存在 SillyTavern 安装: $INSTALL_DIR"
            if confirm "删除并重新安装?"; then
                rm -rf "$INSTALL_DIR"
            else
                info "保留现有安装"; return 0
            fi
        else
            error "目录已存在且非 SillyTavern: $INSTALL_DIR"; exit 1
        fi
    fi

    echo ""
    echo -e "  ${BOLD}选择分支:${NC}"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}— 稳定版 (推荐)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}— 开发版 (最新功能)${NC}"
    echo ""
    local bc=""
    while [[ "$bc" != "1" && "$bc" != "2" ]]; do bc=$(read_input "选择 (1/2)"); done
    local branch="release"; [[ "$bc" == "2" ]] && branch="staging"
    info "分支: $branch"

    local repo_url; repo_url=$(get_github_url "$SILLYTAVERN_REPO")
    if ! git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" 2>&1 | tail -3; then
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理失败，尝试直连..."
            git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR" 2>&1 | tail -3 || \
                { error "克隆失败"; exit 1; }
        else
            error "克隆失败"; exit 1
        fi
    fi
    success "仓库克隆完成"

    # 规范化 YAML 换行符
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖..."
    cd "$INSTALL_DIR"
    npm install --no-audit --no-fund 2>&1 | tail -3
    cd - >/dev/null
    success "npm 依赖安装完成"
    save_config
}

# =====================================================================
#  初始配置向导 (安装时)
# =====================================================================
configure_initial() {
    step "配置 SillyTavern..."
    local cf="$INSTALL_DIR/config.yaml"
    local df="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$cf" ]]; then
        [[ -f "$df" ]] || { error "缺少 default.yaml"; exit 1; }
        cp "$df" "$cf"; sed -i 's/\r$//' "$cf" 2>/dev/null || true
        info "已生成 config.yaml"
    fi

    echo ""
    divider
    echo -e "  ${BOLD}配置向导${NC}  ${DIM}(仅设置核心项目，其余可后续修改)${NC}"
    divider
    echo ""

    # 1. 监听
    echo -e "  ${YELLOW}● 监听模式${NC}"
    echo -e "    ${DIM}开启 → 监听 0.0.0.0，允许远程访问${NC}"
    echo -e "    ${DIM}关闭 → 仅 127.0.0.1，本机访问${NC}"
    echo ""
    local listen=false
    if confirm "开启监听 (允许远程访问)?"; then
        set_yaml_val "listen" "true" "$cf"; listen=true
        success "已开启监听"
    else
        set_yaml_val "listen" "false" "$cf"
        info "保持本机访问"
    fi

    # 2. 端口
    echo ""
    local port; port=$(read_input "端口号" "8000")
    set_yaml_val "port" "$port" "$cf"
    info "端口: $port"

    # 3. 白名单
    echo ""
    echo -e "  ${YELLOW}● 白名单模式${NC}  ${DIM}开启后仅白名单 IP 可访问${NC}"
    if [[ "$listen" == true ]]; then
        echo -e "    ${DIM}远程访问时建议关闭白名单${NC}"
    fi
    echo ""
    if confirm "关闭白名单模式?"; then
        set_yaml_val "whitelistMode" "false" "$cf"
        success "白名单已关闭"
    else
        set_yaml_val "whitelistMode" "true" "$cf"
        info "白名单保持开启"
    fi

    # 4. 基础认证
    echo ""
    echo -e "  ${YELLOW}● 基础认证 (basicAuth)${NC}"
    [[ "$listen" == true ]] && echo -e "    ${RED}远程访问时强烈建议开启${NC}"
    echo ""
    if confirm "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$cf"
        echo ""
        local user=""
        while [[ -z "$user" ]]; do
            user=$(read_input "认证用户名")
            [[ -z "$user" ]] && warn "用户名不能为空"
        done
        local pass; pass=$(read_password "认证密码")

        # 使用 sed 修改 basicAuthUser 内的字段
        local escaped_user; escaped_user=$(printf '%s' "$user" | sed 's/[&/\]/\\&/g')
        local escaped_pass; escaped_pass=$(printf '%s' "$pass" | sed 's/[&/\]/\\&/g')
        sed_i "/basicAuthUser:/,/^[^ #]/{
            s|\( *\)username:.*|\1username: \"${escaped_user}\"|
            s|\( *\)password:.*|\1password: \"${escaped_pass}\"|
        }" "$cf"
        success "认证已开启 (用户: $user)"
    else
        set_yaml_val "basicAuthMode" "false" "$cf"
        info "认证保持关闭"
    fi

    # 5. 防火墙 (仅 listen 且 Linux)
    [[ "$listen" == true ]] && open_firewall_port "$port"

    echo ""
    success "配置已保存: $cf"
}

# =====================================================================
#  配置修改菜单 (维护时)
# =====================================================================
modify_config_menu() {
    check_installed || { error "SillyTavern 未安装"; return 1; }
    local cf="$INSTALL_DIR/config.yaml"
    [[ -f "$cf" ]] || { error "配置文件不存在"; return 1; }

    while true; do
        print_banner

        local lv wv av pv uv dv
        lv=$(get_yaml_val "listen" "$cf")
        wv=$(get_yaml_val "whitelistMode" "$cf")
        av=$(get_yaml_val "basicAuthMode" "$cf")
        pv=$(get_port)
        uv=$(get_yaml_val "enableUserAccounts" "$cf")
        dv=$(get_yaml_val "enableDiscreetLogin" "$cf")

        echo -e "  ${BOLD}当前配置${NC}"
        divider
        echo ""
        echo -e "    监听模式         $(format_bool "$lv")"
        echo -e "    白名单模式       $(format_bool "$wv")"
        echo -e "    基础认证         $(format_bool "$av")"
        echo -e "    端口             ${CYAN}${pv}${NC}"
        echo -e "    多用户账户       $(format_bool "$uv")"
        echo -e "    隐蔽登录页       $(format_bool "$dv")"
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 切换 监听模式"
        echo -e "  ${GREEN}2)${NC} 切换 白名单模式"
        echo -e "  ${GREEN}3)${NC} 修改 基础认证"
        echo -e "  ${GREEN}4)${NC} 修改 端口"
        echo -e "  ${GREEN}5)${NC} 切换 多用户账户  ${DIM}(enableUserAccounts)${NC}"
        echo -e "  ${GREEN}6)${NC} 切换 隐蔽登录页  ${DIM}(enableDiscreetLogin)${NC}"
        echo -e "  ${GREEN}7)${NC} 编辑配置文件     ${DIM}(nano/vi)${NC}"
        echo -e "  ${GREEN}8)${NC} 重置默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行"
        echo ""
        echo -e "  ${RED}0)${NC} 返回"
        echo ""
        divider

        local c; c=$(read_input "请选择")
        case "$c" in
            1)
                echo ""
                echo -e "  当前: $(format_bool "$lv")"
                if confirm "切换监听模式?"; then
                    if [[ "$lv" == "true" ]]; then
                        set_yaml_val "listen" "false" "$cf"; success "监听已关闭"
                    else
                        set_yaml_val "listen" "true" "$cf"; success "监听已开启"
                        open_firewall_port "$(get_port)"
                    fi
                fi ;;
            2)
                echo ""
                echo -e "  当前: $(format_bool "$wv")"
                if confirm "切换白名单模式?"; then
                    if [[ "$wv" == "true" ]]; then
                        set_yaml_val "whitelistMode" "false" "$cf"; success "白名单已关闭"
                    else
                        set_yaml_val "whitelistMode" "true" "$cf"; success "白名单已开启"
                    fi
                fi ;;
            3)
                echo ""
                echo -e "  当前: $(format_bool "$av")"
                if confirm "修改基础认证设置?"; then
                    if [[ "$av" == "true" ]]; then
                        if confirm "关闭基础认证?"; then
                            set_yaml_val "basicAuthMode" "false" "$cf"; success "认证已关闭"
                        else
                            echo ""
                            local user=""
                            while [[ -z "$user" ]]; do user=$(read_input "新用户名"); done
                            local pass; pass=$(read_password "新密码")
                            local eu; eu=$(printf '%s' "$user" | sed 's/[&/\]/\\&/g')
                            local ep; ep=$(printf '%s' "$pass" | sed 's/[&/\]/\\&/g')
                            sed_i "/basicAuthUser:/,/^[^ #]/{
                                s|\( *\)username:.*|\1username: \"${eu}\"|
                                s|\( *\)password:.*|\1password: \"${ep}\"|
                            }" "$cf"
                            success "认证凭据已更新 (用户: $user)"
                        fi
                    else
                        set_yaml_val "basicAuthMode" "true" "$cf"
                        echo ""
                        local user=""
                        while [[ -z "$user" ]]; do user=$(read_input "用户名"); done
                        local pass; pass=$(read_password "密码")
                        local eu; eu=$(printf '%s' "$user" | sed 's/[&/\]/\\&/g')
                        local ep; ep=$(printf '%s' "$pass" | sed 's/[&/\]/\\&/g')
                        sed_i "/basicAuthUser:/,/^[^ #]/{
                            s|\( *\)username:.*|\1username: \"${eu}\"|
                            s|\( *\)password:.*|\1password: \"${ep}\"|
                        }" "$cf"
                        success "认证已开启 (用户: $user)"
                    fi
                fi ;;
            4)
                echo ""
                echo -e "  当前端口: ${CYAN}${pv}${NC}"
                local np; np=$(read_input "新端口" "$pv")
                if [[ "$np" =~ ^[0-9]+$ ]] && (( np >= 1 && np <= 65535 )); then
                    set_yaml_val "port" "$np" "$cf"
                    success "端口已改为: $np"
                    local cl; cl=$(get_yaml_val "listen" "$cf")
                    [[ "$cl" == "true" ]] && open_firewall_port "$np"
                else
                    error "无效端口: $np"
                fi ;;
            5)
                echo ""
                echo -e "  当前: $(format_bool "$uv")"
                if confirm "切换多用户账户功能?"; then
                    if [[ "$uv" == "true" ]]; then
                        set_yaml_val "enableUserAccounts" "false" "$cf"; success "多用户账户已关闭"
                    else
                        set_yaml_val "enableUserAccounts" "true" "$cf"; success "多用户账户已开启"
                    fi
                fi ;;
            6)
                echo ""
                echo -e "  当前: $(format_bool "$dv")"
                if confirm "切换隐蔽登录页?"; then
                    if [[ "$dv" == "true" ]]; then
                        set_yaml_val "enableDiscreetLogin" "false" "$cf"; success "隐蔽登录已关闭"
                    else
                        set_yaml_val "enableDiscreetLogin" "true" "$cf"; success "隐蔽登录已开启"
                    fi
                fi ;;
            7)
                local ed="nano"; command_exists nano || ed="vi"
                $ed "$cf" ;;
            8)
                if confirm "重置配置为默认值? 当前配置将丢失!"; then
                    cp "$INSTALL_DIR/default.yaml" "$cf"
                    sed -i 's/\r$//' "$cf" 2>/dev/null || true
                    success "已重置"
                fi ;;
            9)
                open_firewall_port "$(get_port)" ;;
            0)
                break ;;
            *)
                warn "无效选项" ;;
        esac

        # 提示重启
        if [[ "$c" =~ ^[1-6]$ ]] && pm2_is_running; then
            echo ""
            warn "修改需重启 SillyTavern 生效"
            if confirm "立即重启?"; then
                pm2_restart
            fi
        fi
        pause
    done
}

# =====================================================================
#  状态查看
# =====================================================================
show_status() {
    check_installed || { error "SillyTavern 未安装"; return 1; }

    print_banner
    echo -e "  ${BOLD}SillyTavern 状态${NC}"
    divider
    echo ""

    # 版本
    local ver="未知"
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        ver=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

    # 分支
    local branch="未知"
    [[ -d "$INSTALL_DIR/.git" ]] && branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")

    echo -e "    版本:     ${CYAN}v${ver}${NC}"
    echo -e "    分支:     ${CYAN}${branch}${NC}"
    echo -e "    目录:     ${DIM}${INSTALL_DIR}${NC}"
    echo ""

    # 运行状态
    if pm2_is_running; then
        local pid; pid=$(pm2 pid "$PM2_APP_NAME" 2>/dev/null || true)
        echo -e "    运行状态: ${GREEN}● 运行中${NC} ${DIM}(PM2, PID: ${pid})${NC}"
    elif command_exists pm2 && pm2 describe "$PM2_APP_NAME" &>/dev/null; then
        echo -e "    运行状态: ${RED}● 已停止${NC} ${DIM}(PM2 进程存在但未运行)${NC}"
    else
        echo -e "    运行状态: ${RED}● 未运行${NC}"
    fi

    # 开机自启
    local startup="${DIM}未配置${NC}"
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "macos" ]]; then
        if command_exists systemctl && systemctl list-unit-files 2>/dev/null | grep -q "pm2-${CURRENT_USER}"; then
            startup="${GREEN}已配置${NC}"
        fi
    fi
    echo -e "    开机自启: ${startup}"
    echo ""

    # 配置摘要
    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        local lv wv av pv uv dv
        lv=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
        wv=$(get_yaml_val "whitelistMode" "$INSTALL_DIR/config.yaml")
        av=$(get_yaml_val "basicAuthMode" "$INSTALL_DIR/config.yaml")
        pv=$(get_port)
        uv=$(get_yaml_val "enableUserAccounts" "$INSTALL_DIR/config.yaml")
        dv=$(get_yaml_val "enableDiscreetLogin" "$INSTALL_DIR/config.yaml")

        divider
        echo ""
        echo -e "  ${BOLD}配置摘要${NC}"
        echo ""
        echo -e "    监听       $(format_bool "$lv")     白名单     $(format_bool "$wv")"
        echo -e "    认证       $(format_bool "$av")     端口       ${CYAN}${pv}${NC}"
        echo -e "    多用户     $(format_bool "$uv")     隐蔽登录   $(format_bool "$dv")"
    fi

    show_access_info
    echo ""
}

# =====================================================================
#  更新
# =====================================================================
check_for_updates() {
    cd "$INSTALL_DIR"
    git fetch origin 2>/dev/null || { cd - >/dev/null; return 1; }
    local branch; branch=$(git branch --show-current 2>/dev/null)
    local local_h; local_h=$(git rev-parse HEAD 2>/dev/null)
    local remote_h; remote_h=$(git rev-parse "origin/$branch" 2>/dev/null)
    cd - >/dev/null

    if [[ -z "$local_h" || -z "$remote_h" ]]; then
        echo "error"
    elif [[ "$local_h" == "$remote_h" ]]; then
        echo "0"
    else
        echo "1"
    fi
}

update_sillytavern() {
    check_installed || { error "SillyTavern 未安装"; return 1; }

    print_banner
    echo -e "  ${BOLD}检查更新${NC}"
    divider
    echo ""

    # 当前信息
    local ver="未知" branch="未知"
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        ver=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
    [[ -d "$INSTALL_DIR/.git" ]] && branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")
    echo -e "    当前版本: ${CYAN}v${ver}${NC}"
    echo -e "    当前分支: ${CYAN}${branch}${NC}"
    echo ""

    info "检查远程更新..."

    # 设置代理
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        cd "$INSTALL_DIR"
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null || true
        cd - >/dev/null
    fi

    local result; result=$(check_for_updates)

    # 恢复远程 URL
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        cd "$INSTALL_DIR"
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null || true
        cd - >/dev/null
    fi

    case "$result" in
        0)
            success "当前已是最新版本！"
            return 0
            ;;
        error)
            error "无法检查更新，请检查网络"
            return 1
            ;;
        *)
            echo -e "  ${GREEN}✔${NC} 发现新版本可用！"
            echo ""
            if ! confirm "是否立即更新?"; then
                info "已取消更新"; return 0
            fi
            ;;
    esac

    # 停止运行中的实例
    if pm2_is_running; then
        warn "SillyTavern 正在运行，需要先停止"
        pm2_stop
    fi

    # 备份配置
    local bak="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bak"
    [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$bak/"
    info "配置已备份到: $bak"

    # 拉取
    cd "$INSTALL_DIR"
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null || true
    fi

    if git pull --ff-only 2>&1 | tail -3; then
        success "代码更新完成"
    else
        warn "快速合并失败，强制更新..."
        git fetch --all 2>/dev/null
        git reset --hard "origin/$branch"
        success "代码强制更新完成"
    fi

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null || true

    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    info "更新 npm 依赖..."
    npm install --no-audit --no-fund 2>&1 | tail -3

    # 恢复配置
    [[ -f "$bak/config.yaml" ]] && { cp "$bak/config.yaml" "config.yaml"; success "配置已恢复"; }

    cd - >/dev/null

    # 版本信息
    local new_ver="未知"
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        new_ver=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
    success "更新完成! v${ver} → v${new_ver}"

    # 保存新版脚本
    save_script_copy

    echo ""
    if confirm "立即启动 SillyTavern?"; then
        pm2_start
    fi
}

# =====================================================================
#  卸载
# =====================================================================
uninstall_sillytavern() {
    check_installed || { error "SillyTavern 未安装"; return 1; }

    echo ""
    warn "即将卸载 SillyTavern"
    echo -e "    目录: ${INSTALL_DIR}"
    echo ""
    confirm "确定要卸载吗? 此操作不可恢复!" || { info "已取消"; return 0; }
    confirm "再次确认!" || { info "已取消"; return 0; }

    # 停止
    pm2_stop 2>/dev/null || true
    if command_exists pm2; then
        pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
        pm2 save --force 2>/dev/null || true
    fi

    # 迁移旧 systemd
    migrate_legacy_systemd 2>/dev/null || true

    # 防火墙
    local port; port=$(get_port)
    remove_firewall_port "$port"

    # 备份数据
    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm "备份聊天数据和角色卡?"; then
            local bak="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$bak"
            cp -r "$INSTALL_DIR/data" "$bak/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$bak/"
            success "数据已备份到: $bak"
        fi
    fi

    rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "SillyTavern 已卸载"
}

# =====================================================================
#  完整安装流程
# =====================================================================
full_install() {
    print_banner
    echo -e "  ${BOLD}${GREEN}开始安装 SillyTavern${NC}"
    divider
    echo ""

    detect_os
    detect_network
    echo ""

    install_dependencies
    echo ""

    clone_sillytavern
    echo ""

    configure_initial
    echo ""

    # PM2
    divider
    echo -e "\n  ${BOLD}后台运行设置${NC}"
    echo -e "  ${DIM}使用 PM2 进程管理器保持后台运行${NC}"
    echo ""
    local use_pm2=false
    if confirm "开启后台运行 (PM2)?"; then
        use_pm2=true
        ensure_pm2
    fi

    # 迁移旧 systemd
    migrate_legacy_systemd

    save_config
    save_script_copy

    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${GREEN}🎉 安装完成!${NC}"
    echo ""
    show_status 2>/dev/null || true
    echo ""
    divider
    echo ""

    if confirm "立即启动 SillyTavern?"; then
        if [[ "$use_pm2" == true ]]; then
            pm2_start
        else
            local port; port=$(get_port)
            info "前台启动，按 Ctrl+C 停止"
            show_access_info
            echo ""
            cd "$INSTALL_DIR"
            node server.js
            cd - >/dev/null
        fi
    else
        echo ""
        info "后续启动方式:"
        echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}  ${DIM}(管理菜单)${NC}"
        echo -e "    ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}  ${DIM}(前台)${NC}"
    fi
    echo ""
}

# =====================================================================
#  前台启动 (无 PM2)
# =====================================================================
start_foreground() {
    check_installed || { error "SillyTavern 未安装"; return 1; }
    local port; port=$(get_port)
    info "前台启动 SillyTavern"
    show_access_info
    info "按 Ctrl+C 停止"
    echo ""
    cd "$INSTALL_DIR"
    node server.js
    cd - >/dev/null
}

# =====================================================================
#  主菜单
# =====================================================================
main_menu() {
    while true; do
        print_banner
        load_config

        # 状态卡片
        if check_installed; then
            local ver="?" branch="?"
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                ver=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
            [[ -d "$INSTALL_DIR/.git" ]] && \
                branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "?")

            local st_icon="${RED}●${NC} 未运行"
            if pm2_is_running; then
                st_icon="${GREEN}●${NC} 运行中"
            fi

            echo -e "  ${st_icon}  ${BOLD}SillyTavern${NC} v${ver} (${branch})"
            local port; port=$(get_port)
            local listen_val; listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml" 2>/dev/null)
            if [[ "$listen_val" == "true" ]]; then
                local pub_ip; pub_ip=$(get_public_ip)
                if [[ -n "$pub_ip" ]]; then
                    echo -e "  ${DIM}访问: http://${pub_ip}:${port}${NC}"
                else
                    echo -e "  ${DIM}端口: ${port} | 监听已开启${NC}"
                fi
            else
                echo -e "  ${DIM}访问: http://127.0.0.1:${port}${NC}"
            fi
        else
            echo -e "  ${YELLOW}●${NC} SillyTavern 未安装"
        fi

        echo ""
        divider
        echo ""

        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "   ${GREEN}1)${NC}  安装 SillyTavern"
        echo -e "   ${GREEN}2)${NC}  更新 SillyTavern"
        echo -e "   ${GREEN}3)${NC}  卸载 SillyTavern"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "   ${GREEN}4)${NC}  启动 (PM2 后台)"
        echo -e "   ${GREEN}5)${NC}  停止"
        echo -e "   ${GREEN}6)${NC}  重启"
        echo -e "   ${GREEN}7)${NC}  前台启动"
        echo ""
        echo -e "  ${BOLD}配置与维护${NC}"
        echo -e "   ${GREEN}8)${NC}  查看状态"
        echo -e "   ${GREEN}9)${NC}  修改配置"
        echo -e "  ${GREEN}10)${NC}  后台保活与自启设置"
        echo -e "  ${GREEN}11)${NC}  查看日志"
        echo ""
        echo -e "   ${RED}0)${NC}  退出"
        echo ""
        divider

        local choice; choice=$(read_input "请选择")

        case "$choice" in
            1)
                if check_installed; then
                    warn "SillyTavern 已安装于 $INSTALL_DIR"
                    confirm "重新安装?" || continue
                fi
                full_install
                pause ;;
            2)
                detect_network 2>/dev/null || true
                update_sillytavern
                pause ;;
            3)
                uninstall_sillytavern
                pause ;;
            4)
                check_installed || { error "未安装"; pause; continue; }
                pm2_start
                pause ;;
            5)
                pm2_stop
                pause ;;
            6)
                check_installed || { error "未安装"; pause; continue; }
                pm2_restart
                pause ;;
            7)
                start_foreground
                pause ;;
            8)
                show_status
                pause ;;
            9)
                modify_config_menu ;;
            10)
                check_installed || { error "未安装"; pause; continue; }
                pm2_setup_startup
                pause ;;
            11)
                pm2_logs
                pause ;;
            0)
                echo ""
                info "再见~ 👋"
                echo ""
                exit 0 ;;
            *)
                warn "无效选项"
                sleep 1 ;;
        esac
    done
}

# =====================================================================
#  入口
# =====================================================================
main() {
    detect_platform
    load_config

    case "${1:-}" in
        install)   detect_os; detect_network; full_install ;;
        update)    detect_os; detect_network; update_sillytavern ;;
        start)     check_installed && pm2_start   || start_foreground ;;
        stop)      pm2_stop ;;
        restart)   check_installed && pm2_restart ;;
        status)    detect_platform; show_status ;;
        logs)      pm2_logs ;;
        uninstall) detect_os; uninstall_sillytavern ;;
        "")        main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|logs|uninstall}"
            echo "  无参数进入交互式菜单"
            exit 1 ;;
    esac
}

main "$@"
