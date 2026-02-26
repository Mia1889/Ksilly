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
#  版本: 2.2.0
#

# ==================== 全局常量 ====================
SCRIPT_VERSION="2.2.0"
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

CADDY_CADDYFILE="/etc/caddy/Caddyfile"
CADDY_CADDYFILE_BACKUP="/etc/caddy/Caddyfile.bak.ksilly"
CADDY_VERSION_FALLBACK="2.9.1"

# ==================== 插件定义 ====================
PLUGIN_DIR_NAME="public/scripts/extensions/third-party"

PLUGIN_1_NAME="酒馆助手 (JS-Slash-Runner)"
PLUGIN_1_FOLDER="JS-Slash-Runner"
PLUGIN_1_REPO_INTL="https://github.com/N0VI028/JS-Slash-Runner.git"
PLUGIN_1_REPO_CN="https://gitlab.com/novi028/JS-Slash-Runner"

PLUGIN_2_NAME="提示词模板 (ST-Prompt-Template)"
PLUGIN_2_FOLDER="ST-Prompt-Template"
PLUGIN_2_REPO_INTL="https://github.com/zonde306/ST-Prompt-Template.git"
PLUGIN_2_REPO_CN="https://codeberg.org/zonde306/ST-Prompt-Template.git"

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PINK='\033[38;5;213m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ==================== 全局变量 ====================
IS_CHINA=false
IS_TERMUX=false
GITHUB_PROXY=""
INSTALL_DIR=""
OS_TYPE=""
PKG_MANAGER=""
CURRENT_USER=$(whoami)
NEED_SUDO=""
UPDATE_BEHIND=0
CACHED_PUBLIC_IP=""
HTTPS_ENABLED=false
HTTPS_DOMAIN=""

# ==================== 旋转动画 ====================

spin() {
    local msg="$1"
    shift
    local tmplog
    tmplog=$(mktemp)

    "$@" > "$tmplog" 2>&1 &
    local cmd_pid=$!

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local start_time=$SECONDS

    tput civis 2>/dev/null

    while kill -0 "$cmd_pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_time ))
        printf "\r  ${PINK}%s${NC} %s ${DIM}(%ds)${NC}  " "${frames[i++ % ${#frames[@]}]}" "$msg" "$elapsed"
        sleep 0.1
    done

    wait "$cmd_pid"
    local ret=$?

    printf "\r\033[K"
    tput cnorm 2>/dev/null

    if [[ $ret -ne 0 ]]; then
        tail -3 "$tmplog" 2>/dev/null | while IFS= read -r line; do
            [[ -n "$line" ]] && echo -e "    ${DIM}${line}${NC}"
        done
    fi

    rm -f "$tmplog"
    return $ret
}

spin_cmd() {
    local msg="$1"
    local cmd="$2"
    local tmplog
    tmplog=$(mktemp)

    bash -c "$cmd" > "$tmplog" 2>&1 &
    local cmd_pid=$!

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local start_time=$SECONDS

    tput civis 2>/dev/null

    while kill -0 "$cmd_pid" 2>/dev/null; do
        local elapsed=$(( SECONDS - start_time ))
        printf "\r  ${PINK}%s${NC} %s ${DIM}(%ds)${NC}  " "${frames[i++ % ${#frames[@]}]}" "$msg" "$elapsed"
        sleep 0.1
    done

    wait "$cmd_pid"
    local ret=$?

    printf "\r\033[K"
    tput cnorm 2>/dev/null

    if [[ $ret -ne 0 ]]; then
        tail -3 "$tmplog" 2>/dev/null | while IFS= read -r line; do
            [[ -n "$line" ]] && echo -e "    ${DIM}${line}${NC}"
        done
    fi

    rm -f "$tmplog"
    return $ret
}

# ==================== 信号处理 ====================
trap 'printf "\r\033[K"; tput cnorm 2>/dev/null; echo ""; warn "哼~杂鱼按 Ctrl+C 跑掉了♡"; exit 130' INT

# ==================== 输出函数 ====================

print_banner() {
    clear
    echo -e "${PINK}"
    cat << 'BANNER'
  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
  ██║  ██╗███████║██║███████╗███████╗██║
  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}才不是为杂鱼准备的部署脚本呢${NC} ${PINK}♡${NC} ${DIM}v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}by Mia1889 · github.com/Mia1889/Ksilly${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
ask()     { echo -e "  ${PINK}?${NC} $1"; }
success() { echo -e "  ${PINK}★${NC} $1"; }

step() {
    echo ""
    echo -e "  ${PINK}▸ $1${NC}"
}

divider() {
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
}

# ==================== 输入函数 ====================

confirm() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${PINK}?${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) warn "只能输 y 或 n 哦~这都不懂吗杂鱼♡" ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result=""
    if [[ -n "$default" ]]; then
        echo -ne "  ${PINK}→${NC} ${prompt} ${DIM}[$default]${NC}: " >&2
    else
        echo -ne "  ${PINK}→${NC} ${prompt}: " >&2
    fi
    read -r result
    [[ -z "$result" && -n "$default" ]] && result="$default"
    echo "$result"
}

read_password() {
    local prompt="$1"
    local result=""
    echo -e "  ${YELLOW}⚠ 输入密码的时候屏幕不会显示字符哦~别以为坏掉了笨蛋♡${NC}" >&2
    while [[ -z "$result" ]]; do
        echo -ne "  ${PINK}→${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "密码不能为空啦~再输一次♡"
        fi
    done
    echo "$result"
}

pause_key() {
    echo ""
    read -rp "  按 Enter 继续~杂鱼♡ "
}

# ==================== 工具函数 ====================

command_exists() { command -v "$1" &>/dev/null; }

get_sudo() {
    if [[ "$IS_TERMUX" == true ]]; then
        NEED_SUDO=""
        return 0
    fi
    if [[ "$EUID" -eq 0 ]]; then
        NEED_SUDO=""
    elif command_exists sudo; then
        NEED_SUDO="sudo"
    else
        error "需要 root 权限但找不到 sudo~杂鱼是不是忘了装♡"
        return 1
    fi
}

# ==================== YAML 配置辅助函数 ====================

get_yaml_val() {
    local key="$1" file="$2"
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | \
        sed "s/^[[:space:]]*${key}:[[:space:]]*//" | \
        tr -d '\r\n' | sed 's/^["'"'"']\(.*\)["'"'"']$/\1/' | \
        sed 's/[[:space:]]*$//'
}

set_yaml_val() {
    local key="$1" value="$2" file="$3"
    if grep -qE "^\s*${key}:" "$file" 2>/dev/null; then
        sed -i "s|^\([[:space:]]*\)${key}:.*|\1${key}: ${value}|" "$file"
    else
        echo "${key}: ${value}" >> "$file"
    fi
}

get_port() {
    local port
    port=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml")
    [[ "$port" =~ ^[0-9]+$ ]] || port="8000"
    echo "$port"
}

format_bool() {
    local val="${1:-false}"
    if [[ "$val" == "true" ]]; then
        echo -e "${GREEN}开启${NC}"
    else
        echo -e "${DIM}关闭${NC}"
    fi
}

# ==================== IP 获取函数 ====================

get_local_ip() {
    local ip=""
    if [[ "$IS_TERMUX" == true ]]; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
        [[ -z "$ip" ]] && ip=$(ip -4 addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
        echo "${ip:-无法获取}"
        return
    fi
    if command_exists ip; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
        [[ -z "$ip" ]] && ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi
    [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi
    echo "${ip:-无法获取}"
}

get_public_ip() {
    if [[ -n "$CACHED_PUBLIC_IP" ]]; then
        echo "$CACHED_PUBLIC_IP"
        return 0
    fi
    local services=(
        "https://ifconfig.me"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
        "https://icanhazip.com"
    )
    local ip=""
    for svc in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 3 --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            CACHED_PUBLIC_IP="$ip"
            echo "$ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# ==================== 访问信息显示 ====================

show_access_info() {
    local port config_file="$INSTALL_DIR/config.yaml"
    port=$(get_port)
    local listen
    listen=$(get_yaml_val "listen" "$config_file")

    echo ""
    echo -e "  ${BOLD}访问地址 (记好了哦杂鱼♡):${NC}"
    echo -e "    本机访问   → ${CYAN}http://127.0.0.1:${port}${NC}"

    if [[ "$listen" == "true" ]]; then
        local local_ip public_ip
        local_ip=$(get_local_ip)
        public_ip=$(get_public_ip)

        [[ "$local_ip" != "无法获取" ]] && \
            echo -e "    局域网访问 → ${CYAN}http://${local_ip}:${port}${NC}"

        if [[ -n "$public_ip" ]]; then
            echo -e "    公网访问   → ${CYAN}http://${public_ip}:${port}${NC}"
        else
            echo -e "    公网访问   → ${YELLOW}获取不到公网IP~杂鱼自己查吧♡${NC}"
        fi

        if [[ "$HTTPS_ENABLED" == true ]]; then
            echo ""
            echo -e "  ${BOLD}${GREEN}🔒 HTTPS 安全访问:${NC}"
            if [[ -n "$HTTPS_DOMAIN" ]]; then
                echo -e "    推荐访问   → ${CYAN}https://${HTTPS_DOMAIN}${NC}"
            else
                if [[ -n "$public_ip" ]]; then
                    echo -e "    HTTPS 访问 → ${CYAN}https://${public_ip}${NC}"
                fi
                [[ "$local_ip" != "无法获取" ]] && \
                    echo -e "    局域网HTTPS→ ${CYAN}https://${local_ip}${NC}"
                echo -e "    ${DIM}(自签名证书~浏览器警告点「继续」即可♡)${NC}"
            fi
        fi
    fi
}

# ==================== 配置管理 ====================

load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        source "$KSILLY_CONF" 2>/dev/null || true
        INSTALL_DIR="${KSILLY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
        HTTPS_ENABLED="${KSILLY_HTTPS_ENABLED:-false}"
        HTTPS_DOMAIN="${KSILLY_HTTPS_DOMAIN:-}"
    else
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
        HTTPS_ENABLED=false
        HTTPS_DOMAIN=""
    fi
}

save_config() {
    cat > "$KSILLY_CONF" << EOF
KSILLY_INSTALL_DIR="${INSTALL_DIR}"
KSILLY_IS_CHINA="${IS_CHINA}"
KSILLY_GITHUB_PROXY="${GITHUB_PROXY}"
KSILLY_HTTPS_ENABLED="${HTTPS_ENABLED}"
KSILLY_HTTPS_DOMAIN="${HTTPS_DOMAIN}"
EOF
}

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

save_script() {
    [[ -z "$INSTALL_DIR" || ! -d "$INSTALL_DIR" ]] && return 1
    local target="$INSTALL_DIR/ksilly.sh"
    local url="$SCRIPT_RAW_URL"
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && url="${GITHUB_PROXY}${url}"
    if curl -fsSL --connect-timeout 10 "$url" -o "$target" 2>/dev/null; then
        chmod +x "$target"
        return 0
    fi
    if [[ "$IS_CHINA" == true ]]; then
        if curl -fsSL --connect-timeout 10 "$SCRIPT_RAW_URL" -o "$target" 2>/dev/null; then
            chmod +x "$target"
            return 0
        fi
    fi
    return 1
}

# ==================== 环境检测 ====================

detect_os() {
    step "人家看看杂鱼用的什么环境~"
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        IS_TERMUX=true
        OS_TYPE="termux"
        PKG_MANAGER="pkg"
        NEED_SUDO=""
        info "Termux 啊~用手机玩的杂鱼♡"
        return
    fi
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE="$ID"
    elif [[ -f /etc/redhat-release ]]; then
        OS_TYPE="centos"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_TYPE="macos"
    else
        OS_TYPE="unknown"
    fi
    case "$OS_TYPE" in
        ubuntu|debian|linuxmint|pop)
            PKG_MANAGER="apt"
            info "Debian/Ubuntu ($OS_TYPE) ~还行吧♡"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "RHEL/CentOS ($OS_TYPE) ~老古董呢♡"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "Arch ($OS_TYPE) ~哦~会装Arch的杂鱼♡"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "Alpine ~小巧的系统呢♡"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "macOS ~有钱的杂鱼♡"
            ;;
        *)
            warn "这什么奇怪的系统: $OS_TYPE ~人家试试看吧♡"
            PKG_MANAGER="unknown"
            ;;
    esac
}

detect_network() {
    step "帮杂鱼看看网络环境~"
    local china_test=false
    if curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" &>/dev/null; then
        if ! curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" &>/dev/null; then
            china_test=true
        fi
    fi
    if [[ "$china_test" == false ]]; then
        local country
        country=$(curl -s --connect-timeout 5 --max-time 8 "https://ipapi.co/country_code/" 2>/dev/null || true)
        [[ "$country" == "CN" ]] && china_test=true
    fi
    if [[ "$china_test" == true ]]; then
        IS_CHINA=true
        info "大陆网络呢~人家帮你找加速镜像♡"
        find_github_proxy
    else
        IS_CHINA=false
        info "能直连 GitHub~运气不错嘛杂鱼♡"
    fi
}

find_github_proxy() {
    info "测试代理中~杂鱼等一下♡"
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "找到能用的代理了~感谢人家吧♡"
            return 0
        fi
    done
    warn "代理全挂了~硬连吧杂鱼♡"
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

# ==================== 依赖安装 ====================

update_pkg_cache() {
    case "$PKG_MANAGER" in
        pkg)    spin "刷新软件包索引~杂鱼等着♡" pkg update -y ;;
        apt)    spin "刷新软件包索引~杂鱼等着♡" $NEED_SUDO apt-get update -qq ;;
        yum)    spin "刷新软件包索引~杂鱼等着♡" $NEED_SUDO yum makecache -q ;;
        dnf)    spin "刷新软件包索引~杂鱼等着♡" $NEED_SUDO dnf makecache -q ;;
        pacman) spin "刷新软件包索引~杂鱼等着♡" $NEED_SUDO pacman -Sy --noconfirm ;;
        apk)    spin "刷新软件包索引~杂鱼等着♡" $NEED_SUDO apk update ;;
        brew)   spin "刷新软件包索引~杂鱼等着♡" brew update ;;
    esac
}

install_git() {
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') 已经有了~♡"
        return 0
    fi
    case "$PKG_MANAGER" in
        pkg)    spin "帮杂鱼装 Git 中~♡" pkg install -y git ;;
        apt)    spin "帮杂鱼装 Git 中~♡" $NEED_SUDO apt-get install -y -qq git ;;
        yum)    spin "帮杂鱼装 Git 中~♡" $NEED_SUDO yum install -y -q git ;;
        dnf)    spin "帮杂鱼装 Git 中~♡" $NEED_SUDO dnf install -y -q git ;;
        pacman) spin "帮杂鱼装 Git 中~♡" $NEED_SUDO pacman -S --noconfirm git ;;
        apk)    spin "帮杂鱼装 Git 中~♡" $NEED_SUDO apk add git ;;
        brew)   spin "帮杂鱼装 Git 中~♡" brew install git ;;
        *)      error "人家装不了~杂鱼自己想办法装 git 吧♡"; return 1 ;;
    esac
    command_exists git && info "Git 装好了~不用谢♡" || { error "Git 装不上欸~杂鱼的环境有问题吧♡"; return 1; }
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ -n "$ver" && "$ver" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) 已经有了~♡"
        return 0
    fi
    command_exists node && warn "Node.js $(node -v) 太老了啦~至少要 v${MIN_NODE_VERSION}+ 哦杂鱼♡"
    step "帮杂鱼装 Node.js~"
    if [[ "$IS_TERMUX" == true ]]; then
        install_nodejs_termux
    elif [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi
    hash -r 2>/dev/null || true
    if check_node_version; then
        info "Node.js $(node -v) 装好了~厉害吧♡"
    else
        error "Node.js 装不上~杂鱼的机器是不是太烂了♡"; return 1
    fi
    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null
        info "npm 镜像设好了~人家真贴心♡"
    fi
}

install_nodejs_termux() {
    spin "Termux 装 Node.js 中~♡" pkg install -y nodejs 2>/dev/null || \
    spin "换个方式试试~♡" pkg install -y nodejs-lts
}

install_nodejs_standard() {
    case "$PKG_MANAGER" in
        apt)
            spin "准备 NodeSource 仓库~♡" $NEED_SUDO apt-get install -y -qq ca-certificates curl gnupg
            $NEED_SUDO mkdir -p /etc/apt/keyrings
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                | $NEED_SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
                | $NEED_SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
            spin "刷新仓库~♡" $NEED_SUDO apt-get update -qq
            spin "安装 Node.js 中~杂鱼耐心等♡" $NEED_SUDO apt-get install -y -qq nodejs
            ;;
        yum|dnf)
            spin_cmd "配置 NodeSource~♡" "curl -fsSL https://rpm.nodesource.com/setup_20.x | $NEED_SUDO bash -"
            spin "安装 Node.js 中~杂鱼耐心等♡" $NEED_SUDO $PKG_MANAGER install -y nodejs
            ;;
        pacman) spin "安装 Node.js 中~♡" $NEED_SUDO pacman -S --noconfirm nodejs npm ;;
        apk)    spin "安装 Node.js 中~♡" $NEED_SUDO apk add nodejs npm ;;
        brew)   spin "安装 Node.js 中~♡" brew install node@20 ;;
        *)      install_nodejs_binary ;;
    esac
}

install_nodejs_china() {
    install_nodejs_binary "https://npmmirror.com/mirrors/node"
}

install_nodejs_binary() {
    local mirror="${1:-https://nodejs.org/dist}"
    local node_ver="v20.18.0"
    local arch=""
    case "$(uname -m)" in
        x86_64|amd64)  arch="x64"    ;;
        aarch64|arm64) arch="arm64"  ;;
        armv7l)        arch="armv7l" ;;
        *) error "这个 CPU 架构 $(uname -m) 人家不认识~♡"; return 1 ;;
    esac
    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    spin "下载 Node.js ${node_ver} 中~杂鱼等一下♡" curl -fSL -o "${tmp_dir}/${filename}" "${mirror}/${node_ver}/${filename}"
    if [[ $? -eq 0 ]]; then
        spin_cmd "解压安装中~♡" "cd '${tmp_dir}' && tar xf '${filename}' && ${NEED_SUDO:+$NEED_SUDO }cp -rf 'node-${node_ver}-linux-${arch}'/{bin,include,lib,share} /usr/local/ 2>/dev/null || ${NEED_SUDO:+$NEED_SUDO }cp -rf 'node-${node_ver}-linux-${arch}'/{bin,include,lib} /usr/local/"
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
    else
        rm -rf "$tmp_dir"
        error "Node.js 下载失败了~网络太烂了吧杂鱼♡"; return 1
    fi
}

install_dependencies() {
    step "帮杂鱼装系统依赖~真是没办法呢♡"
    [[ "$IS_TERMUX" != true ]] && get_sudo
    update_pkg_cache
    if [[ "$IS_TERMUX" == true ]]; then
        spin "装基础工具中~♡" pkg install -y curl git
    else
        case "$PKG_MANAGER" in
            apt)    spin "装基础工具中~♡" $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils ;;
            yum)    spin "装基础工具中~♡" $NEED_SUDO yum install -y -q curl wget tar xz ;;
            dnf)    spin "装基础工具中~♡" $NEED_SUDO dnf install -y -q curl wget tar xz ;;
            pacman) spin "装基础工具中~♡" $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz ;;
            apk)    spin "装基础工具中~♡" $NEED_SUDO apk add curl wget tar xz ;;
            brew)   : ;;
        esac
    fi
    install_git
    install_nodejs
}

# ==================== PM2 管理 ====================

install_pm2() {
    if command_exists pm2; then
        info "PM2 $(pm2 -v 2>/dev/null) 已经有了~♡"
        return 0
    fi
    spin "帮杂鱼装 PM2 中~♡" npm install -g pm2
    if command_exists pm2; then
        info "PM2 装好了~♡"
        return 0
    else
        warn "全局安装失败了~用 npx 凑合吧杂鱼♡"
        return 1
    fi
}

is_pm2_managed() {
    command_exists pm2 || return 1
    pm2 describe "$SERVICE_NAME" &>/dev/null 2>&1
}

is_pm2_online() {
    is_pm2_managed || return 1
    pm2 list 2>/dev/null | grep -q "${SERVICE_NAME}.*online"
}

is_running() {
    if is_pm2_online; then return 0; fi
    if command_exists pgrep; then
        pgrep -f "node.*server\.js" &>/dev/null && return 0
    else
        ps aux 2>/dev/null | grep -v grep | grep -q "node.*server\.js" && return 0
    fi
    return 1
}

pm2_start() {
    install_pm2 || { error "PM2 不能用~杂鱼想想办法♡"; return 1; }
    cd "$INSTALL_DIR"
    if is_pm2_managed; then
        pm2 restart "$SERVICE_NAME" &>/dev/null
    else
        pm2 start server.js --name "$SERVICE_NAME" &>/dev/null
    fi
    pm2 save &>/dev/null
    cd - >/dev/null
    sleep 2
    if is_pm2_online; then
        success "SillyTavern 跑起来了哦~不夸夸人家吗♡"
        show_access_info
        return 0
    else
        error "启动失败了~用 'pm2 logs $SERVICE_NAME' 看看怎么回事吧杂鱼♡"
        return 1
    fi
}

pm2_stop() {
    if is_pm2_online; then
        pm2 stop "$SERVICE_NAME" &>/dev/null
        pm2 save &>/dev/null
        info "SillyTavern 停下来了~♡"
    elif command_exists pgrep; then
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            info "进程杀掉了~♡"
        else
            info "本来就没在跑啊~杂鱼瞎操心♡"
        fi
    else
        info "本来就没在跑啊~杂鱼瞎操心♡"
    fi
}

pm2_remove() {
    if is_pm2_managed; then
        pm2 delete "$SERVICE_NAME" &>/dev/null
        pm2 save &>/dev/null
    fi
}

pm2_setup_autostart() {
    install_pm2 || return 1
    if [[ "$IS_TERMUX" == true ]]; then
        mkdir -p "$HOME/.termux/boot"
        cat > "$HOME/.termux/boot/sillytavern.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
pm2 resurrect
BOOTEOF
        chmod +x "$HOME/.termux/boot/sillytavern.sh"
        pm2 save &>/dev/null
        success "Termux 开机自启搞好了~♡"
        warn "记得装 Termux:Boot 哦笨蛋♡"
    else
        echo ""
        info "生成自启动配置中..."
        local startup_cmd
        startup_cmd=$(pm2 startup 2>&1 | grep -E "sudo|env" | head -1 || true)
        if [[ -n "$startup_cmd" ]]; then
            info "杂鱼~手动执行下面这条命令♡"
            echo ""
            echo -e "    ${CYAN}${startup_cmd}${NC}"
            echo ""
            info "然后再跑: ${CYAN}pm2 save${NC}"
        else
            get_sudo
            pm2 startup &>/dev/null || true
            pm2 save &>/dev/null
            info "自启动应该配好了~♡"
        fi
    fi
}

pm2_remove_autostart() {
    if [[ "$IS_TERMUX" == true ]]; then
        rm -f "$HOME/.termux/boot/sillytavern.sh"
        info "Termux 自启动删掉了~♡"
    else
        pm2 unstartup &>/dev/null || true
        info "PM2 自启动删掉了~♡"
    fi
}

migrate_from_systemd() {
    [[ "$IS_TERMUX" == true ]] && return
    command_exists systemctl || return
    if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        warn "检测到旧版 systemd 服务~该升级了杂鱼♡"
        info "新版改用 PM2 了哦~更好用♡"
        if confirm "把旧的 systemd 服务删掉好不好~♡"; then
            get_sudo
            spin_cmd "清理旧服务中~♡" "$NEED_SUDO systemctl stop $SERVICE_NAME 2>/dev/null; $NEED_SUDO systemctl disable $SERVICE_NAME 2>/dev/null; $NEED_SUDO rm -f /etc/systemd/system/${SERVICE_NAME}.service; $NEED_SUDO systemctl daemon-reload 2>/dev/null"
            success "旧服务清理掉了~♡"
        fi
    fi
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"
    if [[ "$IS_TERMUX" == true ]]; then
        info "Termux 不用管防火墙啦~♡"
        return
    fi
    get_sudo || return
    step "看看防火墙~"
    local firewall_found=false
    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW: 端口 $port 早就开了~♡"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW: 端口 $port 放行了~♡"
            fi
        fi
    fi
    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 $port 早就开了~♡"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld: 端口 $port 放行了~♡"
            fi
        fi
    fi
    if [[ "$firewall_found" == false ]] && command_exists iptables; then
        local has_drop
        has_drop=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || true)
        if [[ "$has_drop" -gt 0 ]]; then
            firewall_found=true
            if ! $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
                if command_exists iptables-save; then
                    if [[ -d /etc/iptables ]]; then
                        $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
                    elif command_exists netfilter-persistent; then
                        $NEED_SUDO netfilter-persistent save 2>/dev/null || true
                    fi
                fi
                success "iptables: 端口 $port 放行了~♡"
            else
                info "iptables: 端口 $port 早就开了~♡"
            fi
        fi
    fi
    [[ "$firewall_found" == false ]] && info "没检测到防火墙~♡"
    echo ""
    warn "云服务器的杂鱼记得去安全组也放行端口 ${port} 哦~别忘了♡"
}

remove_firewall_port() {
    local port="$1"
    [[ "$IS_TERMUX" == true ]] && return
    get_sudo || return
    if command_exists ufw; then
        $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
    fi
    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            $NEED_SUDO firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null || true
            $NEED_SUDO firewall-cmd --reload 2>/dev/null || true
        fi
    fi
}

# ==================== HTTPS / Caddy 管理 ====================

is_caddy_installed() {
    command_exists caddy
}

is_caddy_running() {
    [[ "$IS_TERMUX" == true ]] && return 1
    if command_exists systemctl; then
        systemctl is-active caddy &>/dev/null 2>&1 && return 0
    fi
    if command_exists pgrep; then
        pgrep -x caddy &>/dev/null && return 0
    else
        ps aux 2>/dev/null | grep -v grep | grep -q '[c]addy' && return 0
    fi
    return 1
}

check_port_available() {
    local port="$1"
    if command_exists ss; then
        ss -tlnp 2>/dev/null | grep -q ":${port} " && return 1
    elif command_exists netstat; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 1
    elif command_exists lsof; then
        lsof -i ":${port}" &>/dev/null && return 1
    fi
    return 0
}

install_caddy() {
    if is_caddy_installed; then
        local caddy_ver
        caddy_ver=$(caddy version 2>/dev/null | awk '{print $1}' | head -1)
        info "Caddy ${caddy_ver:-已安装} 已经有了~♡"
        return 0
    fi
    step "帮杂鱼装 Caddy~♡"
    get_sudo || return 1
    local installed=false
    case "$PKG_MANAGER" in
        apt)
            spin_cmd "配置 Caddy 仓库~♡" "
                $NEED_SUDO apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl 2>/dev/null || true
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | $NEED_SUDO gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | $NEED_SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
                $NEED_SUDO apt-get update -qq 2>/dev/null
            "
            if spin "安装 Caddy 中~♡" $NEED_SUDO apt-get install -y -qq caddy; then
                installed=true
            fi
            ;;
        dnf)
            spin_cmd "配置 Caddy 仓库~♡" "
                $NEED_SUDO dnf install -y 'dnf-command(copr)' 2>/dev/null || true
                $NEED_SUDO dnf copr enable @caddy/caddy -y 2>/dev/null || true
            "
            if spin "安装 Caddy 中~♡" $NEED_SUDO dnf install -y caddy; then
                installed=true
            fi
            ;;
        yum)
            spin_cmd "配置 Caddy 仓库~♡" "
                $NEED_SUDO yum install -y yum-plugin-copr 2>/dev/null || true
                $NEED_SUDO yum copr enable @caddy/caddy -y 2>/dev/null || true
            "
            if spin "安装 Caddy 中~♡" $NEED_SUDO yum install -y caddy; then
                installed=true
            fi
            ;;
        pacman)
            if spin "安装 Caddy 中~♡" $NEED_SUDO pacman -S --noconfirm caddy; then
                installed=true
            fi
            ;;
        apk)
            if spin "安装 Caddy 中~♡" $NEED_SUDO apk add caddy; then
                installed=true
            fi
            ;;
        brew)
            if spin "安装 Caddy 中~♡" brew install caddy; then
                installed=true
            fi
            ;;
    esac
    if [[ "$installed" == false ]]; then
        warn "包管理器安装失败~试试下载二进制♡"
        install_caddy_binary && installed=true
    fi
    if is_caddy_installed; then
        local caddy_ver
        caddy_ver=$(caddy version 2>/dev/null | awk '{print $1}' | head -1)
        success "Caddy ${caddy_ver} 装好了~♡"
        return 0
    else
        error "Caddy 装不上~杂鱼检查网络吧♡"
        return 1
    fi
}

install_caddy_binary() {
    local arch os
    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l)        arch="armv7"  ;;
        *) error "不支持的架构 $(uname -m)~♡"; return 1 ;;
    esac
    case "$(uname -s)" in
        Linux)  os="linux"  ;;
        Darwin) os="darwin" ;;
        *) error "不支持的系统~♡"; return 1 ;;
    esac
    local caddy_ver="$CADDY_VERSION_FALLBACK"
    local filename="caddy_${caddy_ver}_${os}_${arch}.tar.gz"
    local url="https://github.com/caddyserver/caddy/releases/download/v${caddy_ver}/${filename}"
    local download_url
    download_url=$(get_github_url "$url")
    local tmp_dir
    tmp_dir=$(mktemp -d)
    if ! spin "下载 Caddy v${caddy_ver} 中~♡" curl -fSL -o "${tmp_dir}/${filename}" "$download_url"; then
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            if ! spin "直连下载 Caddy~♡" curl -fSL -o "${tmp_dir}/${filename}" "$url"; then
                rm -rf "$tmp_dir"
                return 1
            fi
        else
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    cd "$tmp_dir"
    tar xzf "$filename" 2>/dev/null
    if [[ -f "caddy" ]]; then
        $NEED_SUDO mv caddy /usr/local/bin/caddy
        $NEED_SUDO chmod +x /usr/local/bin/caddy
    else
        cd - >/dev/null
        rm -rf "$tmp_dir"
        error "解压后找不到 caddy 文件~♡"
        return 1
    fi
    cd - >/dev/null
    rm -rf "$tmp_dir"
    $NEED_SUDO mkdir -p /etc/caddy
    if [[ "$os" == "linux" ]] && command_exists systemctl; then
        $NEED_SUDO groupadd --system caddy 2>/dev/null || true
        $NEED_SUDO useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy 2>/dev/null || true
        $NEED_SUDO tee /etc/systemd/system/caddy.service > /dev/null << 'SVCEOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SVCEOF
        $NEED_SUDO systemctl daemon-reload 2>/dev/null
    fi
    return 0
}

generate_caddyfile() {
    local domain="$1"
    local st_port="$2"
    get_sudo || return 1
    $NEED_SUDO mkdir -p /etc/caddy
    if [[ -f "$CADDY_CADDYFILE" ]]; then
        $NEED_SUDO cp "$CADDY_CADDYFILE" "$CADDY_CADDYFILE_BACKUP" 2>/dev/null || true
    fi
    if [[ -n "$domain" ]]; then
        $NEED_SUDO tee "$CADDY_CADDYFILE" > /dev/null << EOF
# Managed by Ksilly - SillyTavern HTTPS Reverse Proxy
# Mode: Auto ACME (Let's Encrypt / ZeroSSL)
# Domain: ${domain}

${domain} {
    reverse_proxy localhost:${st_port}
}
EOF
    else
        $NEED_SUDO tee "$CADDY_CADDYFILE" > /dev/null << EOF
# Managed by Ksilly - SillyTavern HTTPS Reverse Proxy
# Mode: Self-signed certificate (tls internal)

:443 {
    tls internal
    reverse_proxy localhost:${st_port}
}
EOF
    fi
    if id caddy &>/dev/null; then
        $NEED_SUDO chown caddy:caddy "$CADDY_CADDYFILE" 2>/dev/null || true
    fi
    info "Caddyfile 生成好了~♡"
}

update_caddyfile_port() {
    local new_port="$1"
    if [[ "$HTTPS_ENABLED" == true ]] && [[ -f "$CADDY_CADDYFILE" ]]; then
        get_sudo || return
        $NEED_SUDO sed -i "s|reverse_proxy localhost:[0-9]*|reverse_proxy localhost:${new_port}|g" "$CADDY_CADDYFILE"
        info "Caddyfile 端口已同步为 ${new_port}~♡"
        if is_caddy_running; then
            reload_caddy_service
        fi
    fi
}

start_caddy_service() {
    get_sudo || return 1
    if command_exists systemctl && [[ -f /etc/systemd/system/caddy.service ]] || \
       command_exists systemctl && systemctl list-unit-files caddy.service &>/dev/null 2>&1; then
        $NEED_SUDO systemctl enable caddy &>/dev/null 2>&1 || true
        $NEED_SUDO systemctl start caddy &>/dev/null 2>&1
    elif [[ "$OS_TYPE" == "macos" ]] && command_exists brew; then
        brew services start caddy &>/dev/null 2>&1 || \
            $NEED_SUDO caddy start --config "$CADDY_CADDYFILE" &>/dev/null 2>&1
    else
        $NEED_SUDO caddy start --config "$CADDY_CADDYFILE" &>/dev/null 2>&1
    fi
    sleep 2
    if is_caddy_running; then
        success "Caddy 启动了~♡"
        return 0
    else
        error "Caddy 启动失败~♡"
        return 1
    fi
}

stop_caddy_service() {
    get_sudo || return 1
    if command_exists systemctl && systemctl is-active caddy &>/dev/null 2>&1; then
        $NEED_SUDO systemctl stop caddy &>/dev/null 2>&1
    elif [[ "$OS_TYPE" == "macos" ]] && command_exists brew; then
        brew services stop caddy &>/dev/null 2>&1
    else
        $NEED_SUDO caddy stop &>/dev/null 2>&1 || true
        if command_exists pkill; then
            $NEED_SUDO pkill -x caddy 2>/dev/null || true
        fi
    fi
    info "Caddy 停了~♡"
}

restart_caddy_service() {
    get_sudo || return 1
    if command_exists systemctl && systemctl list-unit-files caddy.service &>/dev/null 2>&1; then
        $NEED_SUDO systemctl restart caddy &>/dev/null 2>&1
    else
        stop_caddy_service
        sleep 1
        start_caddy_service
        return $?
    fi
    sleep 2
    if is_caddy_running; then
        success "Caddy 重启好了~♡"
        return 0
    else
        error "Caddy 重启失败~♡"
        return 1
    fi
}

reload_caddy_service() {
    get_sudo || return 1
    if is_caddy_running; then
        if $NEED_SUDO caddy reload --config "$CADDY_CADDYFILE" --force &>/dev/null 2>&1; then
            info "Caddy 配置已重载~♡"
            return 0
        else
            warn "重载失败~尝试重启♡"
            restart_caddy_service
        fi
    else
        start_caddy_service
    fi
}

setup_https() {
    if [[ "$IS_TERMUX" == true ]]; then
        return 0
    fi
    local listen_val
    listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
    if [[ "$listen_val" != "true" ]]; then
        return 0
    fi
    echo ""
    divider
    echo -e "  ${BOLD}${PINK}🔒 HTTPS 安全访问配置~♡${NC}"
    divider
    echo ""
    echo -e "  ${DIM}用 HTTP 明文访问不安全~密码和聊天内容都能被截获♡${NC}"
    echo -e "  ${DIM}人家用 Caddy 帮杂鱼配个 HTTPS~超简单的♡${NC}"
    echo -e "  ${DIM}有域名和没域名都能用~不用担心♡${NC}"
    echo ""
    if [[ "$HTTPS_ENABLED" == true ]]; then
        info "HTTPS 已经配好了~♡"
        if [[ -n "$HTTPS_DOMAIN" ]]; then
            echo -e "    当前模式: ${GREEN}域名证书${NC} (${CYAN}${HTTPS_DOMAIN}${NC})"
        else
            echo -e "    当前模式: ${YELLOW}自签名证书${NC}"
        fi
        echo ""
        if ! confirm "要重新配置 HTTPS 吗~♡"; then
            return 0
        fi
    else
        if ! confirm "要配置 HTTPS 安全访问吗~♡"; then
            info "不配就不配~裸奔的杂鱼♡"
            return 0
        fi
    fi
    get_sudo || return 1
    if ! is_caddy_running; then
        if ! check_port_available 443; then
            warn "端口 443 已被其他程序占用~♡"
            echo -e "    ${DIM}用 ${CYAN}ss -tlnp | grep :443${NC}${DIM} 看看是什么占了♡${NC}"
            if ! confirm "继续配置吗~可能会冲突哦杂鱼♡"; then
                return 1
            fi
        fi
    fi
    install_caddy || { error "Caddy 装不上~HTTPS 配不了♡"; return 1; }
    local st_port
    st_port=$(get_port)
    echo ""
    echo -e "  ${BOLD}选择证书模式~♡${NC}"
    echo ""
    echo -e "    ${GREEN}1)${NC} 我有域名 ${DIM}(自动申请 Let's Encrypt 免费证书~推荐♡)${NC}"
    echo -e "       ${DIM}需要域名已经解析到这台服务器${NC}"
    echo ""
    echo -e "    ${GREEN}2)${NC} 没有域名 ${DIM}(自签名证书~用 IP 直接访问♡)${NC}"
    echo -e "       ${DIM}浏览器会有安全警告~但数据传输是加密的${NC}"
    echo ""
    local cert_mode=""
    while [[ "$cert_mode" != "1" && "$cert_mode" != "2" ]]; do
        cert_mode=$(read_input "选哪个~杂鱼" "2")
    done
    if [[ "$cert_mode" == "1" ]]; then
        echo ""
        local domain=""
        while [[ -z "$domain" ]]; do
            domain=$(read_input "输入域名~(如 st.example.com)")
            if [[ -z "$domain" ]]; then
                warn "不能空着~笨蛋♡"
                continue
            fi
            if ! echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*\.)+[a-zA-Z]{2,}$'; then
                warn "这不太像个域名~杂鱼确定吗♡"
                if ! confirm "继续使用 ${domain} ~♡"; then
                    domain=""
                    continue
                fi
            fi
        done
        local pub_ip
        echo ""
        spin "获取公网 IP 中~♡" bash -c "true"
        pub_ip=$(get_public_ip)
        echo ""
        if [[ -n "$pub_ip" ]]; then
            warn "请确保域名 ${CYAN}${domain}${NC} 的 DNS 已解析到 ${CYAN}${pub_ip}${NC}"
        else
            warn "请确保域名 ${CYAN}${domain}${NC} 已解析到这台服务器的公网 IP"
        fi
        echo -e "  ${DIM}如果 DNS 没配好~Let's Encrypt 证书申请会失败哦♡${NC}"
        echo ""
        if ! confirm "DNS 已经配好了~♡"; then
            warn "那杂鱼先去配 DNS 吧~配好了再来运行 HTTPS 管理♡"
            return 0
        fi
        generate_caddyfile "$domain" "$st_port"
        HTTPS_DOMAIN="$domain"
        open_firewall_port "80"
    else
        echo ""
        echo -e "  ${YELLOW}⚠ 自签名证书说明~杂鱼听好了♡${NC}"
        echo ""
        echo -e "    ${DIM}• 数据传输是加密的~比 HTTP 安全♡${NC}"
        echo -e "    ${DIM}• 证书由 Caddy 本地 CA 签发，不被浏览器信任${NC}"
        echo -e "    ${DIM}• 浏览器会显示安全警告~这是正常的${NC}"
        echo ""
        echo -e "    ${BOLD}如何跳过警告:${NC}"
        echo -e "    ${DIM}Chrome  → 点「高级」→「继续前往(不安全)」${NC}"
        echo -e "    ${DIM}Firefox → 点「高级」→「接受风险并继续」${NC}"
        echo -e "    ${DIM}Edge    → 点「详细信息」→「继续转到网页」${NC}"
        echo ""
        generate_caddyfile "" "$st_port"
        HTTPS_DOMAIN=""
    fi
    open_firewall_port "443"
    echo ""
    if is_caddy_running; then
        step "重载 Caddy 配置~♡"
        reload_caddy_service
    else
        step "启动 Caddy~♡"
        start_caddy_service
    fi
    sleep 2
    if is_caddy_running; then
        HTTPS_ENABLED=true
        save_config
        echo ""
        success "HTTPS 配置完成~杂鱼可以安全访问了♡"
        echo ""
        if [[ -n "$HTTPS_DOMAIN" ]]; then
            echo -e "    ${GREEN}🔒${NC} HTTPS 访问 → ${CYAN}https://${HTTPS_DOMAIN}${NC}"
            echo ""
            echo -e "    ${DIM}首次访问可能需要几秒钟申请证书~耐心等一下♡${NC}"
        else
            local pub_ip
            pub_ip=$(get_public_ip)
            if [[ -n "$pub_ip" ]]; then
                echo -e "    ${GREEN}🔒${NC} HTTPS 访问 → ${CYAN}https://${pub_ip}${NC}"
            fi
            local local_ip
            local_ip=$(get_local_ip)
            [[ "$local_ip" != "无法获取" ]] && \
                echo -e "    ${GREEN}🔒${NC} 局域网HTTPS → ${CYAN}https://${local_ip}${NC}"
            echo ""
            echo -e "    ${YELLOW}浏览器安全警告是正常的~点击「继续」就好♡${NC}"
        fi
    else
        error "Caddy 没跑起来~证书配置可能有问题♡"
        echo ""
        echo -e "    调试命令: ${CYAN}${NEED_SUDO:+$NEED_SUDO }caddy run --config ${CADDY_CADDYFILE}${NC}"
        echo -e "    查看日志: ${CYAN}${NEED_SUDO:+$NEED_SUDO }journalctl -u caddy --no-pager -n 20${NC}"
        return 1
    fi
}

remove_https() {
    if [[ "$HTTPS_ENABLED" != true ]]; then
        info "HTTPS 本来就没配~杂鱼瞎操心♡"
        return 0
    fi
    echo ""
    warn "要移除 HTTPS 配置~♡"
    if [[ -n "$HTTPS_DOMAIN" ]]; then
        echo -e "    当前域名: ${CYAN}${HTTPS_DOMAIN}${NC}"
    else
        echo -e "    当前模式: 自签名证书"
    fi
    echo ""
    if ! confirm "确定移除 HTTPS 吗~♡"; then
        info "那就留着吧~♡"
        return 0
    fi
    get_sudo || return 1
    if is_caddy_running; then
        stop_caddy_service
    fi
    if command_exists systemctl && systemctl list-unit-files caddy.service &>/dev/null 2>&1; then
        $NEED_SUDO systemctl disable caddy &>/dev/null 2>&1 || true
    fi
    if [[ -f "$CADDY_CADDYFILE_BACKUP" ]]; then
        $NEED_SUDO mv "$CADDY_CADDYFILE_BACKUP" "$CADDY_CADDYFILE" 2>/dev/null || true
        info "Caddyfile 已恢复为原始配置~♡"
    else
        $NEED_SUDO rm -f "$CADDY_CADDYFILE" 2>/dev/null || true
    fi
    remove_firewall_port "443"
    remove_firewall_port "80"
    HTTPS_ENABLED=false
    HTTPS_DOMAIN=""
    save_config
    success "HTTPS 配置已移除~杂鱼又变成裸奔了♡"
}

caddy_menu() {
    if ! check_installed; then
        error "SillyTavern 都还没装呢~♡"
        return 1
    fi
    if [[ "$IS_TERMUX" == true ]]; then
        error "Termux 不支持 Caddy HTTPS 配置~端口 443 需要 root♡"
        return 1
    fi
    while true; do
        print_banner
        echo -e "  ${BOLD}${PINK}🔒 HTTPS 证书管理~♡${NC}"
        divider
        echo ""
        echo -e "  ${BOLD}当前状态${NC}"
        echo ""
        if [[ "$HTTPS_ENABLED" == true ]]; then
            echo -e "    HTTPS        ${GREEN}● 已配置${NC}"
            if [[ -n "$HTTPS_DOMAIN" ]]; then
                echo -e "    证书模式     ${GREEN}域名证书 (ACME)${NC}"
                echo -e "    域名         ${CYAN}${HTTPS_DOMAIN}${NC}"
            else
                echo -e "    证书模式     ${YELLOW}自签名证书${NC}"
            fi
        else
            echo -e "    HTTPS        ${DIM}未配置${NC}"
        fi
        if is_caddy_installed; then
            local caddy_ver
            caddy_ver=$(caddy version 2>/dev/null | awk '{print $1}' | head -1)
            echo -e "    Caddy        ${GREEN}已安装${NC} ${DIM}(${caddy_ver})${NC}"
        else
            echo -e "    Caddy        ${DIM}未安装${NC}"
        fi
        if is_caddy_running; then
            echo -e "    Caddy 状态   ${GREEN}● 运行中${NC}"
        else
            echo -e "    Caddy 状态   ${RED}● 已停止${NC}"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 配置 / 重新配置 HTTPS"
        echo -e "  ${GREEN}2)${NC} 启动 Caddy"
        echo -e "  ${GREEN}3)${NC} 停止 Caddy"
        echo -e "  ${GREEN}4)${NC} 重启 Caddy"
        echo -e "  ${GREEN}5)${NC} 查看 Caddy 日志"
        echo -e "  ${GREEN}6)${NC} 查看 Caddyfile 配置"
        echo -e "  ${GREEN}7)${NC} 移除 HTTPS 配置"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单~♡"
        echo ""
        divider
        local choice
        choice=$(read_input "杂鱼想干嘛~")
        case "$choice" in
            1) setup_https ;;
            2)
                if ! is_caddy_installed; then
                    error "Caddy 还没装呢~先去配置 HTTPS♡"
                elif ! [[ -f "$CADDY_CADDYFILE" ]]; then
                    error "Caddyfile 不存在~先去配置 HTTPS♡"
                else
                    start_caddy_service
                fi
                ;;
            3)
                if is_caddy_running; then
                    stop_caddy_service
                else
                    info "Caddy 本来就没跑~♡"
                fi
                ;;
            4)
                if is_caddy_installed && [[ -f "$CADDY_CADDYFILE" ]]; then
                    restart_caddy_service
                else
                    error "Caddy 没安装或没配置~先去配置 HTTPS♡"
                fi
                ;;
            5)
                echo ""
                if command_exists journalctl; then
                    echo -e "  ${BOLD}最近的 Caddy 日志~♡${NC}"
                    divider
                    echo ""
                    $NEED_SUDO journalctl -u caddy --no-pager -n 30 2>/dev/null || \
                        warn "获取不到日志~可能 Caddy 不是用 systemd 运行的♡"
                else
                    warn "没有 journalctl~试试 ${CYAN}caddy run --config ${CADDY_CADDYFILE}${NC} 看输出♡"
                fi
                ;;
            6)
                echo ""
                if [[ -f "$CADDY_CADDYFILE" ]]; then
                    echo -e "  ${BOLD}Caddyfile 内容~♡${NC}"
                    divider
                    echo ""
                    $NEED_SUDO cat "$CADDY_CADDYFILE" 2>/dev/null | while IFS= read -r line; do
                        echo -e "    ${DIM}${line}${NC}"
                    done
                else
                    warn "Caddyfile 不存在~先去配置 HTTPS♡"
                fi
                ;;
            7) remove_https ;;
            0) return 0 ;;
            *) warn "没这个选项~杂鱼♡" ;;
        esac
        pause_key
    done
}
# ==================== 插件管理 ====================

get_plugin_dir() {
    echo "$INSTALL_DIR/$PLUGIN_DIR_NAME"
}

is_plugin_installed() {
    local folder="$1"
    local plugin_path="$(get_plugin_dir)/$folder"
    [[ -d "$plugin_path" && "$(ls -A "$plugin_path" 2>/dev/null)" ]]
}

get_plugin_version() {
    local folder="$1"
    local plugin_path="$(get_plugin_dir)/$folder"
    if [[ -f "$plugin_path/manifest.json" ]]; then
        local ver
        ver=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$plugin_path/manifest.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        [[ -n "$ver" ]] && echo "$ver" && return
    fi
    if [[ -f "$plugin_path/package.json" ]]; then
        local ver
        ver=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$plugin_path/package.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        [[ -n "$ver" ]] && echo "$ver" && return
    fi
    if [[ -d "$plugin_path/.git" ]]; then
        local hash
        hash=$(cd "$plugin_path" && git rev-parse --short HEAD 2>/dev/null)
        [[ -n "$hash" ]] && echo "git:$hash" && return
    fi
    echo "已安装"
}

install_single_plugin() {
    local name="$1" folder="$2" repo_intl="$3" repo_cn="$4"
    local plugin_base
    plugin_base=$(get_plugin_dir)
    mkdir -p "$plugin_base"
    local target_path="$plugin_base/$folder"
    if is_plugin_installed "$folder"; then
        warn "${name} 已经装过了哦~♡"
        echo -e "    当前版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
        echo ""
        if confirm "要删掉重装吗~杂鱼♡"; then
            spin "删除旧版 ${name} 中~♡" rm -rf "$target_path"
        else
            info "那就不动了~♡"
            return 0
        fi
    fi
    local repo_url
    if [[ "$IS_CHINA" == true ]]; then
        repo_url="$repo_cn"
        info "大陆网络~用镜像源安装♡"
    else
        repo_url="$repo_intl"
        info "国际网络~直连安装♡"
    fi
    echo -e "    仓库: ${DIM}${repo_url}${NC}"
    if spin "克隆 ${name} 中~杂鱼等等♡" git clone --depth 1 "$repo_url" "$target_path"; then
        success "${name} 安装好了~♡"
        echo -e "    版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
        echo -e "    路径: ${DIM}${target_path}${NC}"
        return 0
    fi
    warn "第一个源失败了~换一个试试♡"
    local fallback_url
    if [[ "$IS_CHINA" == true ]]; then
        fallback_url=$(get_github_url "$repo_intl")
    else
        fallback_url="$repo_cn"
    fi
    echo -e "    备用: ${DIM}${fallback_url}${NC}"
    if spin "用备用源克隆 ${name} 中~♡" git clone --depth 1 "$fallback_url" "$target_path"; then
        success "${name} 安装好了~(用的备用源) ♡"
        echo -e "    版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
        return 0
    fi
    error "${name} 装不上~两个源都挂了杂鱼检查网络吧♡"
    return 1
}

uninstall_single_plugin() {
    local name="$1" folder="$2"
    if ! is_plugin_installed "$folder"; then
        info "${name} 本来就没装~杂鱼瞎操心♡"
        return 0
    fi
    local target_path="$(get_plugin_dir)/$folder"
    echo -e "    版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
    echo -e "    路径: ${DIM}${target_path}${NC}"
    echo ""
    if confirm "确定删掉 ${name} 吗~♡"; then
        spin "删除 ${name} 中~♡" rm -rf "$target_path"
        success "${name} 删掉了~♡"
    else
        info "那就留着吧~♡"
    fi
}

update_single_plugin() {
    local name="$1" folder="$2" repo_intl="$3" repo_cn="$4"
    if ! is_plugin_installed "$folder"; then
        warn "${name} 还没装呢~要不要先装一个♡"
        if confirm "现在安装~♡"; then
            install_single_plugin "$name" "$folder" "$repo_intl" "$repo_cn"
        fi
        return
    fi
    local target_path="$(get_plugin_dir)/$folder"
    if [[ ! -d "$target_path/.git" ]]; then
        warn "${name} 不是用 git 装的~没法更新♡"
        if confirm "要删了重装吗~杂鱼♡"; then
            spin "删除旧版中~♡" rm -rf "$target_path"
            install_single_plugin "$name" "$folder" "$repo_intl" "$repo_cn"
        fi
        return
    fi
    echo -e "    当前版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
    local repo_url
    if [[ "$IS_CHINA" == true ]]; then
        repo_url="$repo_cn"
    else
        repo_url="$repo_intl"
    fi
    cd "$target_path"
    git remote set-url origin "$repo_url" 2>/dev/null
    if spin "拉取 ${name} 更新中~♡" git pull --ff-only; then
        success "${name} 更新好了~♡"
        echo -e "    新版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
    else
        warn "快速合并失败~强制更新♡"
        local branch
        branch=$(git branch --show-current 2>/dev/null || echo "main")
        if spin_cmd "强制更新 ${name}~♡" "cd '$target_path' && git fetch --all 2>/dev/null && git reset --hard 'origin/$branch' 2>/dev/null"; then
            success "${name} 强制更新好了~♡"
            echo -e "    新版本: ${CYAN}$(get_plugin_version "$folder")${NC}"
        else
            error "${name} 更新失败了~杂鱼的网络有问题♡"
        fi
    fi
    cd - >/dev/null
}

plugin_menu() {
    if ! check_installed; then
        error "SillyTavern 都还没装呢~装什么插件杂鱼♡"
        return 1
    fi
    if [[ -z "$GITHUB_PROXY" && "$IS_CHINA" == false ]]; then
        if [[ -f "$KSILLY_CONF" ]]; then
            source "$KSILLY_CONF" 2>/dev/null || true
            IS_CHINA="${KSILLY_IS_CHINA:-false}"
            GITHUB_PROXY="${KSILLY_GITHUB_PROXY:-}"
        fi
    fi
    while true; do
        print_banner
        echo -e "  ${BOLD}${PINK}插件管理~给杂鱼的酒馆加点料♡${NC}"
        divider
        echo ""
        echo -e "  ${BOLD}已收录插件${NC}"
        echo ""
        if is_plugin_installed "$PLUGIN_1_FOLDER"; then
            local p1_ver
            p1_ver=$(get_plugin_version "$PLUGIN_1_FOLDER")
            echo -e "    ${GREEN}●${NC} ${PLUGIN_1_NAME}"
            echo -e "      ${DIM}版本: ${p1_ver}${NC}"
        else
            echo -e "    ${DIM}○${NC} ${PLUGIN_1_NAME}"
            echo -e "      ${DIM}未安装${NC}"
        fi
        echo ""
        if is_plugin_installed "$PLUGIN_2_FOLDER"; then
            local p2_ver
            p2_ver=$(get_plugin_version "$PLUGIN_2_FOLDER")
            echo -e "    ${GREEN}●${NC} ${PLUGIN_2_NAME}"
            echo -e "      ${DIM}版本: ${p2_ver}${NC}"
        else
            echo -e "    ${DIM}○${NC} ${PLUGIN_2_NAME}"
            echo -e "      ${DIM}未安装${NC}"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装插件${NC}"
        echo -e "    ${GREEN}1)${NC} 安装 ${PLUGIN_1_NAME}"
        echo -e "    ${GREEN}2)${NC} 安装 ${PLUGIN_2_NAME}"
        echo -e "    ${GREEN}3)${NC} 全部安装"
        echo ""
        echo -e "  ${BOLD}更新插件${NC}"
        echo -e "    ${GREEN}4)${NC} 更新 ${PLUGIN_1_NAME}"
        echo -e "    ${GREEN}5)${NC} 更新 ${PLUGIN_2_NAME}"
        echo -e "    ${GREEN}6)${NC} 全部更新"
        echo ""
        echo -e "  ${BOLD}卸载插件${NC}"
        echo -e "    ${GREEN}7)${NC} 卸载 ${PLUGIN_1_NAME}"
        echo -e "    ${GREEN}8)${NC} 卸载 ${PLUGIN_2_NAME}"
        echo -e "    ${GREEN}9)${NC} 全部卸载"
        echo ""
        echo -e "    ${RED}0)${NC} 返回主菜单~♡"
        echo ""
        divider
        local choice
        choice=$(read_input "杂鱼想装什么~")
        local need_restart=false
        case "$choice" in
            1)
                echo ""
                step "安装 ${PLUGIN_1_NAME}~♡"
                install_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN" && need_restart=true
                ;;
            2)
                echo ""
                step "安装 ${PLUGIN_2_NAME}~♡"
                install_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN" && need_restart=true
                ;;
            3)
                echo ""
                step "全部安装~一步到位♡"
                echo ""
                echo -e "  ${PINK}[1/2]${NC} ${PLUGIN_1_NAME}"
                install_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN" && need_restart=true
                echo ""
                echo -e "  ${PINK}[2/2]${NC} ${PLUGIN_2_NAME}"
                install_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN" && need_restart=true
                echo ""
                success "全部装好了~杂鱼可以去酒馆里看看了♡"
                ;;
            4)
                echo ""
                step "更新 ${PLUGIN_1_NAME}~♡"
                update_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN" && need_restart=true
                ;;
            5)
                echo ""
                step "更新 ${PLUGIN_2_NAME}~♡"
                update_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN" && need_restart=true
                ;;
            6)
                echo ""
                step "全部更新~♡"
                echo ""
                echo -e "  ${PINK}[1/2]${NC} ${PLUGIN_1_NAME}"
                update_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN" && need_restart=true
                echo ""
                echo -e "  ${PINK}[2/2]${NC} ${PLUGIN_2_NAME}"
                update_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN" && need_restart=true
                echo ""
                success "全部更新好了~♡"
                ;;
            7)
                echo ""
                step "卸载 ${PLUGIN_1_NAME}~♡"
                uninstall_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" && need_restart=true
                ;;
            8)
                echo ""
                step "卸载 ${PLUGIN_2_NAME}~♡"
                uninstall_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" && need_restart=true
                ;;
            9)
                echo ""
                step "全部卸载~♡"
                if confirm "真的要把插件全删了吗~杂鱼♡"; then
                    echo ""
                    uninstall_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" && need_restart=true
                    echo ""
                    uninstall_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" && need_restart=true
                    echo ""
                    success "全删干净了~♡"
                fi
                ;;
            0) return 0 ;;
            *) warn "没这个选项~杂鱼眼花了吗♡" ;;
        esac
        if [[ "$need_restart" == true ]] && is_running; then
            echo ""
            warn "插件变动后重启一下 SillyTavern 才能生效哦~♡"
            if confirm "现在重启~♡"; then
                restart_sillytavern
            fi
        fi
        pause_key
    done
}

# ==================== SillyTavern 核心操作 ====================

clone_sillytavern() {
    step "克隆 SillyTavern~人家帮你拉代码♡"
    INSTALL_DIR=$(read_input "装到哪里~" "$DEFAULT_INSTALL_DIR")
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "这里已经装过了哦~杂鱼♡"
            if confirm "删掉重装好不好~♡"; then
                spin "清理旧安装中~♡" rm -rf "$INSTALL_DIR"
            else
                info "那就留着吧~♡"
                return 0
            fi
        else
            error "这个目录已经有东西了但不是 SillyTavern~换一个吧杂鱼♡"
            return 1
        fi
    fi
    echo ""
    ask "选个分支吧杂鱼~♡"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}稳定版 (推荐笨蛋用这个)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}开发版 (爱折腾的杂鱼选这个)${NC}"
    echo ""
    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "选哪个~" "1")
    done
    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"
    info "分支: $branch ~♡"
    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")
    if ! spin "克隆仓库中~杂鱼耐心等♡" git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR"; then
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理不行~试试直连♡"
            if ! spin "直连克隆中~♡" git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR"; then
                error "克隆失败了~杂鱼检查一下网络吧♡"; return 1
            fi
        else
            error "克隆失败了~杂鱼检查一下网络吧♡"; return 1
        fi
    fi
    success "仓库拉好了~♡"
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    step "装 npm 依赖~杂鱼别急♡"
    cd "$INSTALL_DIR"
    if spin "npm install 中~这个比较慢哦杂鱼♡" npm install --no-audit --no-fund; then
        success "依赖装好了~♡"
    else
        error "npm 依赖装不上~杂鱼的环境有问题吧♡"; cd - >/dev/null; return 1
    fi
    cd - >/dev/null
    save_config
}

configure_sillytavern() {
    step "配置 SillyTavern~人家手把手教杂鱼♡"
    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"
    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed -i 's/\r$//' "$config_file"
            info "配置文件生成好了~♡"
        else
            error "连 default.yaml 都没有~仓库是不是坏了杂鱼♡"; return 1
        fi
    fi
    echo ""
    divider
    echo -e "  ${BOLD}${PINK}配置向导 ~跟着人家选就行了杂鱼♡${NC}"
    divider

    # --- 监听设置 ---
    echo ""
    echo -e "  ${BOLD}1. 监听模式${NC}"
    echo -e "     ${DIM}开了的话局域网和外网设备都能访问哦~${NC}"
    echo -e "     ${DIM}不开就只有本机能用~${NC}"
    echo ""
    local listen_enabled=false
    if confirm "开启监听~让其他设备也能用♡"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        success "监听开了~♡"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "只能本机访问~♡"
    fi

    # --- 端口 ---
    echo ""
    echo -e "  ${BOLD}2. 端口设置${NC}"
    local port
    port=$(read_input "端口号~不懂就用默认的吧杂鱼" "8000")
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        set_yaml_val "port" "$port" "$config_file"
        info "端口: $port ~♡"
    else
        warn "这什么乱七八糟的端口~用默认 8000 了笨蛋♡"
        port="8000"
    fi

    # --- 白名单 ---
    echo ""
    echo -e "  ${BOLD}3. 白名单模式${NC}"
    echo -e "     ${DIM}开了的话只有白名单里的 IP 才能访问~${NC}"
    echo -e "     ${DIM}要远程访问的话建议关掉~${NC}"
    echo ""
    if confirm "关掉白名单~♡"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        success "白名单关了~谁都能来了♡"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "白名单开着~安全第一♡"
    fi

    # --- 基础认证 ---
    echo ""
    echo -e "  ${BOLD}4. 基础认证 (HTTP Auth)${NC}"
    echo -e "     ${DIM}访问的时候要输用户名密码~${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "     ${RED}都开了远程访问了~不设密码的话杂鱼是想被人偷窥吗♡${NC}"
    fi
    echo ""
    if confirm "开启基础认证~♡"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"
        echo ""
        local auth_user=""
        while [[ -z "$auth_user" ]]; do
            auth_user=$(read_input "用户名~起个好记的♡")
            [[ -z "$auth_user" ]] && warn "不能空着啦~笨蛋♡"
        done
        local auth_pass
        auth_pass=$(read_password "密码~设个复杂点的♡")
        if grep -q "basicAuthUser:" "$config_file" 2>/dev/null; then
            sed -i "/basicAuthUser:/,/^[^ #]/{
                s|\(\s*\)username:.*|\1username: \"${auth_user}\"|
                s|\(\s*\)password:.*|\1password: \"${auth_pass}\"|
            }" "$config_file"
        else
            cat >> "$config_file" << EOF
basicAuthUser:
  username: "${auth_user}"
  password: "${auth_pass}"
EOF
        fi
        success "认证开好了~(用户: $auth_user) ♡"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "不设认证啊~胆子挺大的杂鱼♡"
    fi

    # --- 防火墙 ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置保存好了~♡"
}

setup_background() {
    echo ""
    divider
    echo -e "  ${BOLD}后台运行设置~♡${NC}"
    divider
    [[ "$IS_TERMUX" != true ]] && get_sudo 2>/dev/null
    migrate_from_systemd
    echo ""
    echo -e "  ${BOLD}● PM2 后台运行${NC}"
    echo -e "    ${DIM}用 PM2 管理进程~关掉终端也不会停♡${NC}"
    echo -e "    ${DIM}崩了还能自动重启~比杂鱼靠谱多了♡${NC}"
    echo ""
    if confirm "用 PM2 后台运行~♡"; then
        install_pm2 || return 1
        success "PM2 准备好了~♡"
        echo ""
        if confirm "顺便设个开机自启~♡"; then
            pm2_setup_autostart
        fi
    fi
}

# ==================== 启动/停止 ====================

start_sillytavern() {
    if ! check_installed; then
        error "都还没装呢~急什么杂鱼♡"
        return 1
    fi
    if is_running; then
        warn "已经在跑了啦~杂鱼眼瞎了吗♡"
        show_access_info
        return 0
    fi
    echo ""
    echo -e "  ${GREEN}1)${NC} 后台运行 ${DIM}(PM2~推荐♡)${NC}"
    echo -e "  ${GREEN}2)${NC} 前台运行 ${DIM}(Ctrl+C 停止)${NC}"
    echo ""
    local mode
    mode=$(read_input "选一个~" "1")
    case "$mode" in
        1)
            step "PM2 后台启动中~♡"
            pm2_start
            ;;
        2)
            local port
            port=$(get_port)
            step "前台启动~♡"
            info "按 Ctrl+C 就能停哦~♡"
            show_access_info
            echo ""
            cd "$INSTALL_DIR"
            node server.js
            cd - >/dev/null
            ;;
        *) warn "选的什么鬼~杂鱼♡" ;;
    esac
}

stop_sillytavern() {
    if ! is_running; then
        info "本来就没在跑~瞎操心的杂鱼♡"
        return 0
    fi
    step "停止 SillyTavern~♡"
    pm2_stop
}

restart_sillytavern() {
    if ! check_installed; then
        error "都还没装呢~杂鱼♡"
        return 1
    fi
    step "重启 SillyTavern~♡"
    pm2_stop
    sleep 1
    pm2_start
}

# ==================== 状态显示 ====================

show_status() {
    if ! check_installed; then
        error "都还没装呢~看什么状态杂鱼♡"
        return 1
    fi
    print_banner
    local version="" branch="" config_file="$INSTALL_DIR/config.yaml"
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)
    local status_text status_color
    if is_running; then
        status_text="运行中~好好的♡"
        status_color="$GREEN"
    else
        status_text="停着呢"
        status_color="$RED"
    fi
    echo -e "  ${BOLD}基本信息~给杂鱼看看♡${NC}"
    divider
    echo -e "    版本       ${CYAN}${version:-不知道}${NC}"
    echo -e "    分支       ${CYAN}${branch:-不知道}${NC}"
    echo -e "    目录       ${DIM}${INSTALL_DIR}${NC}"
    echo -e "    状态       ${status_color}● ${status_text}${NC}"
    if is_pm2_managed; then
        echo -e "    进程管理   ${GREEN}PM2${NC}"
    else
        echo -e "    进程管理   ${DIM}没配置♡${NC}"
    fi

    # HTTPS 状态
    if [[ "$HTTPS_ENABLED" == true ]]; then
        if [[ -n "$HTTPS_DOMAIN" ]]; then
            echo -e "    HTTPS      ${GREEN}● 域名证书${NC} ${DIM}(${HTTPS_DOMAIN})${NC}"
        else
            echo -e "    HTTPS      ${YELLOW}● 自签名证书${NC}"
        fi
        if is_caddy_running; then
            echo -e "    Caddy      ${GREEN}● 运行中${NC}"
        else
            echo -e "    Caddy      ${RED}● 已停止${NC}"
        fi
    else
        echo -e "    HTTPS      ${DIM}未配置${NC}"
    fi

    echo ""

    # 插件信息
    echo -e "  ${BOLD}已安装插件~♡${NC}"
    divider
    local plugin_count=0
    if is_plugin_installed "$PLUGIN_1_FOLDER"; then
        echo -e "    ${GREEN}●${NC} ${PLUGIN_1_NAME} ${DIM}($(get_plugin_version "$PLUGIN_1_FOLDER"))${NC}"
        ((plugin_count++))
    fi
    if is_plugin_installed "$PLUGIN_2_FOLDER"; then
        echo -e "    ${GREEN}●${NC} ${PLUGIN_2_NAME} ${DIM}($(get_plugin_version "$PLUGIN_2_FOLDER"))${NC}"
        ((plugin_count++))
    fi
    if [[ "$plugin_count" -eq 0 ]]; then
        echo -e "    ${DIM}没装任何插件~杂鱼可以去插件管理里装♡${NC}"
    fi
    echo ""
    if [[ -f "$config_file" ]]; then
        local listen_val whitelist_val auth_val port_val user_acc discreet
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        port_val=$(get_port)
        user_acc=$(get_yaml_val "enableUserAccounts" "$config_file")
        discreet=$(get_yaml_val "enableDiscreetLogin" "$config_file")
        echo -e "  ${BOLD}当前配置~♡${NC}"
        divider
        echo -e "    监听模式       $(format_bool "$listen_val")"
        echo -e "    端口           ${CYAN}${port_val}${NC}"
        echo -e "    白名单模式     $(format_bool "$whitelist_val")"
        echo -e "    基础认证       $(format_bool "$auth_val")"
        echo -e "    用户账户系统   $(format_bool "${user_acc:-false}")"
        echo -e "    隐蔽登录       $(format_bool "${discreet:-false}")"
        show_access_info
    fi
}

# ==================== 更新管理 ====================

check_for_updates() {
    UPDATE_BEHIND=0
    cd "$INSTALL_DIR" || return 1
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi
    if ! git fetch origin --quiet 2>/dev/null; then
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
            git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null
        return 1
    fi
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "@{u}" 2>/dev/null || echo "")
    if [[ -z "$remote_commit" || "$local_commit" == "$remote_commit" ]]; then
        cd - >/dev/null
        return 1
    fi
    UPDATE_BEHIND=$(git rev-list HEAD.."@{u}" --count 2>/dev/null || echo "0")
    cd - >/dev/null
    return 0
}

do_update() {
    if is_running; then
        warn "SillyTavern 还在跑~先停一下♡"
        pm2_stop
    fi
    cd "$INSTALL_DIR"
    info "备份配置中~人家真贴心吧♡"
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "备份在: $backup_dir ~♡"
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi
    if ! spin "拉取最新代码中~杂鱼等等♡" git pull --ff-only; then
        warn "快速合并不行~人家强制更新了♡"
        local current_branch
        current_branch=$(git branch --show-current)
        spin_cmd "强制更新中~♡" "git fetch --all 2>/dev/null && git reset --hard 'origin/$current_branch' 2>/dev/null"
    fi
    success "代码更新好了~♡"
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    spin "更新 npm 依赖中~♡" npm install --no-audit --no-fund
    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        info "配置恢复好了~♡"
    fi
    cd - >/dev/null
    save_script 2>/dev/null && info "管理脚本也更新了~♡"
    success "SillyTavern 更新完成~感谢人家吧杂鱼♡"
    echo ""
    if confirm "现在就启动~♡"; then
        pm2_start
    fi
}

handle_update() {
    if ! check_installed; then
        error "都还没装呢~更新什么杂鱼♡"
        return
    fi
    detect_network
    step "帮杂鱼检查更新~♡"
    local current_ver=""
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        current_ver=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
    local branch=""
    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)
    echo ""
    echo -e "    当前版本: ${CYAN}${current_ver:-不知道}${NC}"
    echo -e "    当前分支: ${CYAN}${branch:-不知道}${NC}"
    echo ""
    if spin "连接远程仓库中~♡" bash -c "cd '$INSTALL_DIR' && git fetch origin --quiet 2>/dev/null" && check_for_updates; then
        echo ""
        warn "有 ${UPDATE_BEHIND} 个新提交可以更新哦~杂鱼♡"
        echo ""
        if confirm "要更新吗~♡"; then
            do_update
        else
            info "不更新就算了~♡"
        fi
    else
        echo ""
        success "已经是最新的了~杂鱼白担心了♡"
    fi
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "都还没装呢~卸什么卸杂鱼♡"
        return 1
    fi
    echo ""
    warn "要卸载 SillyTavern 了哦~杂鱼真的舍得吗♡"
    echo -e "    安装目录: ${DIM}${INSTALL_DIR}${NC}"
    local has_plugins=false
    if is_plugin_installed "$PLUGIN_1_FOLDER" || is_plugin_installed "$PLUGIN_2_FOLDER"; then
        has_plugins=true
        echo ""
        echo -e "    ${YELLOW}已安装的插件也会一起删掉哦~♡${NC}"
        is_plugin_installed "$PLUGIN_1_FOLDER" && echo -e "      • ${PLUGIN_1_NAME}"
        is_plugin_installed "$PLUGIN_2_FOLDER" && echo -e "      • ${PLUGIN_2_NAME}"
    fi
    echo ""
    confirm "真的要删掉吗~后悔可没药吃哦杂鱼♡" || { info "算了算了~♡"; return 0; }
    echo ""
    confirm "再确认一次~真的删光所有数据♡" || { info "就知道你不敢~杂鱼♡"; return 0; }
    step "开始卸载~♡"
    pm2_stop
    pm2_remove
    local port
    port=$(get_port)
    remove_firewall_port "$port"

    # 清理 HTTPS/Caddy
    if [[ "$HTTPS_ENABLED" == true ]]; then
        echo ""
        info "清理 HTTPS 配置~♡"
        if is_caddy_running; then
            stop_caddy_service
        fi
        if command_exists systemctl && systemctl list-unit-files caddy.service &>/dev/null 2>&1; then
            get_sudo
            $NEED_SUDO systemctl disable caddy &>/dev/null 2>&1 || true
        fi
        if [[ -f "$CADDY_CADDYFILE_BACKUP" ]]; then
            get_sudo
            $NEED_SUDO mv "$CADDY_CADDYFILE_BACKUP" "$CADDY_CADDYFILE" 2>/dev/null || true
        elif [[ -f "$CADDY_CADDYFILE" ]]; then
            get_sudo
            $NEED_SUDO rm -f "$CADDY_CADDYFILE" 2>/dev/null || true
        fi
        remove_firewall_port "443"
        remove_firewall_port "80"
        HTTPS_ENABLED=false
        HTTPS_DOMAIN=""
        info "HTTPS 配置清理完了~♡"
    fi

    if [[ "$IS_TERMUX" != true ]] && command_exists systemctl; then
        if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            get_sudo
            spin_cmd "清理 systemd 服务~♡" "$NEED_SUDO systemctl stop $SERVICE_NAME 2>/dev/null; $NEED_SUDO systemctl disable $SERVICE_NAME 2>/dev/null; $NEED_SUDO rm -f /etc/systemd/system/${SERVICE_NAME}.service; $NEED_SUDO systemctl daemon-reload 2>/dev/null"
        fi
    fi
    rm -f "$HOME/.termux/boot/sillytavern.sh" 2>/dev/null
    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm "备份一下聊天记录和角色卡吧~杂鱼♡"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            spin "备份数据中~♡" bash -c "cp -r '$INSTALL_DIR/data' '$backup_path/' && [[ -f '$INSTALL_DIR/config.yaml' ]] && cp '$INSTALL_DIR/config.yaml' '$backup_path/'"
            success "数据备份在: $backup_path ~♡"
        fi
    fi
    spin "删除安装目录中~♡" rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "SillyTavern 卸载完了~再见了♡"
    echo ""
    if confirm "顺便把 Node.js 也删了~♡"; then
        if [[ "$IS_TERMUX" == true ]]; then
            spin "卸载 Node.js 中~♡" pkg uninstall -y nodejs
        else
            get_sudo
            case "$PKG_MANAGER" in
                apt)    spin_cmd "卸载 Node.js 中~♡" "$NEED_SUDO apt-get remove -y nodejs 2>/dev/null; $NEED_SUDO rm -f /etc/apt/sources.list.d/nodesource.list" ;;
                yum)    spin "卸载 Node.js 中~♡" $NEED_SUDO yum remove -y nodejs ;;
                dnf)    spin "卸载 Node.js 中~♡" $NEED_SUDO dnf remove -y nodejs ;;
                pacman) spin "卸载 Node.js 中~♡" $NEED_SUDO pacman -R --noconfirm nodejs npm ;;
            esac
        fi
        info "Node.js 删掉了~♡"
    fi
}

# ==================== 配置修改菜单 ====================

modify_config_menu() {
    if ! check_installed; then
        error "都还没装呢~改什么配置杂鱼♡"
        return 1
    fi
    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件不见了~杂鱼是不是手欠删了♡"
        return 1
    fi
    while true; do
        print_banner
        local listen_val whitelist_val auth_val port_val user_acc discreet
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        port_val=$(get_port)
        user_acc=$(get_yaml_val "enableUserAccounts" "$config_file")
        discreet=$(get_yaml_val "enableDiscreetLogin" "$config_file")
        echo -e "  ${BOLD}当前配置~♡${NC}"
        divider
        echo -e "    监听模式       $(format_bool "$listen_val")"
        echo -e "    端口           ${CYAN}${port_val}${NC}"
        echo -e "    白名单模式     $(format_bool "$whitelist_val")"
        echo -e "    基础认证       $(format_bool "$auth_val")"
        echo -e "    多账户系统     $(format_bool "${user_acc:-false}")"
        echo -e "    隐蔽登录       $(format_bool "${discreet:-false}")"
        if [[ "$HTTPS_ENABLED" == true ]]; then
            if [[ -n "$HTTPS_DOMAIN" ]]; then
                echo -e "    HTTPS          ${GREEN}域名证书${NC} ${DIM}(${HTTPS_DOMAIN})${NC}"
            else
                echo -e "    HTTPS          ${YELLOW}自签名证书${NC}"
            fi
        else
            echo -e "    HTTPS          ${DIM}未配置${NC}"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN} 1)${NC} 修改监听设置"
        echo -e "  ${GREEN} 2)${NC} 修改端口"
        echo -e "  ${GREEN} 3)${NC} 修改白名单模式"
        echo -e "  ${GREEN} 4)${NC} 修改基础认证"
        echo -e "  ${GREEN} 5)${NC} 修改多账户系统"
        echo -e "  ${GREEN} 6)${NC} 修改隐蔽登录"
        echo -e "  ${GREEN} 7)${NC} 编辑完整配置文件"
        echo -e "  ${GREEN} 8)${NC} 重置为默认配置"
        echo -e "  ${GREEN} 9)${NC} 防火墙放行管理"
        echo -e "  ${GREEN}10)${NC} HTTPS 证书管理"
        echo ""
        echo -e "  ${RED} 0)${NC} 返回主菜单~♡"
        echo ""
        divider
        local choice
        choice=$(read_input "杂鱼想改什么~")
        case "$choice" in
            1)
                echo ""
                echo -e "  当前: 监听 $(format_bool "$listen_val")"
                if confirm "开启监听~♡"; then
                    set_yaml_val "listen" "true" "$config_file"
                    success "监听开了~♡"
                    open_firewall_port "$(get_port)"
                else
                    set_yaml_val "listen" "false" "$config_file"
                    info "监听关了~♡"
                fi
                ;;
            2)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                local new_port
                new_port=$(read_input "新端口号~" "$port_val")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    success "端口改成 $new_port 了~♡"
                    # 同步更新 Caddyfile
                    update_caddyfile_port "$new_port"
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    [[ "$cur_listen" == "true" ]] && open_firewall_port "$new_port"
                else
                    error "这什么端口~$new_port ~杂鱼乱填♡"
                fi
                ;;
            3)
                echo ""
                echo -e "  当前: 白名单 $(format_bool "$whitelist_val")"
                if confirm "关掉白名单~♡"; then
                    set_yaml_val "whitelistMode" "false" "$config_file"
                    success "白名单关了~♡"
                else
                    set_yaml_val "whitelistMode" "true" "$config_file"
                    info "白名单开着~♡"
                fi
                ;;
            4)
                echo ""
                echo -e "  当前: 基础认证 $(format_bool "$auth_val")"
                if confirm "开启基础认证~♡"; then
                    set_yaml_val "basicAuthMode" "true" "$config_file"
                    echo ""
                    local auth_user=""
                    while [[ -z "$auth_user" ]]; do
                        auth_user=$(read_input "用户名~")
                        [[ -z "$auth_user" ]] && warn "不能空着~笨蛋♡"
                    done
                    local auth_pass
                    auth_pass=$(read_password "密码~")
                    if grep -q "basicAuthUser:" "$config_file" 2>/dev/null; then
                        sed -i "/basicAuthUser:/,/^[^ #]/{
                            s|\(\s*\)username:.*|\1username: \"${auth_user}\"|
                            s|\(\s*\)password:.*|\1password: \"${auth_pass}\"|
                        }" "$config_file"
                    else
                        cat >> "$config_file" << EOF
basicAuthUser:
  username: "${auth_user}"
  password: "${auth_pass}"
EOF
                    fi
                    success "认证开了~(用户: $auth_user) ♡"
                else
                    set_yaml_val "basicAuthMode" "false" "$config_file"
                    info "认证关了~小心被偷窥哦杂鱼♡"
                fi
                ;;
            5)
                echo ""
                echo -e "  当前: 多账户系统 $(format_bool "${user_acc:-false}")"
                echo -e "  ${DIM}开了可以建多个用户~各自独立数据♡${NC}"
                echo ""
                if confirm "开启多账户系统~♡"; then
                    set_yaml_val "enableUserAccounts" "true" "$config_file"
                    success "多账户系统开了~♡"
                else
                    set_yaml_val "enableUserAccounts" "false" "$config_file"
                    info "多账户系统关了~♡"
                fi
                ;;
            6)
                echo ""
                echo -e "  当前: 隐蔽登录 $(format_bool "${discreet:-false}")"
                echo -e "  ${DIM}开了的话登录页不显示头像和用户名~♡${NC}"
                echo ""
                if confirm "开启隐蔽登录~♡"; then
                    set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                    success "隐蔽登录开了~偷偷摸摸的杂鱼♡"
                else
                    set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                    info "隐蔽登录关了~♡"
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            8)
                if confirm "要重置成默认配置吗~杂鱼改坏了♡"; then
                    if [[ -f "$INSTALL_DIR/default.yaml" ]]; then
                        cp "$INSTALL_DIR/default.yaml" "$config_file"
                        sed -i 's/\r$//' "$config_file"
                        success "重置好了~从头再来吧杂鱼♡"
                    else
                        error "default.yaml 不见了~没法重置♡"
                    fi
                fi
                ;;
            9) open_firewall_port "$(get_port)" ;;
            10) caddy_menu ;;
            0) return 0 ;;
            *) warn "没这个选项~杂鱼眼花了吗♡" ;;
        esac
        if [[ "$choice" =~ ^[1-6]$ ]] && is_running; then
            echo ""
            warn "改了配置要重启才生效哦~杂鱼♡"
            if confirm "现在重启~♡"; then
                restart_sillytavern
            fi
        fi
        pause_key
    done
}

# ==================== PM2 管理菜单 ====================

pm2_menu() {
    if ! check_installed; then
        error "都还没装呢~杂鱼♡"
        return 1
    fi
    while true; do
        print_banner
        echo -e "  ${BOLD}PM2 后台运行状态~♡${NC}"
        divider
        if command_exists pm2; then
            echo -e "    PM2        ${GREEN}已安装${NC} ($(pm2 -v 2>/dev/null))"
        else
            echo -e "    PM2        ${DIM}没装呢♡${NC}"
        fi
        if is_pm2_managed; then
            if is_pm2_online; then
                echo -e "    进程状态   ${GREEN}● 跑着呢~♡${NC}"
            else
                echo -e "    进程状态   ${RED}● 停了${NC}"
            fi
        else
            echo -e "    进程状态   ${DIM}没托管♡${NC}"
        fi
        if [[ "$IS_TERMUX" == true ]]; then
            if [[ -f "$HOME/.termux/boot/sillytavern.sh" ]]; then
                echo -e "    开机自启   ${GREEN}● 配好了~♡${NC}"
            else
                echo -e "    开机自启   ${DIM}没配置♡${NC}"
            fi
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 安装/更新 PM2"
        echo -e "  ${GREEN}2)${NC} 后台启动"
        echo -e "  ${GREEN}3)${NC} 停止"
        echo -e "  ${GREEN}4)${NC} 重启"
        echo -e "  ${GREEN}5)${NC} 查看日志"
        echo -e "  ${GREEN}6)${NC} 设置开机自启"
        echo -e "  ${GREEN}7)${NC} 移除开机自启"
        echo -e "  ${GREEN}8)${NC} 从 PM2 移除进程"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单~♡"
        echo ""
        divider
        local choice
        choice=$(read_input "杂鱼想干嘛~")
        case "$choice" in
            1) install_pm2 ;;
            2) pm2_start ;;
            3) pm2_stop ;;
            4) restart_sillytavern ;;
            5)
                if is_pm2_managed; then
                    echo ""
                    echo -e "  ${GREEN}1)${NC} 看最近的日志"
                    echo -e "  ${GREEN}2)${NC} 实时跟踪 ${DIM}(Ctrl+C 退出)${NC}"
                    echo -e "  ${GREEN}3)${NC} 清空日志"
                    echo ""
                    local log_choice
                    log_choice=$(read_input "选~" "1")
                    case "$log_choice" in
                        1) echo ""; pm2 logs "$SERVICE_NAME" --lines 50 --nostream 2>/dev/null ;;
                        2) pm2 logs "$SERVICE_NAME" 2>/dev/null ;;
                        3) pm2 flush "$SERVICE_NAME" &>/dev/null; success "日志清掉了~♡" ;;
                    esac
                else
                    warn "SillyTavern 还没在 PM2 里注册呢~杂鱼♡"
                fi
                ;;
            6) pm2_setup_autostart ;;
            7) pm2_remove_autostart ;;
            8)
                if confirm "从 PM2 移除 SillyTavern 进程~♡"; then
                    pm2_stop
                    pm2_remove
                    success "从 PM2 移除了~♡"
                fi
                ;;
            0) return 0 ;;
            *) warn "没这个选项~杂鱼♡" ;;
        esac
        pause_key
    done
}

# ==================== 完整安装流程 ====================

full_install() {
    print_banner
    echo -e "  ${BOLD}${PINK}嘛~人家就帮杂鱼装一次 SillyTavern 吧♡${NC}"
    divider
    detect_os
    detect_network
    install_dependencies
    echo ""
    clone_sillytavern
    configure_sillytavern

    # 安装后询问是否安装插件
    echo ""
    divider
    echo -e "  ${BOLD}${PINK}要不要顺便装几个好用的插件~♡${NC}"
    divider
    echo ""
    echo -e "    ${GREEN}●${NC} ${PLUGIN_1_NAME}"
    echo -e "      ${DIM}为酒馆提供更强大的脚本运行能力${NC}"
    echo ""
    echo -e "    ${GREEN}●${NC} ${PLUGIN_2_NAME}"
    echo -e "      ${DIM}提供提示词模板管理功能${NC}"
    echo ""
    if confirm "安装全部推荐插件~♡"; then
        echo ""
        echo -e "  ${PINK}[1/2]${NC} ${PLUGIN_1_NAME}"
        install_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN"
        echo ""
        echo -e "  ${PINK}[2/2]${NC} ${PLUGIN_2_NAME}"
        install_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN"
        echo ""
        success "插件全装好了~♡"
    elif confirm "那要一个一个选吗~♡"; then
        echo ""
        if confirm "安装 ${PLUGIN_1_NAME}~♡"; then
            install_single_plugin "$PLUGIN_1_NAME" "$PLUGIN_1_FOLDER" "$PLUGIN_1_REPO_INTL" "$PLUGIN_1_REPO_CN"
        fi
        echo ""
        if confirm "安装 ${PLUGIN_2_NAME}~♡"; then
            install_single_plugin "$PLUGIN_2_NAME" "$PLUGIN_2_FOLDER" "$PLUGIN_2_REPO_INTL" "$PLUGIN_2_REPO_CN"
        fi
    else
        info "不装就不装~以后想装再来找人家♡"
    fi

    setup_background

    # HTTPS 配置（仅在开启了监听且非 Termux 时提示）
    setup_https

    save_config

    step "保存管理脚本~♡"
    if spin "保存脚本中~♡" bash -c "true" && save_script; then
        success "脚本保存在: ${INSTALL_DIR}/ksilly.sh ~♡"
        info "以后直接跑: ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC} 就行了杂鱼♡"
    else
        warn "脚本保存失败了~不过问题不大♡"
    fi
    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${PINK}🎉 装~好~了~♡ 感谢人家吧杂鱼~${NC}"
    echo ""
    info "安装目录: $INSTALL_DIR"
    local p_count=0
    is_plugin_installed "$PLUGIN_1_FOLDER" && ((p_count++))
    is_plugin_installed "$PLUGIN_2_FOLDER" && ((p_count++))
    [[ "$p_count" -gt 0 ]] && info "已安装插件: ${p_count} 个"
    show_access_info
    echo ""
    divider
    echo ""
    if confirm "现在就启动吗~急性子的杂鱼♡"; then
        start_sillytavern
    else
        echo ""
        info "想启动的时候来找人家~♡"
        echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
        echo -e "    或 ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
    fi
}

# ==================== 主菜单 ====================

main_menu() {
    while true; do
        print_banner
        load_config
        if check_installed; then
            local version=""
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
            local status_icon="${RED}●${NC}"
            is_running && status_icon="${GREEN}●${NC}"
            echo -e "  ${status_icon} SillyTavern ${CYAN}v${version:-?}${NC} ${DIM}| ${INSTALL_DIR}${NC}"
            local p_count=0
            is_plugin_installed "$PLUGIN_1_FOLDER" && ((p_count++))
            is_plugin_installed "$PLUGIN_2_FOLDER" && ((p_count++))
            [[ "$p_count" -gt 0 ]] && echo -e "  ${DIM}  插件: ${p_count} 个已安装${NC}"
            if [[ "$HTTPS_ENABLED" == true ]]; then
                if is_caddy_running; then
                    echo -e "  ${DIM}  🔒 HTTPS: 已启用${NC}"
                else
                    echo -e "  ${DIM}  🔒 HTTPS: 已配置(Caddy已停止)${NC}"
                fi
            fi
            [[ ! -f "$INSTALL_DIR/ksilly.sh" ]] && save_script 2>/dev/null
        else
            echo -e "  ${YELLOW}●${NC} SillyTavern 还没装呢~杂鱼♡"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "    ${GREEN} 1)${NC} 安装"
        echo -e "    ${GREEN} 2)${NC} 更新"
        echo -e "    ${GREEN} 3)${NC} 卸载"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "    ${GREEN} 4)${NC} 启动"
        echo -e "    ${GREEN} 5)${NC} 停止"
        echo -e "    ${GREEN} 6)${NC} 重启"
        echo -e "    ${GREEN} 7)${NC} 查看状态"
        echo ""
        echo -e "  ${BOLD}配置与维护${NC}"
        echo -e "    ${GREEN} 8)${NC} 修改配置"
        echo -e "    ${GREEN} 9)${NC} 后台运行管理 (PM2)"
        echo -e "    ${GREEN}10)${NC} 插件管理"
        echo -e "    ${GREEN}11)${NC} HTTPS 证书管理 🔒"
        echo ""
        echo -e "     ${RED} 0)${NC} 退出~♡"
        echo ""
        divider
        local choice
        choice=$(read_input "杂鱼想干什么~选一个吧♡")
        case "$choice" in
            1)
                if check_installed; then
                    warn "已经装过了呀~杂鱼健忘♡"
                    confirm "要重新装吗~♡" || continue
                fi
                full_install
                pause_key
                ;;
            2)
                handle_update
                pause_key
                ;;
            3)
                detect_os
                [[ "$IS_TERMUX" != true ]] && get_sudo 2>/dev/null
                uninstall_sillytavern
                pause_key
                ;;
            4)
                start_sillytavern
                pause_key
                ;;
            5)
                stop_sillytavern
                pause_key
                ;;
            6)
                restart_sillytavern
                pause_key
                ;;
            7)
                show_status
                pause_key
                ;;
            8)
                modify_config_menu
                ;;
            9)
                pm2_menu
                ;;
            10)
                plugin_menu
                ;;
            11)
                detect_os
                caddy_menu
                ;;
            0)
                echo ""
                info "哼~走了就走了~才不会想你呢杂鱼♡ 👋"
                echo ""
                exit 0
                ;;
            *)
                warn "没这个选项~数字都看不懂吗杂鱼♡"
                sleep 0.5
                ;;
        esac
    done
}

# ==================== 入口 ====================

main() {
    local uname_s
    uname_s=$(uname -s 2>/dev/null || echo "Unknown")
    case "$uname_s" in
        Linux|Darwin) ;;
        *)
            if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
                error "这脚本只支持 Linux / macOS / Termux ~杂鱼用错系统了♡"
                exit 1
            fi
            ;;
    esac
    load_config
    case "${1:-}" in
        install)   detect_os; detect_network; full_install ;;
        update)    detect_os; detect_network; load_config; handle_update ;;
        start)     load_config; start_sillytavern ;;
        stop)      load_config; stop_sillytavern ;;
        restart)   load_config; restart_sillytavern ;;
        status)    load_config; show_status ;;
        uninstall) detect_os; load_config; uninstall_sillytavern ;;
        plugins)   load_config; plugin_menu ;;
        https)     detect_os; load_config; caddy_menu ;;
        "")        main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|uninstall|plugins|https}"
            echo "  不带参数进入菜单~杂鱼♡"
            exit 1
            ;;
    esac
}

main "$@"
