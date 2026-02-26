#!/bin/bash
#
#  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
#  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
#  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
#  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
#  ██║  ██╗███████║██║███████╗███████╗██║
#  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
#
#  Ksilly - SillyTavern 一键部署管理脚本
#  作者: Mia1889
#  仓库: https://github.com/Mia1889/Ksilly
#  版本: 2.0.0
#  支持: Linux / macOS / Termux / Windows (Git Bash)
#

set -o pipefail

# ==================== 全局常量 ====================
SCRIPT_VERSION="2.0.0"
KSILLY_CONF="$HOME/.ksilly.conf"
DEFAULT_INSTALL_DIR="$HOME/SillyTavern"
SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh"
SERVICE_NAME="sillytavern"
MIN_NODE_VERSION=18
GITHUB_PROXIES=(
    "https://ghfast.top/"
    "https://gh-proxy.com/"
    "https://mirror.ghproxy.com/"
)

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ==================== 全局变量 ====================
PLATFORM=""        # linux / macos / termux / windows
OS_TYPE=""         # ubuntu / centos / ... (仅 linux)
PKG_MANAGER=""
IS_CHINA=false
GITHUB_PROXY=""
INSTALL_DIR=""
CURRENT_USER=$(whoami)
NEED_SUDO=""
HAS_SYSTEMD=false

# ==================== 工具函数 ====================

print_banner() {
    printf '\033c' 2>/dev/null || clear 2>/dev/null || true
    echo -e "${CYAN}"
    echo '  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗'
    echo '  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝'
    echo '  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝ '
    echo '  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝  '
    echo '  ██║  ██╗███████║██║███████╗███████╗██║   '
    echo '  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝  '
    echo -e "${NC}"
    echo -e "  ${BOLD}SillyTavern 一键部署管理 v${SCRIPT_VERSION}${NC}  ${DIM}[${PLATFORM}]${NC}"
    echo -e "  ${DIM}github.com/Mia1889/Ksilly${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }

step() {
    echo ""
    echo -e "  ${CYAN}▶ $1${NC}"
}

divider() {
    echo -e "  ${DIM}───────────────────────────────────────────${NC}"
}

command_exists() {
    command -v "$1" &>/dev/null
}

confirm() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) echo -e "  ${YELLOW}!${NC} 请输入 y 或 n" >&2 ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result=""
    if [[ -n "$default" ]]; then
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}[${default}]${NC}: " >&2
    else
        echo -ne "  ${BLUE}?${NC} ${prompt}: " >&2
    fi
    read -r result
    [[ -z "$result" && -n "$default" ]] && result="$default"
    echo "$result"
}

read_password() {
    local prompt="$1"
    local result=""
    while [[ -z "$result" ]]; do
        echo -e "  ${DIM}(输入密码时不会显示任何字符，这是正常的安全行为)${NC}" >&2
        echo -ne "  ${BLUE}?${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "密码不能为空，请重新输入" >&2
        fi
    done
    echo "$result"
}

format_bool() {
    local val="${1:-false}"
    if [[ "$val" == "true" ]]; then
        echo -e "${GREEN}开启${NC}"
    else
        echo -e "${DIM}关闭${NC}"
    fi
}

pause() {
    echo ""
    read -rp "  按 Enter 继续..."
}

# ==================== sed 跨平台兼容 ====================

sed_i() {
    if [[ "$PLATFORM" == "macos" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ==================== YAML 操作 ====================

get_yaml_val() {
    local key="$1"
    local file="$2"
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r\n "'\'''
}

set_yaml_val() {
    local key="$1"
    local value="$2"
    local file="$3"
    if grep -qE "^\s*${key}:" "$file" 2>/dev/null; then
        sed_i "s/^\( *\)${key}:.*/\1${key}: ${value}/" "$file"
    else
        echo "${key}: ${value}" >> "$file"
    fi
}

ensure_yaml_key() {
    local key="$1"
    local default_val="$2"
    local file="$3"
    if ! grep -qE "^\s*${key}:" "$file" 2>/dev/null; then
        echo "${key}: ${default_val}" >> "$file"
    fi
}

get_port() {
    local port
    port=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml" 2>/dev/null)
    [[ ! "$port" =~ ^[0-9]+$ ]] && port="8000"
    echo "$port"
}

# ==================== 平台检测 ====================

detect_platform() {
    PLATFORM="unknown"

    # Termux
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        PLATFORM="termux"
        return
    fi

    local uname_s uname_o
    uname_s=$(uname -s 2>/dev/null || echo "Unknown")
    uname_o=$(uname -o 2>/dev/null || echo "Unknown")

    case "$uname_s" in
        Linux)
            [[ "$uname_o" == "Android" ]] && PLATFORM="termux" || PLATFORM="linux"
            ;;
        Darwin)
            PLATFORM="macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            ;;
        *)
            case "$uname_o" in
                Msys|Cygwin|Mingw*) PLATFORM="windows" ;;
                *)                  PLATFORM="linux"    ;;
            esac
            ;;
    esac
}

detect_os() {
    case "$PLATFORM" in
        linux)
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                OS_TYPE="$ID"
            elif [[ -f /etc/redhat-release ]]; then
                OS_TYPE="centos"
            else
                OS_TYPE="unknown"
            fi
            case "$OS_TYPE" in
                ubuntu|debian|linuxmint|pop|deepin|kali)
                    PKG_MANAGER="apt"
                    ;;
                centos|rhel|rocky|almalinux|fedora|ol)
                    PKG_MANAGER="yum"
                    command_exists dnf && PKG_MANAGER="dnf"
                    ;;
                arch|manjaro|endeavouros)
                    PKG_MANAGER="pacman"
                    ;;
                alpine)
                    PKG_MANAGER="apk"
                    ;;
                *)
                    PKG_MANAGER="unknown"
                    ;;
            esac
            ;;
        macos)
            OS_TYPE="macos"
            PKG_MANAGER="brew"
            ;;
        termux)
            OS_TYPE="termux"
            PKG_MANAGER="pkg"
            ;;
        windows)
            OS_TYPE="windows"
            PKG_MANAGER="none"
            ;;
    esac

    # systemd 检测
    HAS_SYSTEMD=false
    if [[ "$PLATFORM" == "linux" ]] && command_exists systemctl && [[ -d /run/systemd/system ]]; then
        HAS_SYSTEMD=true
    fi
}

get_sudo() {
    case "$PLATFORM" in
        termux|windows)
            NEED_SUDO=""
            ;;
        *)
            if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
                NEED_SUDO=""
            elif command_exists sudo; then
                NEED_SUDO="sudo"
            else
                error "需要 root 权限但未找到 sudo，请以 root 用户运行"
                exit 1
            fi
            ;;
    esac
}

# ==================== 网络检测 ====================

detect_network() {
    step "检测网络环境..."

    local china_test=false

    if curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" &>/dev/null; then
        if ! curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" &>/dev/null; then
            china_test=true
        fi
    fi

    if [[ "$china_test" == false ]]; then
        local country
        country=$(curl -s --connect-timeout 4 --max-time 6 "https://ipapi.co/country_code/" 2>/dev/null || true)
        [[ "$country" == "CN" ]] && china_test=true
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
    info "测试 GitHub 代理..."
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "可用代理: ${CYAN}${proxy}${NC}"
            return 0
        fi
    done
    warn "未找到可用代理，将尝试直连"
    GITHUB_PROXY=""
}

get_github_url() {
    local url="$1"
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        echo "${GITHUB_PROXY}${url}"
    else
        echo "$url"
    fi
}

# ==================== IP 检测 ====================

get_local_ip() {
    local ip=""

    case "$PLATFORM" in
        linux)
            if command_exists ip; then
                ip=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
            fi
            if [[ -z "$ip" ]] && command_exists ip; then
                ip=$(ip -4 addr show scope global 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
            fi
            if [[ -z "$ip" ]] && command_exists hostname; then
                ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
            ;;
        macos)
            ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
            if [[ -z "$ip" ]] && command_exists ifconfig; then
                ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
            fi
            ;;
        termux)
            if command_exists ip; then
                ip=$(ip -4 addr show wlan0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
                [[ -z "$ip" ]] && ip=$(ip -4 addr show scope global 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
            fi
            if [[ -z "$ip" ]] && command_exists ifconfig; then
                ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
            fi
            ;;
        windows)
            if command_exists ipconfig.exe; then
                ip=$(ipconfig.exe 2>/dev/null | grep -E 'IPv4' | head -1 | sed 's/.*: //' | tr -d '\r')
            fi
            ;;
    esac

    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi

    echo "${ip:-未知}"
}

get_public_ip() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://api.ip.sb/ip"
        "https://ident.me"
    )

    for svc in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 3 --max-time 5 "$svc" 2>/dev/null | tr -d '\r\n ')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
}

# ==================== 包管理与依赖安装 ====================

update_pkg_cache() {
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get update -qq 2>/dev/null ;;
        yum)    $NEED_SUDO yum makecache -q 2>/dev/null ;;
        dnf)    $NEED_SUDO dnf makecache -q 2>/dev/null ;;
        pacman) $NEED_SUDO pacman -Sy --noconfirm 2>/dev/null ;;
        apk)    $NEED_SUDO apk update 2>/dev/null ;;
        pkg)    pkg update -y 2>/dev/null ;;
        brew)   brew update 2>/dev/null ;;
    esac
}

install_git() {
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') ✓"
        return 0
    fi

    step "安装 Git..."
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get install -y -qq git ;;
        yum)    $NEED_SUDO yum install -y -q git ;;
        dnf)    $NEED_SUDO dnf install -y -q git ;;
        pacman) $NEED_SUDO pacman -S --noconfirm git ;;
        apk)    $NEED_SUDO apk add git ;;
        pkg)    pkg install -y git ;;
        brew)   brew install git ;;
        none)
            error "请手动安装 Git: ${CYAN}https://git-scm.com/downloads${NC}"
            exit 1
            ;;
        *)
            error "不支持的包管理器，请手动安装 Git"
            exit 1
            ;;
    esac
    command_exists git && info "Git 安装完成" || { error "Git 安装失败"; exit 1; }
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ "${ver:-0}" -ge "$MIN_NODE_VERSION" ]]
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) ✓"
        return 0
    fi

    command_exists node && warn "Node.js $(node -v) 版本过低，需要 v${MIN_NODE_VERSION}+"

    step "安装 Node.js..."

    case "$PLATFORM" in
        termux)
            pkg install -y nodejs 2>/dev/null
            ;;
        windows)
            if ! command_exists node; then
                echo ""
                error "请先安装 Node.js v${MIN_NODE_VERSION}+"
                echo -e "    下载地址: ${CYAN}https://nodejs.org/zh-cn/download${NC}"
                echo -e "    或使用: ${CYAN}winget install OpenJS.NodeJS.LTS${NC}"
                exit 1
            fi
            ;;
        macos)
            if command_exists brew; then
                brew install node@20
            else
                install_nodejs_binary
            fi
            ;;
        linux)
            if [[ "$IS_CHINA" == true ]]; then
                install_nodejs_binary "https://npmmirror.com/mirrors/node"
            else
                install_nodejs_standard
            fi
            ;;
    esac

    hash -r 2>/dev/null || true

    if check_node_version; then
        info "Node.js $(node -v) 安装完成"
    else
        error "Node.js 安装失败"
        exit 1
    fi

    # npm 镜像
    if [[ "$IS_CHINA" == true ]] && command_exists npm; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null
        info "npm 镜像已设置为 npmmirror"
    fi
}

install_nodejs_standard() {
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
        *)      install_nodejs_binary ;;
    esac
}

install_nodejs_binary() {
    local mirror="${1:-https://nodejs.org/dist}"
    local node_ver="v20.18.0"
    local arch=""
    local os_part="linux"

    case "$(uname -m)" in
        x86_64|amd64)  arch="x64"    ;;
        aarch64|arm64) arch="arm64"  ;;
        armv7l)        arch="armv7l" ;;
        *)             error "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
    esac

    [[ "$PLATFORM" == "macos" ]] && os_part="darwin"

    local filename="node-${node_ver}-${os_part}-${arch}.tar.xz"
    local download_url="${mirror}/${node_ver}/${filename}"
    info "下载: $download_url"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if curl -fSL --progress-bar -o "${tmp_dir}/${filename}" "$download_url"; then
        info "正在安装..."
        cd "$tmp_dir"
        tar xf "$filename"
        local dir_name="node-${node_ver}-${os_part}-${arch}"
        if [[ "$PLATFORM" == "termux" ]]; then
            cp -rf "${dir_name}"/bin/* "$PREFIX/bin/" 2>/dev/null || true
            cp -rf "${dir_name}"/lib/* "$PREFIX/lib/" 2>/dev/null || true
        else
            get_sudo
            $NEED_SUDO cp -rf "${dir_name}"/{bin,include,lib} /usr/local/ 2>/dev/null || true
            [[ -d "${dir_name}/share" ]] && $NEED_SUDO cp -rf "${dir_name}/share" /usr/local/ 2>/dev/null || true
        fi
        cd - >/dev/null
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
    else
        rm -rf "$tmp_dir"
        error "Node.js 下载失败"
        exit 1
    fi
}

install_dependencies() {
    step "检查并安装依赖..."

    if [[ "$PLATFORM" != "windows" && "$PLATFORM" != "termux" ]]; then
        get_sudo
        update_pkg_cache
        case "$PKG_MANAGER" in
            apt)    $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils ;;
            yum)    $NEED_SUDO yum install -y -q curl wget tar xz ;;
            dnf)    $NEED_SUDO dnf install -y -q curl wget tar xz ;;
            pacman) $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz ;;
            apk)    $NEED_SUDO apk add curl wget tar xz ;;
            brew)   : ;;
        esac
    elif [[ "$PLATFORM" == "termux" ]]; then
        pkg install -y curl wget tar 2>/dev/null || true
    fi

    install_git
    install_nodejs
}

# ==================== 配置文件操作 ====================

init_config_file() {
    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            info "已从 default.yaml 生成 config.yaml"
        else
            error "未找到 default.yaml"
            exit 1
        fi
    fi

    # 清除 Windows 换行符
    sed_i 's/\r$//' "$config_file" 2>/dev/null || true

    # 确保新增配置项存在
    ensure_yaml_key "enableUserAccounts" "false" "$config_file"
    ensure_yaml_key "enableDiscreetLogin" "false" "$config_file"
}

configure_sillytavern() {
    step "配置 SillyTavern..."

    local config_file="$INSTALL_DIR/config.yaml"
    init_config_file

    echo ""
    divider
    echo -e "  ${BOLD}配置向导${NC}"
    divider
    echo ""

    # === 监听 ===
    echo -e "  ${YELLOW}● 监听设置${NC}"
    echo -e "    ${DIM}开启 = 允许局域网/外网访问  |  关闭 = 仅本机访问${NC}"
    echo ""
    local listen_enabled=false
    if confirm "开启监听 (允许远程访问)?"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        info "已开启监听"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "仅本机访问"
    fi

    # === 端口 ===
    echo ""
    local port
    port=$(read_input "端口号" "8000")
    set_yaml_val "port" "$port" "$config_file"
    info "端口: $port"

    # === 白名单 ===
    echo ""
    echo -e "  ${YELLOW}● 白名单模式${NC}"
    echo -e "    ${DIM}开启 = 仅白名单 IP 可访问  |  远程访问建议关闭${NC}"
    echo ""
    if confirm "关闭白名单模式?"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        info "白名单已关闭"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "白名单保持开启"
    fi

    # === 基础认证 ===
    echo ""
    echo -e "  ${YELLOW}● 基础认证 (BasicAuth)${NC}"
    echo -e "    ${DIM}访问时需要输入用户名和密码${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "    ${RED}已开启远程访问，强烈建议开启认证${NC}"
    fi
    echo ""
    if confirm "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        echo ""
        local auth_user=""
        while [[ -z "$auth_user" ]]; do
            auth_user=$(read_input "认证用户名")
            [[ -z "$auth_user" ]] && warn "用户名不能为空"
        done

        local auth_pass
        auth_pass=$(read_password "认证密码")

        # 设置用户名和密码
        sed_i "/basicAuthUser:/,/^[^ #]/{
            s/\( *\)username:.*/\1username: \"${auth_user}\"/
            s/\( *\)password:.*/\1password: \"${auth_pass}\"/
        }" "$config_file"

        info "认证已开启 (用户: ${auth_user})"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "认证保持关闭"
    fi

    # === 防火墙 (仅在需要时) ===
    if [[ "$listen_enabled" == true && "$PLATFORM" == "linux" ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置已保存"
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"

    [[ "$PLATFORM" != "linux" ]] && return 0

    get_sudo
    step "检查防火墙..."

    local found=false

    # UFW
    if command_exists ufw; then
        local status
        status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$status" | grep -qi "active"; then
            found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW 端口 $port 已放行"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                info "UFW 已放行端口 $port/tcp"
            fi
        fi
    fi

    # firewalld
    if command_exists firewall-cmd; then
        local state
        state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$state" == "running" ]]; then
            found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld 端口 $port 已放行"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                info "firewalld 已放行端口 $port/tcp"
            fi
        fi
    fi

    # iptables fallback
    if [[ "$found" == false ]] && command_exists iptables; then
        local drops
        drops=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || true)
        if [[ "${drops:-0}" -gt 0 ]]; then
            found=true
            if ! $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
                info "iptables 已放行端口 $port/tcp"
                # 尝试持久化
                if command_exists iptables-save && [[ -d /etc/iptables ]]; then
                    $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
                fi
            else
                info "iptables 端口 $port 已放行"
            fi
        fi
    fi

    [[ "$found" == false ]] && info "未检测到活动防火墙"

    echo ""
    warn "云服务器用户请确保安全组中也放行了端口 ${port}/tcp"
}

remove_firewall_port() {
    local port="$1"
    [[ "$PLATFORM" != "linux" ]] && return 0
    get_sudo

    if command_exists ufw; then
        $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
    fi
    if command_exists firewall-cmd; then
        $NEED_SUDO firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null || true
        $NEED_SUDO firewall-cmd --reload 2>/dev/null || true
    fi
}

# ==================== 服务管理 ====================

setup_service() {
    echo ""
    divider
    echo -e "  ${BOLD}后台运行与开机自启${NC}"
    divider
    echo ""

    if [[ "$HAS_SYSTEMD" != true ]]; then
        case "$PLATFORM" in
            termux)
                warn "Termux 不支持 systemd"
                info "可使用 ${CYAN}nohup node server.js &${NC} 后台运行"
                ;;
            windows)
                warn "Windows 不支持 systemd 服务管理"
                info "可创建快捷方式或使用任务计划程序"
                ;;
            *)
                warn "当前系统不支持 systemd"
                info "可使用 screen/tmux 保持后台运行"
                ;;
        esac
        return 0
    fi

    # 显示当前状态
    local svc_exists=false
    local svc_enabled=false
    if systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        svc_exists=true
        systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && svc_enabled=true
    fi

    echo -e "  当前状态:"
    if [[ "$svc_exists" == true ]]; then
        echo -e "    systemd 服务: ${GREEN}已创建${NC}"
        echo -e "    开机自启:     $(format_bool "$svc_enabled")"
    else
        echo -e "    systemd 服务: ${DIM}未创建${NC}"
    fi
    echo ""

    local enable_service=false
    local enable_autostart=false

    if confirm "是否创建/更新后台运行服务?"; then
        enable_service=true
        echo ""
        if confirm "是否开启开机自启动?"; then
            enable_autostart=true
        fi
    else
        return 0
    fi

    if [[ "$enable_service" == true ]]; then
        get_sudo
        local node_path
        node_path=$(which node)

        $NEED_SUDO tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=SillyTavern Server
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
Group=$(id -gn "$CURRENT_USER")
WorkingDirectory=${INSTALL_DIR}
ExecStart=${node_path} server.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sillytavern
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

        $NEED_SUDO systemctl daemon-reload
        info "systemd 服务已创建"

        if [[ "$enable_autostart" == true ]]; then
            $NEED_SUDO systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
            info "开机自启已开启"
        else
            $NEED_SUDO systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
            info "开机自启未开启"
        fi
    fi
}

# ==================== 进程管理 ====================

find_st_pid() {
    local pid=""
    case "$PLATFORM" in
        linux|macos|termux)
            if command_exists pgrep; then
                pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
            fi
            if [[ -z "$pid" ]]; then
                pid=$(ps -eo pid,args 2>/dev/null | grep "node.*server\.js" | grep -v grep | awk '{print $1}' | head -1 || true)
            fi
            ;;
        windows)
            pid=$(ps -W 2>/dev/null | grep -i node | awk '{print $1}' | head -1 || true)
            ;;
    esac
    echo "$pid"
}

is_st_running() {
    if [[ "$HAS_SYSTEMD" == true ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    fi
    local pid
    pid=$(find_st_pid)
    [[ -n "$pid" ]]
}

show_access_info() {
    local port
    port=$(get_port)
    local listen_mode
    listen_mode=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")

    echo ""
    echo -e "  ${BOLD}访问地址:${NC}"
    echo -e "    本地:   ${CYAN}http://localhost:${port}${NC}"

    if [[ "$listen_mode" == "true" ]]; then
        local local_ip
        local_ip=$(get_local_ip)
        echo -e "    局域网: ${CYAN}http://${local_ip}:${port}${NC}"

        local public_ip
        public_ip=$(get_public_ip)
        if [[ -n "$public_ip" ]]; then
            echo -e "    公网:   ${CYAN}http://${public_ip}:${port}${NC}"
        else
            echo -e "    公网:   ${DIM}无法获取公网 IP${NC}"
        fi
    fi
}

start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    if is_st_running; then
        warn "SillyTavern 已在运行中"
        show_access_info
        return 0
    fi

    if [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "通过 systemd 启动..."
        get_sudo
        $NEED_SUDO systemctl start "$SERVICE_NAME"
        sleep 2
        if $NEED_SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
            success "SillyTavern 已启动"
            show_access_info
        else
            error "启动失败，请查看日志: journalctl -u $SERVICE_NAME -n 30"
        fi
    else
        local port
        port=$(get_port)
        step "前台启动 SillyTavern..."
        show_access_info
        echo ""
        warn "按 Ctrl+C 停止运行"
        echo ""
        cd "$INSTALL_DIR"
        node server.js
        cd - >/dev/null
    fi
}

stop_sillytavern() {
    if [[ "$HAS_SYSTEMD" == true ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "停止 SillyTavern 服务..."
        get_sudo
        $NEED_SUDO systemctl stop "$SERVICE_NAME"
        success "已停止"
        return 0
    fi

    local pid
    pid=$(find_st_pid)
    if [[ -n "$pid" ]]; then
        step "停止进程 (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        success "已停止"
    else
        info "SillyTavern 未在运行"
    fi
}

restart_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    if [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "重启 SillyTavern..."
        get_sudo
        $NEED_SUDO systemctl restart "$SERVICE_NAME"
        sleep 2
        if $NEED_SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
            success "重启完成"
            show_access_info
        else
            error "重启失败"
        fi
    else
        stop_sillytavern
        sleep 1
        start_sillytavern
    fi
}

# ==================== 状态显示 ====================

show_status() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    print_banner

    echo -e "  ${BOLD}运行状态${NC}"
    divider
    echo ""

    # 基本信息
    local version="" branch=""
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')
    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")

    echo -e "    安装目录:   ${INSTALL_DIR}"
    echo -e "    版本:       ${version:-未知}"
    echo -e "    分支:       ${branch:-未知}"

    # 运行状态
    echo ""
    if [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "    运行状态:   ${GREEN}● 运行中${NC}"
        else
            echo -e "    运行状态:   ${RED}● 已停止${NC}"
        fi
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "    开机自启:   ${GREEN}● 已启用${NC}"
        else
            echo -e "    开机自启:   ${DIM}● 未启用${NC}"
        fi
    else
        local pid
        pid=$(find_st_pid)
        if [[ -n "$pid" ]]; then
            echo -e "    运行状态:   ${GREEN}● 运行中${NC} (PID: $pid)"
        else
            echo -e "    运行状态:   ${RED}● 未运行${NC}"
        fi
        echo -e "    服务模式:   ${DIM}未配置 systemd${NC}"
    fi

    # 配置
    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        echo ""
        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
        whitelist_val=$(get_yaml_val "whitelistMode" "$INSTALL_DIR/config.yaml")
        auth_val=$(get_yaml_val "basicAuthMode" "$INSTALL_DIR/config.yaml")
        port_val=$(get_port)
        ua_val=$(get_yaml_val "enableUserAccounts" "$INSTALL_DIR/config.yaml")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$INSTALL_DIR/config.yaml")

        echo -e "    监听模式:   $(format_bool "$listen_val")"
        echo -e "    端口:       ${CYAN}${port_val}${NC}"
        echo -e "    白名单:     $(format_bool "$whitelist_val")"
        echo -e "    基础认证:   $(format_bool "$auth_val")"
        echo -e "    多用户账户: $(format_bool "$ua_val")"
        echo -e "    隐匿登录:   $(format_bool "$dl_val")"

        show_access_info
    fi
}

# ==================== 更新管理 ====================

update_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    step "检查更新..."

    cd "$INSTALL_DIR"

    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "release")

    # 设置代理 URL (如果需要)
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    # 获取远程信息
    if ! git fetch origin 2>/dev/null; then
        warn "无法连接远程仓库，请检查网络"
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null
        return 1
    fi

    local current_commit remote_commit behind
    current_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "origin/$branch" 2>/dev/null)

    echo ""
    echo -e "    当前分支: ${CYAN}${branch}${NC}"
    echo -e "    本地提交: ${DIM}${current_commit:0:8}${NC}"
    echo -e "    远程提交: ${DIM}${remote_commit:0:8}${NC}"

    if [[ "$current_commit" == "$remote_commit" ]]; then
        echo ""
        success "当前已是最新版本，无需更新"
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null
        return 0
    fi

    behind=$(git rev-list HEAD.."origin/$branch" --count 2>/dev/null || echo "?")
    echo ""
    info "发现 ${YELLOW}${behind}${NC} 个新提交"

    # 显示最近的更新内容
    echo ""
    echo -e "  ${DIM}最近更新:${NC}"
    git log HEAD.."origin/$branch" --oneline --max-count=5 2>/dev/null | while read -r line; do
        echo -e "    ${DIM}• ${line}${NC}"
    done
    echo ""

    if ! confirm "是否更新?"; then
        info "已取消更新"
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null
        return 0
    fi

    # 停止运行中的服务
    if is_st_running; then
        warn "SillyTavern 正在运行，先停止..."
        stop_sillytavern
    fi

    # 备份配置
    info "备份配置文件..."
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "备份: $backup_dir"

    # 拉取更新
    info "拉取更新..."
    if git pull --ff-only 2>/dev/null; then
        success "代码更新完成"
    else
        warn "快速合并失败，尝试强制更新..."
        git fetch --all 2>/dev/null
        git reset --hard "origin/$branch" 2>/dev/null
        success "代码强制更新完成"
    fi

    # 恢复代理 URL
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null

    # 清理换行符
    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    # 更新依赖
    info "更新 npm 依赖..."
    npm install --no-audit --no-fund 2>&1 | tail -3

    # 恢复配置
    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        info "配置已恢复"
    fi

    cd - >/dev/null

    success "更新完成!"

    echo ""
    if is_st_running || { [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; }; then
        if confirm "是否立即启动?"; then
            start_sillytavern
        fi
    fi
}

# ==================== 配置修改菜单 ====================

modify_config_menu() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件不存在"
        return 1
    fi

    # 确保新配置项存在
    ensure_yaml_key "enableUserAccounts" "false" "$config_file"
    ensure_yaml_key "enableDiscreetLogin" "false" "$config_file"

    while true; do
        print_banner

        echo -e "  ${BOLD}配置管理${NC}"
        divider
        echo ""

        # 读取当前值
        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        port_val=$(get_port)
        ua_val=$(get_yaml_val "enableUserAccounts" "$config_file")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$config_file")

        echo -e "  ${BOLD}当前配置:${NC}"
        echo ""
        echo -e "    监听模式       $(format_bool "$listen_val")"
        echo -e "    端口           ${CYAN}${port_val}${NC}"
        echo -e "    白名单模式     $(format_bool "$whitelist_val")"
        echo -e "    基础认证       $(format_bool "$auth_val")"
        echo -e "    多用户账户     $(format_bool "$ua_val")"
        echo -e "    隐匿登录       $(format_bool "$dl_val")"
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 切换监听模式"
        echo -e "  ${GREEN}2)${NC} 修改端口"
        echo -e "  ${GREEN}3)${NC} 切换白名单模式"
        echo -e "  ${GREEN}4)${NC} 基础认证设置"
        echo -e "  ${GREEN}5)${NC} 切换多用户账户    ${DIM}(enableUserAccounts)${NC}"
        echo -e "  ${GREEN}6)${NC} 切换隐匿登录      ${DIM}(enableDiscreetLogin)${NC}"
        echo -e "  ${GREEN}7)${NC} 编辑完整配置文件"
        echo -e "  ${GREEN}8)${NC} 重置为默认配置"
        if [[ "$PLATFORM" == "linux" ]]; then
            echo -e "  ${GREEN}9)${NC} 防火墙放行管理"
        fi
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "请选择")

        case "$choice" in
            1)
                echo ""
                echo -e "  当前: 监听模式 $(format_bool "$listen_val")"
                echo ""
                if confirm "切换监听模式?"; then
                    if [[ "$listen_val" == "true" ]]; then
                        set_yaml_val "listen" "false" "$config_file"
                        info "已关闭监听"
                    else
                        set_yaml_val "listen" "true" "$config_file"
                        info "已开启监听"
                        [[ "$PLATFORM" == "linux" ]] && open_firewall_port "$port_val"
                    fi
                fi
                ;;
            2)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                echo ""
                local new_port
                new_port=$(read_input "新端口号" "$port_val")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ "$new_port" -ge 1 ]] && [[ "$new_port" -le 65535 ]]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    info "端口已改为: $new_port"
                    if [[ "$(get_yaml_val "listen" "$config_file")" == "true" && "$PLATFORM" == "linux" ]]; then
                        open_firewall_port "$new_port"
                    fi
                else
                    error "无效端口: $new_port (1-65535)"
                fi
                ;;
            3)
                echo ""
                echo -e "  当前: 白名单模式 $(format_bool "$whitelist_val")"
                echo ""
                if confirm "切换白名单模式?"; then
                    if [[ "$whitelist_val" == "true" ]]; then
                        set_yaml_val "whitelistMode" "false" "$config_file"
                        info "白名单已关闭"
                    else
                        set_yaml_val "whitelistMode" "true" "$config_file"
                        info "白名单已开启"
                    fi
                fi
                ;;
            4)
                echo ""
                echo -e "  当前: 基础认证 $(format_bool "$auth_val")"
                echo ""
                if [[ "$auth_val" == "true" ]]; then
                    echo -e "  ${GREEN}1)${NC} 关闭认证"
                    echo -e "  ${GREEN}2)${NC} 修改用户名/密码"
                    echo ""
                    local sub
                    sub=$(read_input "请选择" "1")
                    case "$sub" in
                        1)
                            set_yaml_val "basicAuthMode" "false" "$config_file"
                            info "认证已关闭"
                            ;;
                        2)
                            local u=""
                            while [[ -z "$u" ]]; do
                                u=$(read_input "新用户名")
                                [[ -z "$u" ]] && warn "用户名不能为空"
                            done
                            local p
                            p=$(read_password "新密码")
                            sed_i "/basicAuthUser:/,/^[^ #]/{
                                s/\( *\)username:.*/\1username: \"${u}\"/
                                s/\( *\)password:.*/\1password: \"${p}\"/
                            }" "$config_file"
                            info "认证信息已更新 (用户: $u)"
                            ;;
                    esac
                else
                    if confirm "开启基础认证?"; then
                        set_yaml_val "basicAuthMode" "true" "$config_file"
                        local u=""
                        while [[ -z "$u" ]]; do
                            u=$(read_input "认证用户名")
                            [[ -z "$u" ]] && warn "用户名不能为空"
                        done
                        local p
                        p=$(read_password "认证密码")
                        sed_i "/basicAuthUser:/,/^[^ #]/{
                            s/\( *\)username:.*/\1username: \"${u}\"/
                            s/\( *\)password:.*/\1password: \"${p}\"/
                        }" "$config_file"
                        info "认证已开启 (用户: $u)"
                    fi
                fi
                ;;
            5)
                echo ""
                echo -e "  当前: 多用户账户 $(format_bool "$ua_val")"
                echo -e "  ${DIM}启用后支持多用户独立登录和数据隔离${NC}"
                echo ""
                if confirm "切换多用户账户?"; then
                    if [[ "$ua_val" == "true" ]]; then
                        set_yaml_val "enableUserAccounts" "false" "$config_file"
                        info "多用户账户已关闭"
                    else
                        set_yaml_val "enableUserAccounts" "true" "$config_file"
                        info "多用户账户已开启"
                    fi
                fi
                ;;
            6)
                echo ""
                echo -e "  当前: 隐匿登录 $(format_bool "$dl_val")"
                echo -e "  ${DIM}启用后登录页面不显示 SillyTavern 标识${NC}"
                echo ""
                if confirm "切换隐匿登录?"; then
                    if [[ "$dl_val" == "true" ]]; then
                        set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                        info "隐匿登录已关闭"
                    else
                        set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                        info "隐匿登录已开启"
                    fi
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                command_exists vi || editor="vim"
                if [[ "$PLATFORM" == "windows" ]] && command_exists notepad; then
                    editor="notepad"
                fi
                $editor "$config_file"
                # 清理换行符
                sed_i 's/\r$//' "$config_file" 2>/dev/null || true
                ;;
            8)
                if confirm "确定重置为默认配置?"; then
                    if [[ -f "$INSTALL_DIR/default.yaml" ]]; then
                        cp "$INSTALL_DIR/default.yaml" "$config_file"
                        sed_i 's/\r$//' "$config_file" 2>/dev/null || true
                        ensure_yaml_key "enableUserAccounts" "false" "$config_file"
                        ensure_yaml_key "enableDiscreetLogin" "false" "$config_file"
                        info "已重置为默认配置"
                    else
                        error "default.yaml 不存在"
                    fi
                fi
                ;;
            9)
                if [[ "$PLATFORM" == "linux" ]]; then
                    local fw_port
                    fw_port=$(get_port)
                    open_firewall_port "$fw_port"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                warn "无效选项"
                ;;
        esac

        # 提示重启
        echo ""
        if is_st_running && [[ "$choice" != "0" && "$choice" != "7" && "$choice" != "9" ]]; then
            warn "配置修改后需重启才能生效"
            if confirm "立即重启?"; then
                restart_sillytavern
            fi
        fi

        pause
    done
}

# ==================== 日志查看 ====================

view_logs() {
    if [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "最近日志:"
        echo ""
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager 2>/dev/null || warn "无法读取日志"
    else
        warn "未使用 systemd 服务，无法查看系统日志"
        info "请直接查看前台运行时的终端输出"
    fi
}

# ==================== 安装检测 ====================

check_installed() {
    load_config
    if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/server.js" ]]; then
        return 0
    fi
    if [[ -d "$DEFAULT_INSTALL_DIR" && -f "$DEFAULT_INSTALL_DIR/server.js" ]]; then
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
        save_config
        return 0
    fi
    return 1
}

load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        source "$KSILLY_CONF" 2>/dev/null || true
        INSTALL_DIR="${KSILLY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    else
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    fi
}

save_config() {
    cat > "$KSILLY_CONF" <<EOF
KSILLY_INSTALL_DIR="${INSTALL_DIR}"
KSILLY_IS_CHINA="${IS_CHINA}"
KSILLY_GITHUB_PROXY="${GITHUB_PROXY}"
EOF
}

# ==================== 脚本自保存 ====================

save_script_to_install_dir() {
    [[ -z "$INSTALL_DIR" ]] && return
    [[ ! -d "$INSTALL_DIR" ]] && return

    local target="$INSTALL_DIR/ksilly.sh"
    local need_save=false

    if [[ ! -f "$target" ]]; then
        need_save=true
    else
        local saved_ver
        saved_ver=$(grep '^SCRIPT_VERSION=' "$target" 2>/dev/null | head -1 | cut -d'"' -f2)
        [[ "$saved_ver" != "$SCRIPT_VERSION" ]] && need_save=true
    fi

    if [[ "$need_save" == true ]]; then
        local url="$SCRIPT_RAW_URL"
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            url="${GITHUB_PROXY}${SCRIPT_RAW_URL}"
        fi

        if curl -fsSL "$url" -o "$target" 2>/dev/null; then
            chmod +x "$target" 2>/dev/null || true
            info "管理脚本已保存到: ${CYAN}${target}${NC}"
            info "后续可运行: ${CYAN}bash ${target}${NC}"
        fi
    fi
}

# ==================== 克隆仓库 ====================

clone_sillytavern() {
    step "克隆 SillyTavern..."

    INSTALL_DIR=$(read_input "安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "目录已存在 SillyTavern"
            if confirm "删除并重新安装?"; then
                rm -rf "$INSTALL_DIR"
            else
                info "保留现有安装"
                return 0
            fi
        else
            error "目录已存在且不是 SillyTavern: $INSTALL_DIR"
            exit 1
        fi
    fi

    echo ""
    echo -e "  选择分支:"
    echo -e "    ${GREEN}1)${NC} release ${DIM}— 稳定版 (推荐)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging ${DIM}— 开发版 (最新功能)${NC}"
    echo ""
    local bc=""
    while [[ "$bc" != "1" && "$bc" != "2" ]]; do
        bc=$(read_input "选择 (1/2)" "1")
    done

    local branch="release"
    [[ "$bc" == "2" ]] && branch="staging"
    info "分支: $branch"

    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")
    info "地址: $repo_url"

    if ! git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" 2>&1; then
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理失败，尝试直连..."
            git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR" 2>&1 || {
                error "克隆失败，请检查网络"
                exit 1
            }
        else
            error "克隆失败"
            exit 1
        fi
    fi
    success "仓库克隆完成"

    # 规范化换行符
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖..."
    cd "$INSTALL_DIR"
    if npm install --no-audit --no-fund 2>&1 | tail -5; then
        success "依赖安装完成"
    else
        error "npm install 失败"
        exit 1
    fi
    cd - >/dev/null

    save_config
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    echo ""
    warn "即将卸载 SillyTavern"
    echo -e "    目录: ${INSTALL_DIR}"
    echo ""

    confirm "确定要卸载吗? 此操作不可恢复!" || { info "已取消"; return 0; }
    confirm "再次确认: 删除所有数据?" || { info "已取消"; return 0; }

    # 停止
    stop_sillytavern

    # 防火墙
    local port
    port=$(get_port 2>/dev/null || echo "8000")
    remove_firewall_port "$port"

    # systemd
    if [[ "$HAS_SYSTEMD" == true ]] && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "移除 systemd 服务..."
        get_sudo
        $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        $NEED_SUDO systemctl daemon-reload
        info "服务已移除"
    fi

    # 备份提示
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

    step "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "卸载完成"
}

# ==================== 完整安装流程 ====================

full_install() {
    print_banner

    echo -e "  ${BOLD}${GREEN}开始安装 SillyTavern${NC}"
    divider
    echo ""

    detect_os
    info "平台: ${PLATFORM} (${OS_TYPE:-通用})"

    detect_network
    echo ""

    install_dependencies
    echo ""

    clone_sillytavern
    echo ""

    configure_sillytavern
    echo ""

    setup_service
    echo ""

    save_config
    save_script_to_install_dir

    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${GREEN}🎉 安装完成!${NC}"
    show_access_info
    echo ""
    divider
    echo ""

    if confirm "立即启动 SillyTavern?"; then
        start_sillytavern
    else
        echo ""
        info "稍后启动方式:"
        if [[ "$HAS_SYSTEMD" == true ]]; then
            echo -e "    ${CYAN}sudo systemctl start ${SERVICE_NAME}${NC}"
        fi
        echo -e "    ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
        echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
    fi
}

# ==================== 主菜单 ====================

main_menu() {
    while true; do
        print_banner
        load_config

        # 状态栏
        if check_installed; then
            local ver="" status_icon="${RED}●${NC}" status_text="已停止"
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                ver=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"\([0-9.]*\)".*/\1/')

            if is_st_running; then
                status_icon="${GREEN}●${NC}"
                status_text="运行中"
            fi

            local branch=""
            [[ -d "$INSTALL_DIR/.git" ]] && branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)

            echo -e "  ${status_icon} ${BOLD}v${ver:-?}${NC} ${DIM}(${branch:-?})${NC} — ${status_text}"
            echo -e "  ${DIM}${INSTALL_DIR}${NC}"
        else
            echo -e "  ${YELLOW}●${NC} 未安装"
        fi
        echo ""
        divider
        echo ""

        echo -e "  ${BOLD}安装管理${NC}"
        echo -e "   ${GREEN}1)${NC}  全新安装"
        echo -e "   ${GREEN}2)${NC}  检查更新"
        echo -e "   ${GREEN}3)${NC}  卸载"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "   ${GREEN}4)${NC}  启动"
        echo -e "   ${GREEN}5)${NC}  停止"
        echo -e "   ${GREEN}6)${NC}  重启"
        echo ""
        echo -e "  ${BOLD}配置维护${NC}"
        echo -e "   ${GREEN}7)${NC}  查看状态"
        echo -e "   ${GREEN}8)${NC}  修改配置"
        echo -e "   ${GREEN}9)${NC}  查看日志"
        echo -e "  ${GREEN}10)${NC}  服务管理"
        echo ""
        echo -e "   ${RED}0)${NC}  退出"
        echo ""
        divider

        local choice
        choice=$(read_input "请选择")

        case "$choice" in
            1)
                if check_installed; then
                    warn "SillyTavern 已安装"
                    confirm "是否重新安装?" || continue
                fi
                full_install
                pause
                ;;
            2)
                detect_os
                detect_network
                update_sillytavern
                pause
                ;;
            3)
                detect_os
                uninstall_sillytavern
                pause
                ;;
            4)
                start_sillytavern
                pause
                ;;
            5)
                stop_sillytavern
                pause
                ;;
            6)
                restart_sillytavern
                pause
                ;;
            7)
                show_status
                pause
                ;;
            8)
                modify_config_menu
                ;;
            9)
                view_logs
                pause
                ;;
            10)
                if ! check_installed; then
                    error "请先安装 SillyTavern"
                else
                    detect_os
                    setup_service
                fi
                pause
                ;;
            0)
                echo ""
                info "再见~ 👋"
                echo ""
                exit 0
                ;;
            *)
                warn "无效选项"
                sleep 1
                ;;
        esac
    done
}

# ==================== 入口 ====================

main() {
    detect_platform

    if [[ "$PLATFORM" == "unknown" ]]; then
        echo -e "${RED}不支持的操作系统${NC}"
        echo "支持: Linux / macOS / Termux / Windows (Git Bash)"
        exit 1
    fi

    load_config

    # 每次运行尝试保存脚本
    if check_installed; then
        save_script_to_install_dir
    fi

    case "${1:-}" in
        install)   detect_os; detect_network; full_install ;;
        update)    detect_os; detect_network; load_config; update_sillytavern ;;
        start)     start_sillytavern ;;
        stop)      stop_sillytavern ;;
        restart)   restart_sillytavern ;;
        status)    show_status ;;
        uninstall) detect_os; uninstall_sillytavern ;;
        "")        main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|uninstall}"
            echo "  不带参数进入交互式菜单"
            exit 1
            ;;
    esac
}

main "$@"
