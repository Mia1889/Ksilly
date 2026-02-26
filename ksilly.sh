#!/bin/bash
#
#  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
#  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
#  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
#  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
#  ██║  ██╗███████║██║███████╗███████╗██║
#  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
#
#  Ksilly - 跨平台 SillyTavern 一键部署脚本
#  作者: Mia1889
#  仓库: https://github.com/Mia1889/Ksilly
#  版本: 2.0.0
#  支持: Linux / macOS / Termux / Windows(Git Bash) / WSL
#

# ==================== 全局常量 ====================
SCRIPT_VERSION="2.0.0"
KSILLY_CONF="$HOME/.ksilly.conf"
DEFAULT_INSTALL_DIR="$HOME/SillyTavern"
SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"
KSILLY_RAW="https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.sh"
KSILLY_BAT_RAW="https://raw.githubusercontent.com/Mia1889/Ksilly/main/ksilly.bat"
PM2_APP_NAME="sillytavern"
MIN_NODE_VERSION=18
CURL_OPTS="--connect-timeout 5 --max-time 15"
GITHUB_PROXIES=(
    "https://ghfast.top/"
    "https://gh-proxy.com/"
    "https://mirror.ghproxy.com/"
)

# ==================== 颜色定义 ====================
setup_colors() {
    if [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        PURPLE='\033[0;35m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' BOLD='' DIM='' NC=''
    fi
}
setup_colors

# ==================== 全局变量 ====================
IS_CHINA=false
GITHUB_PROXY=""
INSTALL_DIR=""
PLATFORM=""
PKG_MANAGER=""
CURRENT_USER=$(whoami)
NEED_SUDO=""

# ==================== 信号处理 ====================
cleanup() {
    echo ""
    echo -e "  ${YELLOW}!${NC} 操作已取消"
    exit 130
}
trap cleanup INT TERM

# ==================== 输出函数 ====================
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
    echo -e "  ${BOLD}跨平台 SillyTavern 部署脚本 v${SCRIPT_VERSION}${NC}  ${DIM}[${PLATFORM}]${NC}"
    echo -e "  ${DIM}github.com/Mia1889/Ksilly${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
step()    { echo -e "\n  ${CYAN}▶ $1${NC}"; }
success() { echo -e "  ${GREEN}★${NC} $1"; }
divider() { echo -e "  ${DIM}─────────────────────────────────────────────${NC}"; }

# ==================== 输入函数 ====================
confirm() {
    local prompt="$1" result=""
    while true; do
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result </dev/tty 2>/dev/null || read -r result
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
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}[${default}]${NC}: " >&2
    else
        echo -ne "  ${BLUE}?${NC} ${prompt}: " >&2
    fi
    read -r result </dev/tty 2>/dev/null || read -r result
    [[ -z "$result" && -n "$default" ]] && result="$default"
    echo "$result"
}

read_password() {
    local prompt="$1" result=""
    while [[ -z "$result" ]]; do
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}(输入时不会显示字符, 这是正常现象)${NC}: " >&2
        read -rs result </dev/tty 2>/dev/null || read -rs result
        echo "" >&2
        [[ -z "$result" ]] && warn "密码不能为空, 请重新输入"
    done
    echo "$result"
}

pause_key() {
    echo ""
    echo -ne "  ${DIM}按 Enter 继续...${NC}" >&2
    read -r </dev/tty 2>/dev/null || read -r
}

# ==================== 工具函数 ====================
command_exists() { command -v "$1" &>/dev/null; }

get_sudo() {
    if [[ "$PLATFORM" == "termux" || "$PLATFORM" == "windows" ]]; then
        NEED_SUDO=""
        return
    fi
    if [[ "$EUID" -eq 0 ]]; then
        NEED_SUDO=""
    elif command_exists sudo; then
        NEED_SUDO="sudo"
    else
        NEED_SUDO=""
    fi
}

sed_i() {
    if [[ "$PLATFORM" == "macos" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

run_with_timeout() {
    local secs="$1"; shift
    if command_exists timeout; then
        timeout "$secs" "$@"
    elif command_exists gtimeout; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}

format_bool() {
    local val="${1:-false}"
    if [[ "$val" == "true" ]]; then
        echo -e "${GREEN}开启${NC}"
    else
        echo -e "${RED}关闭${NC}"
    fi
}

escape_sed() {
    printf '%s' "$1" | sed 's/[&/\]/\\&/g; s/"/\\"/g'
}

# ==================== YAML 辅助 ====================
get_yaml_val() {
    local key="$1" file="$2"
    [[ -f "$file" ]] || return
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | \
        sed "s/^[[:space:]]*${key}:[[:space:]]*//" | \
        tr -d '\r\n' | sed 's/^["'\'']\(.*\)["'\''"]$/\1/' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
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
    local port
    port=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml" 2>/dev/null)
    [[ "$port" =~ ^[0-9]+$ ]] || port="8000"
    echo "$port"
}

# ==================== 平台检测 ====================
detect_platform() {
    local uname_s
    uname_s=$(uname -s 2>/dev/null || echo "Unknown")

    case "$uname_s" in
        Linux*)
            if [[ -d "/data/data/com.termux" ]] || [[ -n "${TERMUX_VERSION:-}" ]]; then
                PLATFORM="termux"
                PKG_MANAGER="pkg"
            elif grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
                detect_linux_pkg
            else
                PLATFORM="linux"
                detect_linux_pkg
            fi
            ;;
        Darwin*)
            PLATFORM="macos"
            PKG_MANAGER="brew"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            PKG_MANAGER="none"
            DEFAULT_INSTALL_DIR="${HOME}/SillyTavern"
            ;;
        *)
            PLATFORM="linux"
            detect_linux_pkg
            ;;
    esac
}

detect_linux_pkg() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|linuxmint|pop|kali|deepin|elementary)
                PKG_MANAGER="apt" ;;
            centos|rhel|rocky|almalinux|ol)
                PKG_MANAGER="yum"
                command_exists dnf && PKG_MANAGER="dnf" ;;
            fedora)
                PKG_MANAGER="dnf" ;;
            arch|manjaro|endeavouros)
                PKG_MANAGER="pacman" ;;
            alpine)
                PKG_MANAGER="apk" ;;
            opensuse*|sles)
                PKG_MANAGER="zypper" ;;
            *)
                PKG_MANAGER="unknown" ;;
        esac
    else
        PKG_MANAGER="unknown"
    fi
}

show_platform_info() {
    local plat_name=""
    case "$PLATFORM" in
        linux)   plat_name="Linux ($PKG_MANAGER)" ;;
        macos)   plat_name="macOS" ;;
        termux)  plat_name="Termux (Android)" ;;
        windows) plat_name="Windows (Git Bash)" ;;
        wsl)     plat_name="WSL ($PKG_MANAGER)" ;;
    esac
    info "运行平台: ${plat_name}"
}

# ==================== 网络检测 ====================
detect_network() {
    step "检测网络环境..."

    IS_CHINA=false
    GITHUB_PROXY=""

    local can_baidu=false can_google=false
    if curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" &>/dev/null; then
        can_baidu=true
    fi
    if curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" &>/dev/null; then
        can_google=true
    fi

    if [[ "$can_baidu" == true && "$can_google" == false ]]; then
        IS_CHINA=true
    fi

    if [[ "$IS_CHINA" == false && "$can_google" == false ]]; then
        local country=""
        country=$(curl -s --connect-timeout 3 --max-time 5 "https://ipapi.co/country_code/" 2>/dev/null || true)
        [[ "$country" == "CN" ]] && IS_CHINA=true
    fi

    if [[ "$IS_CHINA" == true ]]; then
        info "网络环境: 中国大陆 (自动启用加速)"
        find_github_proxy
    else
        info "网络环境: 国际网络 (直连)"
    fi
}

find_github_proxy() {
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/package.json"
        if curl -s --connect-timeout 3 --max-time 8 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "可用加速: ${proxy}"
            return 0
        fi
    done
    warn "未找到可用加速代理, 将尝试直连"
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
        windows)
            ip=$(ipconfig.exe 2>/dev/null | grep -i "IPv4" | grep -v "127.0.0.1" | head -1 | \
                 sed 's/.*: *//' | tr -d '\r ')
            if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\. ]]; then
                ip=$(powershell.exe -NoProfile -Command \
                    "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {\$_.InterfaceAlias -notlike '*Loopback*' -and \$_.IPAddress -ne '127.0.0.1'} | Select-Object -First 1).IPAddress" \
                    2>/dev/null | tr -d '\r ')
            fi
            ;;
        termux)
            ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
            ;;
        macos)
            ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
            ;;
        *)
            if command_exists ip; then
                ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
                [[ -z "$ip" ]] && ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
            fi
            [[ -z "$ip" ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            [[ -z "$ip" ]] && command_exists ifconfig && \
                ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
            ;;
    esac
    echo "${ip:-未知}"
}

get_public_ip() {
    local ip="" services=(
        "https://ifconfig.me"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
        "https://icanhazip.com"
    )
    for svc in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 3 --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]' | tr -d '\r')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# ==================== 配置文件管理 ====================
load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        source "$KSILLY_CONF" 2>/dev/null || true
        INSTALL_DIR="${KSILLY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    else
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    fi
}

save_config() {
    cat > "$KSILLY_CONF" << EOF
KSILLY_INSTALL_DIR="${INSTALL_DIR}"
KSILLY_IS_CHINA="${IS_CHINA}"
KSILLY_GITHUB_PROXY="${GITHUB_PROXY}"
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

# ==================== 脚本自保存 ====================
save_script_copy() {
    [[ -d "$INSTALL_DIR" ]] || return

    local target="$INSTALL_DIR/ksilly.sh"
    local source="${BASH_SOURCE[0]:-$0}"

    if [[ -f "$source" && -r "$source" && "$source" != "/dev/"* && "$source" != "/proc/"* ]]; then
        cp "$source" "$target" 2>/dev/null || true
    else
        local url="$KSILLY_RAW"
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && url="${GITHUB_PROXY}${url}"
        curl -fsSL $CURL_OPTS "$url" -o "$target" 2>/dev/null || true
    fi
    chmod +x "$target" 2>/dev/null || true

    if [[ -f "$target" ]]; then
        info "脚本已保存: ${target}"
    fi

    # Windows 额外保存 .bat
    if [[ "$PLATFORM" == "windows" ]]; then
        local bat_target="$INSTALL_DIR/ksilly.bat"
        if [[ ! -f "$bat_target" ]]; then
            local bat_url="$KSILLY_BAT_RAW"
            [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && bat_url="${GITHUB_PROXY}${bat_url}"
            curl -fsSL $CURL_OPTS "$bat_url" -o "$bat_target" 2>/dev/null || true
        fi
        if [[ -f "$bat_target" ]]; then
            info "Windows 启动器: ${bat_target}"
            info "后续可双击 ${CYAN}ksilly.bat${NC} 运行"
        fi
    else
        info "后续可运行: ${CYAN}bash ${target}${NC}"
    fi
}

# ==================== 包管理 ====================
update_pkg_cache() {
    info "更新软件包缓存..."
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get update -qq 2>/dev/null ;;
        yum)    $NEED_SUDO yum makecache -q 2>/dev/null ;;
        dnf)    $NEED_SUDO dnf makecache -q 2>/dev/null ;;
        pacman) $NEED_SUDO pacman -Sy --noconfirm 2>/dev/null ;;
        apk)    $NEED_SUDO apk update 2>/dev/null ;;
        zypper) $NEED_SUDO zypper refresh -q 2>/dev/null ;;
        pkg)    pkg update -y 2>/dev/null ;;
        brew)   brew update 2>/dev/null ;;
    esac
}

install_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get install -y -qq "$pkg" 2>/dev/null ;;
        yum)    $NEED_SUDO yum install -y -q "$pkg" 2>/dev/null ;;
        dnf)    $NEED_SUDO dnf install -y -q "$pkg" 2>/dev/null ;;
        pacman) $NEED_SUDO pacman -S --noconfirm --needed "$pkg" 2>/dev/null ;;
        apk)    $NEED_SUDO apk add "$pkg" 2>/dev/null ;;
        zypper) $NEED_SUDO zypper install -y "$pkg" 2>/dev/null ;;
        pkg)    pkg install -y "$pkg" 2>/dev/null ;;
        brew)   brew install "$pkg" 2>/dev/null ;;
        *)      return 1 ;;
    esac
}

# ==================== Git 安装 ====================
install_git() {
    if command_exists git; then
        info "Git 已安装 ($(git --version | awk '{print $3}'))"
        return 0
    fi

    step "安装 Git..."

    if [[ "$PLATFORM" == "windows" ]]; then
        error "Git 未找到 (不应该发生, bat 启动器应已安装)"
        error "请关闭此窗口, 重新运行 ksilly.bat"
        exit 1
    fi

    install_pkg git || { error "Git 安装失败, 请手动安装"; exit 1; }
    command_exists git && success "Git 安装完成" || { error "Git 安装失败"; exit 1; }
}

# ==================== Node.js 安装 ====================
check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ -n "$ver" && "$ver" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_nodejs() {
    if check_node_version; then
        info "Node.js 已安装 ($(node -v)), 满足要求 (≥v${MIN_NODE_VERSION})"
        return 0
    fi

    if command_exists node; then
        warn "当前 Node.js $(node -v) 版本过低, 需要 ≥v${MIN_NODE_VERSION}"
    fi

    step "安装 Node.js..."

    case "$PLATFORM" in
        windows)
            # Windows: bat 启动器应已安装, 这里尝试修复 PATH
            local node_paths=(
                "/c/Program Files/nodejs"
                "$PROGRAMFILES/nodejs"
                "$LOCALAPPDATA/Programs/nodejs"
            )
            for np in "${node_paths[@]}"; do
                if [[ -f "${np}/node.exe" ]] || [[ -f "${np}/node" ]]; then
                    export PATH="${np}:$PATH"
                    hash -r 2>/dev/null
                    break
                fi
            done
            if ! check_node_version; then
                error "Node.js 未找到或版本过低"
                error "请关闭此窗口, 重新运行 ksilly.bat"
                exit 1
            fi
            ;;
        termux)
            pkg install -y nodejs-lts 2>/dev/null || pkg install -y nodejs 2>/dev/null
            ;;
        macos)
            if command_exists brew; then
                brew install node@20 2>/dev/null
            else
                install_nodejs_binary
            fi
            ;;
        *)
            if [[ "$IS_CHINA" == true ]]; then
                install_nodejs_binary "https://npmmirror.com/mirrors/node"
            else
                install_nodejs_standard
            fi
            ;;
    esac

    hash -r 2>/dev/null || true

    if check_node_version; then
        success "Node.js $(node -v) 安装完成"
    else
        error "Node.js 安装失败"
        error "请手动安装 Node.js ≥v${MIN_NODE_VERSION}: https://nodejs.org/"
        exit 1
    fi
}

install_nodejs_standard() {
    case "$PKG_MANAGER" in
        apt)
            $NEED_SUDO apt-get install -y -qq ca-certificates curl gnupg 2>/dev/null
            $NEED_SUDO mkdir -p /etc/apt/keyrings
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
                $NEED_SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | \
                $NEED_SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
            $NEED_SUDO apt-get update -qq 2>/dev/null
            $NEED_SUDO apt-get install -y -qq nodejs 2>/dev/null
            ;;
        yum|dnf)
            curl -fsSL https://rpm.nodesource.com/setup_20.x | $NEED_SUDO bash - 2>/dev/null
            $NEED_SUDO $PKG_MANAGER install -y nodejs 2>/dev/null
            ;;
        pacman)
            $NEED_SUDO pacman -S --noconfirm nodejs npm 2>/dev/null
            ;;
        apk)
            $NEED_SUDO apk add nodejs npm 2>/dev/null
            ;;
        zypper)
            $NEED_SUDO zypper install -y nodejs20 npm20 2>/dev/null || \
            $NEED_SUDO zypper install -y nodejs npm 2>/dev/null
            ;;
        *)
            install_nodejs_binary
            ;;
    esac
}

install_nodejs_binary() {
    local mirror="${1:-https://nodejs.org/dist}"
    local node_ver="v20.18.0"
    local arch="" os_name="linux"

    [[ "$PLATFORM" == "macos" ]] && os_name="darwin"

    case "$(uname -m)" in
        x86_64|amd64)  arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l)        arch="armv7l" ;;
        *) error "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
    esac

    local filename="node-${node_ver}-${os_name}-${arch}.tar.xz"
    local download_url="${mirror}/${node_ver}/${filename}"
    info "下载: $download_url"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if curl -fSL --progress-bar $CURL_OPTS -o "${tmp_dir}/${filename}" "$download_url"; then
        info "解压并安装..."
        cd "$tmp_dir"
        tar xf "$filename"
        $NEED_SUDO cp -rf "node-${node_ver}-${os_name}-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
        $NEED_SUDO cp -rf "node-${node_ver}-${os_name}-${arch}"/{bin,include,lib} /usr/local/ 2>/dev/null
        cd - >/dev/null
    else
        error "Node.js 下载失败"
    fi

    rm -rf "$tmp_dir"
    hash -r 2>/dev/null || true
}

# ==================== 系统依赖安装 ====================
install_dependencies() {
    step "检查系统依赖..."
    get_sudo

    case "$PLATFORM" in
        windows)
            info "Windows 平台依赖检查..."

            if ! command_exists git; then
                local git_paths=(
                    "/c/Program Files/Git/cmd"
                    "/c/Program Files/Git/bin"
                    "$PROGRAMFILES/Git/cmd"
                )
                for gp in "${git_paths[@]}"; do
                    if [[ -d "$gp" ]]; then
                        export PATH="${gp}:$PATH"
                        hash -r 2>/dev/null
                        break
                    fi
                done
            fi

            if ! command_exists git; then
                error "Git 未找到"
                error "请关闭此窗口, 重新运行 ksilly.bat 自动安装"
                exit 1
            fi
            info "Git $(git --version | awk '{print $3}') ✓"

            if ! command_exists node; then
                local node_paths=(
                    "/c/Program Files/nodejs"
                    "$PROGRAMFILES/nodejs"
                    "$LOCALAPPDATA/Programs/nodejs"
                )
                for np in "${node_paths[@]}"; do
                    if [[ -d "$np" ]]; then
                        export PATH="${np}:$PATH"
                        hash -r 2>/dev/null
                        break
                    fi
                done
            fi

            if ! command_exists node; then
                error "Node.js 未找到"
                error "请关闭此窗口, 重新运行 ksilly.bat 自动安装"
                exit 1
            fi

            if ! check_node_version; then
                error "Node.js $(node -v) 版本过低, 需要 ≥v${MIN_NODE_VERSION}"
                exit 1
            fi

            info "Node.js $(node -v) ✓"
            info "npm v$(npm -v 2>/dev/null || echo '?') ✓"

            if [[ "$IS_CHINA" == true ]]; then
                npm config set registry https://registry.npmmirror.com 2>/dev/null || true
                info "npm 镜像: npmmirror"
            fi
            return 0
            ;;

        termux)
            pkg update -y 2>/dev/null
            pkg install -y curl wget git 2>/dev/null
            install_git
            install_nodejs
            ;;
        macos)
            install_git
            install_nodejs
            ;;
        *)
            if [[ "$PKG_MANAGER" != "none" && "$PKG_MANAGER" != "unknown" ]]; then
                update_pkg_cache
            fi
            for tool in curl wget tar; do
                command_exists "$tool" || install_pkg "$tool"
            done
            case "$PKG_MANAGER" in
                apt) command_exists xz || install_pkg xz-utils ;;
                yum|dnf) command_exists xz || install_pkg xz ;;
                pacman) command_exists xz || install_pkg xz ;;
            esac
            install_git
            install_nodejs
            ;;
    esac

    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null || true
        info "npm 镜像: npmmirror"
    fi
}

# ==================== PM2 管理 ====================
install_pm2() {
    if command_exists pm2; then
        info "PM2 已安装 ($(pm2 -v 2>/dev/null || echo '已安装'))"
        return 0
    fi

    step "安装 PM2 进程管理器..."

    if npm install -g pm2 2>/dev/null; then
        hash -r 2>/dev/null || true
        if command_exists pm2; then
            success "PM2 安装完成"
            return 0
        fi
    fi

    if [[ "$PLATFORM" != "termux" && "$PLATFORM" != "windows" ]]; then
        get_sudo
        if [[ -n "$NEED_SUDO" ]]; then
            $NEED_SUDO npm install -g pm2 2>/dev/null
            hash -r 2>/dev/null || true
        fi
    fi

    # Windows: 检查 npm 全局路径
    if [[ "$PLATFORM" == "windows" ]] && ! command_exists pm2; then
        local npm_prefix
        npm_prefix=$(npm config get prefix 2>/dev/null | tr -d '\r')
        if [[ -n "$npm_prefix" && -d "$npm_prefix" ]]; then
            export PATH="$npm_prefix:$PATH"
            hash -r 2>/dev/null || true
        fi
    fi

    if command_exists pm2; then
        success "PM2 安装完成"
    else
        warn "PM2 安装失败, 将使用前台模式运行"
        return 1
    fi
}

pm2_is_running() {
    command_exists pm2 || return 1
    pm2 describe "$PM2_APP_NAME" &>/dev/null 2>&1 && \
        pm2 describe "$PM2_APP_NAME" 2>/dev/null | grep -q "online"
}

pm2_start() {
    if ! command_exists pm2; then
        warn "PM2 未安装, 使用前台模式启动"
        cd "$INSTALL_DIR"
        info "按 Ctrl+C 停止运行"
        echo ""
        node server.js
        cd - >/dev/null 2>&1
        return
    fi

    if pm2_is_running; then
        info "SillyTavern 已在 PM2 中运行"
        return 0
    fi

    step "通过 PM2 启动 SillyTavern..."
    cd "$INSTALL_DIR"
    pm2 start server.js --name "$PM2_APP_NAME" --cwd "$INSTALL_DIR" 2>/dev/null
    cd - >/dev/null 2>&1

    sleep 2
    if pm2_is_running; then
        success "SillyTavern 已启动"
        return 0
    else
        error "启动失败"
        warn "查看日志: pm2 logs $PM2_APP_NAME"
        return 1
    fi
}

pm2_stop() {
    if ! command_exists pm2; then
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            success "SillyTavern 已停止 (PID: $pid)"
        else
            info "SillyTavern 未在运行"
        fi
        return
    fi

    if pm2_is_running; then
        pm2 stop "$PM2_APP_NAME" 2>/dev/null
        success "SillyTavern 已停止"
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            success "SillyTavern 已停止 (PID: $pid)"
        else
            info "SillyTavern 未在运行"
        fi
    fi
}

pm2_restart() {
    if command_exists pm2 && pm2 describe "$PM2_APP_NAME" &>/dev/null 2>&1; then
        pm2 restart "$PM2_APP_NAME" 2>/dev/null
        sleep 2
        if pm2_is_running; then
            success "SillyTavern 已重启"
        else
            error "重启失败"
        fi
    else
        pm2_stop
        sleep 1
        pm2_start
    fi
}

pm2_setup_startup() {
    if ! command_exists pm2; then
        warn "PM2 未安装, 无法设置开机自启"
        return 1
    fi

    case "$PLATFORM" in
        termux)
            warn "Termux 不支持 PM2 开机自启"
            info "请使用 Termux:Boot 应用实现开机启动"
            info "在 ~/.termux/boot/ 中创建启动脚本即可"
            return 0
            ;;
        windows)
            warn "Windows 下 PM2 开机自启需要额外配置"
            info "请参考: https://github.com/jessety/pm2-installer"
            return 0
            ;;
    esac

    step "配置 PM2 开机自启..."
    get_sudo

    local startup_output
    startup_output=$(pm2 startup 2>&1 || true)

    local sudo_cmd
    sudo_cmd=$(echo "$startup_output" | grep -E "^\s*sudo" | tail -1 || true)

    if [[ -n "$sudo_cmd" ]]; then
        eval "$sudo_cmd" 2>/dev/null || {
            warn "自动设置失败, 请手动运行:"
            echo -e "    ${CYAN}${sudo_cmd}${NC}"
        }
    fi

    pm2 save 2>/dev/null || true
    success "PM2 开机自启已配置"
}

pm2_remove_startup() {
    if command_exists pm2; then
        pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
        pm2 save --force 2>/dev/null || true
        local unstartup_output
        unstartup_output=$(pm2 unstartup 2>&1 || true)
        local sudo_cmd
        sudo_cmd=$(echo "$unstartup_output" | grep -E "^\s*sudo" | tail -1 || true)
        [[ -n "$sudo_cmd" ]] && eval "$sudo_cmd" 2>/dev/null || true
    fi
}

# ==================== 防火墙管理 ====================
open_firewall_port() {
    local port="$1"

    case "$PLATFORM" in
        termux|macos)
            return ;;
        windows)
            step "检查 Windows 防火墙端口 ${port}..."
            local rule_name="SillyTavern_${port}"
            local exists
            exists=$(powershell.exe -NoProfile -Command \
                "Get-NetFirewallRule -DisplayName '${rule_name}' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName" \
                2>/dev/null | tr -d '\r')
            if [[ "$exists" == "$rule_name" ]]; then
                info "Windows 防火墙: 端口 ${port} 已放行"
            else
                info "正在添加 Windows 防火墙规则..."
                powershell.exe -NoProfile -Command \
                    "Start-Process powershell -ArgumentList '-NoProfile','-Command','New-NetFirewallRule -DisplayName \"${rule_name}\" -Direction Inbound -Protocol TCP -LocalPort ${port} -Action Allow' -Verb RunAs -Wait" \
                    2>/dev/null
                if [[ $? -eq 0 ]]; then
                    success "Windows 防火墙: 已放行端口 ${port}"
                else
                    warn "防火墙规则添加失败 (可能用户取消了权限)"
                    warn "请手动在 Windows 防火墙中放行端口 ${port}"
                fi
            fi
            return ;;
    esac

    # Linux 防火墙
    get_sudo
    step "检查防火墙端口 ${port}..."

    local firewall_found=false

    # UFW
    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            if $NEED_SUDO ufw status 2>/dev/null | grep -qw "$port"; then
                info "UFW: 端口 ${port} 已放行"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW: 已放行端口 ${port}/tcp"
            fi
        fi
    fi

    # firewalld
    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 ${port} 已放行"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld: 已放行端口 ${port}/tcp"
            fi
        fi
    fi

    # iptables 兜底
    if [[ "$firewall_found" == false ]] && command_exists iptables; then
        local has_drop
        has_drop=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || echo "0")
        if [[ "$has_drop" -gt 0 ]]; then
            if ! $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
                success "iptables: 已放行端口 ${port}/tcp"
                command_exists iptables-save && {
                    [[ -d /etc/iptables ]] && $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null
                    command_exists netfilter-persistent && $NEED_SUDO netfilter-persistent save 2>/dev/null
                } || true
            else
                info "iptables: 端口 ${port} 已放行"
            fi
        else
            info "未检测到活动的防火墙"
        fi
    elif [[ "$firewall_found" == false ]]; then
        info "未检测到防火墙"
    fi

    echo ""
    warn "若使用云服务器, 请确保安全组也放行了端口 ${port}/tcp"
}

remove_firewall_port() {
    local port="$1"
    case "$PLATFORM" in
        termux|macos) return ;;
        windows)
            local rule_name="SillyTavern_${port}"
            powershell.exe -NoProfile -Command \
                "Start-Process powershell -ArgumentList '-NoProfile','-Command','Remove-NetFirewallRule -DisplayName \"${rule_name}\" -ErrorAction SilentlyContinue' -Verb RunAs -Wait" \
                2>/dev/null || true
            return ;;
    esac
    get_sudo
    if command_exists ufw; then
        $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
    fi
    if command_exists firewall-cmd; then
        $NEED_SUDO firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null || true
        $NEED_SUDO firewall-cmd --reload 2>/dev/null || true
    fi
}

# ==================== 访问信息显示 ====================
show_access_info() {
    local port
    port=$(get_port)

    local listen_mode
    listen_mode=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml" 2>/dev/null)

    echo ""
    divider
    echo -e "  ${BOLD}访问地址${NC}"
    divider

    if [[ "$listen_mode" == "true" ]]; then
        local local_ip public_ip
        local_ip=$(get_local_ip)
        public_ip=$(get_public_ip)

        echo -e "  本机访问:   ${CYAN}http://127.0.0.1:${port}${NC}"
        echo -e "  局域网访问: ${CYAN}http://${local_ip}:${port}${NC}"
        if [[ -n "$public_ip" ]]; then
            echo -e "  公网访问:   ${CYAN}http://${public_ip}:${port}${NC}"
        else
            echo -e "  公网访问:   ${DIM}(未获取到公网IP)${NC}"
        fi

        if [[ -n "$public_ip" && "$local_ip" != "$public_ip" && "$local_ip" != "未知" ]]; then
            echo -e "  ${DIM}提示: 局域网IP与公网IP不同, 可能需要配置端口转发${NC}"
        fi
    else
        echo -e "  访问地址: ${CYAN}http://127.0.0.1:${port}${NC}"
        echo -e "  ${DIM}(仅本机可访问, 如需远程访问请开启监听)${NC}"
    fi
    divider
}

# ==================== SillyTavern 克隆 ====================
clone_sillytavern() {
    step "安装 SillyTavern..."

    INSTALL_DIR=$(read_input "安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" ]]; then
            warn "目录已存在 SillyTavern: $INSTALL_DIR"
            if confirm "删除并重新安装?"; then
                pm2_stop
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

    # 选择分支
    echo ""
    echo -e "  ${BOLD}选择安装分支:${NC}"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}← 稳定版 (推荐)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}← 开发版 (最新功能)${NC}"
    echo ""

    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "选择 (1/2)" "1")
    done

    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"
    info "选择分支: ${branch}"

    # 克隆
    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")

    info "克隆仓库..."
    if run_with_timeout 300 git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" 2>&1 | tail -3; then
        success "仓库克隆完成"
    else
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "加速克隆失败, 尝试直连..."
            if run_with_timeout 300 git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR" 2>&1 | tail -3; then
                success "仓库克隆完成 (直连)"
            else
                error "克隆失败, 请检查网络"; exit 1
            fi
        else
            error "克隆失败, 请检查网络"; exit 1
        fi
    fi

    # 规范化换行符
    if [[ "$PLATFORM" == "macos" ]]; then
        find "$INSTALL_DIR" -name "*.yaml" -exec sed -i '' 's/\r$//' {} \; 2>/dev/null || true
    else
        find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    fi

    # npm install
    step "安装 npm 依赖..."
    cd "$INSTALL_DIR"
    if npm install --no-audit --no-fund --loglevel=error 2>&1 | tail -5; then
        success "npm 依赖安装完成"
    else
        error "npm 依赖安装失败"; exit 1
    fi
    cd - >/dev/null 2>&1

    save_config
}

# ==================== SillyTavern 初始配置 ====================
configure_sillytavern() {
    step "配置 SillyTavern..."

    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default/config.yaml"
    [[ ! -f "$default_file" ]] && default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed_i 's/\r$//' "$config_file" 2>/dev/null || true
            info "已生成 config.yaml"
        else
            error "未找到默认配置文件"; exit 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}配置向导${NC}"
    divider
    echo ""

    # === 远程访问 ===
    echo -e "  ${YELLOW}● 远程访问${NC}"
    echo -e "    ${DIM}开启后允许局域网/外网设备访问 (监听 0.0.0.0)${NC}"
    echo -e "    ${DIM}关闭则仅本机可访问 (127.0.0.1)${NC}"
    echo ""

    local listen_enabled=false
    if confirm "开启远程访问?"; then
        set_yaml_val "listen" "true" "$config_file"
        set_yaml_val "whitelistMode" "false" "$config_file"
        listen_enabled=true
        success "已开启远程访问, 白名单已自动关闭"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "仅本机访问"
    fi

    # === 端口 ===
    echo ""
    local port
    port=$(read_input "设置端口" "8000")
    while [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; do
        warn "端口号须为 1-65535 的数字"
        port=$(read_input "设置端口" "8000")
    done
    set_yaml_val "port" "$port" "$config_file"
    info "端口: ${port}"

    # === 基础认证 ===
    echo ""
    echo -e "  ${YELLOW}● 基础认证 (basicAuth)${NC}"
    echo -e "    ${DIM}访问时需输入用户名和密码${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "    ${RED}已开启远程访问, 强烈建议开启认证!${NC}"
    fi
    echo ""

    if confirm "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        echo ""
        local auth_user
        auth_user=$(read_input "设置用户名")
        while [[ -z "$auth_user" ]]; do
            warn "用户名不能为空"
            auth_user=$(read_input "设置用户名")
        done

        local auth_pass
        auth_pass=$(read_password "设置密码")

        local escaped_user escaped_pass
        escaped_user=$(escape_sed "$auth_user")
        escaped_pass=$(escape_sed "$auth_pass")

        if grep -q "basicAuthUser:" "$config_file" 2>/dev/null; then
            sed_i "/basicAuthUser:/,/^[^ #]/{
                s|username:.*|username: \"${escaped_user}\"|
                s|password:.*|password: \"${escaped_pass}\"|
            }" "$config_file"
        else
            cat >> "$config_file" << AUTHEOF
basicAuthUser:
  username: "${auth_user}"
  password: "${auth_pass}"
AUTHEOF
        fi

        success "认证已开启 (用户: ${auth_user})"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "认证未开启"
    fi

    # === 防火墙 ===
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置已保存"
}

# ==================== 后台运行与自启设置 ====================
setup_background() {
    echo ""
    divider
    echo -e "  ${BOLD}后台运行与开机自启${NC}"
    divider
    echo ""

    # 当前状态
    echo -e "  ${YELLOW}● 当前状态${NC}"
    if command_exists pm2; then
        echo -e "    PM2:  ${GREEN}已安装${NC} ($(pm2 -v 2>/dev/null || echo '?'))"
        if pm2_is_running; then
            echo -e "    运行: ${GREEN}● 运行中${NC}"
        else
            echo -e "    运行: ${RED}● 未运行${NC}"
        fi
        if pm2 describe "$PM2_APP_NAME" &>/dev/null 2>&1; then
            echo -e "    自启: ${GREEN}已注册${NC}"
        else
            echo -e "    自启: ${YELLOW}未注册${NC}"
        fi
    else
        echo -e "    PM2:  ${YELLOW}未安装${NC}"
        echo -e "    ${DIM}PM2 是跨平台进程管理器, 支持后台运行和开机自启${NC}"
    fi

    echo ""
    divider
    echo ""

    echo -e "  ${GREEN}1)${NC} 安装 PM2 并启用后台运行"
    echo -e "  ${GREEN}2)${NC} 设置开机自启"
    echo -e "  ${GREEN}3)${NC} 取消开机自启"
    echo ""
    echo -e "  ${RED}0)${NC} 返回"
    echo ""

    local choice
    choice=$(read_input "选择操作" "0")

    case "$choice" in
        1)
            install_pm2
            if command_exists pm2; then
                if pm2_is_running; then
                    info "SillyTavern 已在后台运行"
                elif confirm "立即通过 PM2 启动 SillyTavern?"; then
                    pm2_start
                    show_access_info
                fi
            fi
            ;;
        2)
            if ! command_exists pm2; then
                install_pm2 || return
            fi
            pm2_setup_startup
            ;;
        3)
            pm2_remove_startup
            success "开机自启已取消"
            ;;
        0|"") return ;;
        *) warn "无效选项" ;;
    esac
}

# ==================== 启动/停止/状态 ====================
start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    if pm2_is_running; then
        info "SillyTavern 已在运行中"
        show_access_info
        return 0
    fi

    local pid
    pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
    if [[ -n "$pid" ]]; then
        info "SillyTavern 已在运行中 (PID: $pid)"
        show_access_info
        return 0
    fi

    if command_exists pm2; then
        pm2_start
    else
        step "前台启动 SillyTavern..."
        show_access_info
        echo ""
        info "按 Ctrl+C 停止运行"
        echo ""
        cd "$INSTALL_DIR"
        node server.js
        cd - >/dev/null 2>&1
        return
    fi

    show_access_info
}

stop_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi
    step "停止 SillyTavern..."
    pm2_stop
}

restart_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    step "重启 SillyTavern..."
    if command_exists pm2 && pm2 describe "$PM2_APP_NAME" &>/dev/null 2>&1; then
        pm2_restart
    else
        pm2_stop
        sleep 1
        pm2_start
    fi
    show_access_info
}

show_status() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    print_banner

    echo -e "  ${BOLD}SillyTavern 状态${NC}"
    divider
    echo ""

    # 基本信息
    echo -e "  ${YELLOW}● 基本信息${NC}"
    echo -e "    安装目录: ${CYAN}${INSTALL_DIR}${NC}"

    if [[ -f "$INSTALL_DIR/package.json" ]]; then
        local version
        version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"\([0-9][^"]*\)".*/\1/')
        echo -e "    版本:     ${CYAN}${version:-未知}${NC}"
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        local branch
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")
        echo -e "    分支:     ${CYAN}${branch}${NC}"
    fi

    # 运行状态
    echo ""
    echo -e "  ${YELLOW}● 运行状态${NC}"

    local is_running=false
    if pm2_is_running; then
        echo -e "    状态: ${GREEN}● 运行中${NC} (PM2)"
        is_running=true
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            echo -e "    状态: ${GREEN}● 运行中${NC} (PID: $pid)"
            is_running=true
        else
            echo -e "    状态: ${RED}● 未运行${NC}"
        fi
    fi

    if command_exists pm2; then
        echo -e "    PM2:  ${GREEN}已安装${NC}"
    else
        echo -e "    PM2:  ${YELLOW}未安装${NC}"
    fi

    # 配置摘要
    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        echo ""
        echo -e "  ${YELLOW}● 配置摘要${NC}"

        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
        whitelist_val=$(get_yaml_val "whitelistMode" "$INSTALL_DIR/config.yaml")
        auth_val=$(get_yaml_val "basicAuthMode" "$INSTALL_DIR/config.yaml")
        port_val=$(get_port)
        ua_val=$(get_yaml_val "enableUserAccounts" "$INSTALL_DIR/config.yaml")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$INSTALL_DIR/config.yaml")

        echo -e "    端口:         ${CYAN}${port_val}${NC}"
        echo -e "    远程访问:     $(format_bool "${listen_val:-false}")"
        echo -e "    白名单模式:   $(format_bool "${whitelist_val:-true}")"
        echo -e "    基础认证:     $(format_bool "${auth_val:-false}")"
        echo -e "    用户账户:     $(format_bool "${ua_val:-false}")"
        echo -e "    离散登录:     $(format_bool "${dl_val:-false}")"
    fi

    if [[ "$is_running" == true ]]; then
        show_access_info
    fi
}

# ==================== 更新 ====================
update_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    step "检查更新..."

    cd "$INSTALL_DIR"

    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "release")

    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    info "正在获取远程仓库信息..."
    if ! run_with_timeout 30 git fetch --quiet 2>/dev/null; then
        warn "获取远程信息失败, 请检查网络"
        [[ "$IS_CHINA" == true ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null 2>&1
        return 1
    fi

    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "origin/$branch" 2>/dev/null)

    if [[ "$local_commit" == "$remote_commit" ]]; then
        echo ""
        success "当前已是最新版本 (${branch})"
        echo -e "    ${DIM}提交: ${local_commit:0:8}${NC}"
        [[ "$IS_CHINA" == true ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null 2>&1
        return 0
    fi

    local behind
    behind=$(git rev-list --count HEAD..origin/"$branch" 2>/dev/null || echo "?")

    echo ""
    divider
    echo -e "  ${BOLD}${GREEN}发现更新!${NC}"
    echo -e "    分支: ${CYAN}${branch}${NC}"
    echo -e "    落后: ${YELLOW}${behind}${NC} 个提交"
    echo ""
    echo -e "  ${DIM}最近更新内容:${NC}"
    git log --oneline HEAD..origin/"$branch" 2>/dev/null | head -5 | while IFS= read -r line; do
        echo -e "    ${DIM}• ${line}${NC}"
    done
    [[ "$behind" != "?" && "$behind" -gt 5 ]] && echo -e "    ${DIM}  ... 还有 $((behind - 5)) 个提交${NC}"
    divider
    echo ""

    if ! confirm "是否更新?"; then
        info "已取消更新"
        [[ "$IS_CHINA" == true ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null 2>&1
        return 0
    fi

    if pm2_is_running; then
        warn "正在停止 SillyTavern..."
        pm2_stop
    fi

    info "备份配置..."
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "配置已备份到: $backup_dir"

    info "拉取更新..."
    if git pull --ff-only 2>/dev/null; then
        success "代码更新完成"
    else
        warn "快速合并失败, 强制更新..."
        git fetch --all 2>/dev/null
        git reset --hard "origin/$branch" 2>/dev/null
        success "代码强制更新完成"
    fi

    [[ "$IS_CHINA" == true ]] && git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null

    # 规范化换行符
    if [[ "$PLATFORM" == "macos" ]]; then
        find . -name "*.yaml" -exec sed -i '' 's/\r$//' {} \; 2>/dev/null || true
    else
        find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    fi

    info "更新 npm 依赖..."
    npm install --no-audit --no-fund --loglevel=error 2>&1 | tail -3

    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        success "配置文件已恢复"
    fi

    cd - >/dev/null 2>&1

    success "SillyTavern 更新完成!"

    echo ""
    if confirm "立即启动?"; then
        pm2_start
        show_access_info
    fi
}

# ==================== 卸载 ====================
uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    echo ""
    warn "⚠  即将卸载 SillyTavern"
    echo -e "    安装目录: ${CYAN}${INSTALL_DIR}${NC}"
    echo ""

    confirm "确定要卸载吗? 此操作不可恢复!" || { info "已取消"; return 0; }
    confirm "再次确认: 删除所有数据?" || { info "已取消"; return 0; }

    pm2_stop

    local data_dir="$INSTALL_DIR/data"
    if [[ -d "$data_dir" ]]; then
        echo ""
        if confirm "备份聊天数据和角色卡?"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            cp -r "$data_dir" "$backup_path/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$backup_path/"
            success "数据已备份到: $backup_path"
        fi
    fi

    # PM2 清理
    if command_exists pm2; then
        pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
        pm2 save --force 2>/dev/null || true
    fi

    # 防火墙清理
    local port
    port=$(get_port)
    remove_firewall_port "$port"

    step "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    success "安装目录已删除"

    rm -f "$KSILLY_CONF"
    success "配置已清理"

    echo ""
    success "SillyTavern 卸载完成!"
}

# ==================== 查看日志 ====================
view_logs() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    if command_exists pm2; then
        step "SillyTavern 日志 (最近 50 行):"
        echo ""
        pm2 logs "$PM2_APP_NAME" --lines 50 --nostream 2>/dev/null || \
            warn "没有日志或 PM2 中未注册该应用"
    else
        warn "PM2 未安装, 无法查看日志"
        warn "请使用前台模式启动以查看输出"
    fi
}

# ==================== 配置修改菜单 ====================
modify_config_menu() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件不存在: $config_file"; return 1
    fi

    while true; do
        print_banner
        echo -e "  ${BOLD}配置修改${NC}"
        divider
        echo ""

        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        port_val=$(get_port)
        ua_val=$(get_yaml_val "enableUserAccounts" "$config_file")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$config_file")

        echo -e "  ${YELLOW}● 当前配置${NC}"
        echo -e "    端口:         ${CYAN}${port_val}${NC}"
        echo -e "    远程访问:     $(format_bool "${listen_val:-false}")"
        echo -e "    白名单模式:   $(format_bool "${whitelist_val:-true}")"
        echo -e "    基础认证:     $(format_bool "${auth_val:-false}")"
        echo -e "    用户账户:     $(format_bool "${ua_val:-false}")"
        echo -e "    离散登录:     $(format_bool "${dl_val:-false}")"
        echo ""
        divider
        echo ""

        echo -e "  ${GREEN}1)${NC} 远程访问 (listen)"
        echo -e "  ${GREEN}2)${NC} 白名单模式 (whitelistMode)"
        echo -e "  ${GREEN}3)${NC} 基础认证 (basicAuthMode)"
        echo -e "  ${GREEN}4)${NC} 端口 (port)"
        echo -e "  ${GREEN}5)${NC} 用户账户 (enableUserAccounts)"
        echo -e "  ${GREEN}6)${NC} 离散登录 (enableDiscreetLogin)"
        echo -e "  ${GREEN}7)${NC} 编辑配置文件"
        echo -e "  ${GREEN}8)${NC} 重置为默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""

        local choice
        choice=$(read_input "选择" "0")
        local changed=false

        case "$choice" in
            1)
                echo ""
                echo -e "  当前: $(format_bool "${listen_val:-false}")"
                if [[ "${listen_val:-false}" == "true" ]]; then
                    echo -e "  ${DIM}当前允许远程访问${NC}"
                    if confirm "关闭远程访问?"; then
                        set_yaml_val "listen" "false" "$config_file"
                        success "已关闭远程访问"
                        changed=true
                    fi
                else
                    echo -e "  ${DIM}当前仅本机访问${NC}"
                    if confirm "开启远程访问?"; then
                        set_yaml_val "listen" "true" "$config_file"
                        success "已开启远程访问"
                        changed=true
                        local p; p=$(get_port)
                        open_firewall_port "$p"
                    fi
                fi
                ;;
            2)
                echo ""
                echo -e "  当前: $(format_bool "${whitelist_val:-true}")"
                if [[ "${whitelist_val:-true}" == "true" ]]; then
                    echo -e "  ${DIM}白名单已开启, 仅白名单内IP可访问${NC}"
                    if confirm "关闭白名单模式?"; then
                        set_yaml_val "whitelistMode" "false" "$config_file"
                        success "已关闭白名单"
                        changed=true
                    fi
                else
                    echo -e "  ${DIM}白名单已关闭${NC}"
                    if confirm "开启白名单模式?"; then
                        set_yaml_val "whitelistMode" "true" "$config_file"
                        success "已开启白名单"
                        changed=true
                    fi
                fi
                ;;
            3)
                echo ""
                echo -e "  当前: $(format_bool "${auth_val:-false}")"
                if [[ "${auth_val:-false}" == "true" ]]; then
                    echo -e "  ${DIM}基础认证已开启${NC}"
                    echo ""
                    echo -e "  ${GREEN}1)${NC} 关闭认证"
                    echo -e "  ${GREEN}2)${NC} 修改用户名/密码"
                    echo -e "  ${RED}0)${NC} 取消"
                    echo ""
                    local auth_choice
                    auth_choice=$(read_input "选择" "0")
                    case "$auth_choice" in
                        1)
                            set_yaml_val "basicAuthMode" "false" "$config_file"
                            success "已关闭认证"
                            changed=true
                            ;;
                        2)
                            local u p eu ep
                            u=$(read_input "新用户名")
                            while [[ -z "$u" ]]; do warn "不能为空"; u=$(read_input "新用户名"); done
                            p=$(read_password "新密码")
                            eu=$(escape_sed "$u"); ep=$(escape_sed "$p")
                            if grep -q "basicAuthUser:" "$config_file" 2>/dev/null; then
                                sed_i "/basicAuthUser:/,/^[^ #]/{
                                    s|username:.*|username: \"${eu}\"|
                                    s|password:.*|password: \"${ep}\"|
                                }" "$config_file"
                            fi
                            success "认证信息已更新"
                            changed=true
                            ;;
                    esac
                else
                    echo -e "  ${DIM}基础认证已关闭${NC}"
                    if confirm "开启基础认证?"; then
                        set_yaml_val "basicAuthMode" "true" "$config_file"
                        local u p eu ep
                        u=$(read_input "设置用户名")
                        while [[ -z "$u" ]]; do warn "不能为空"; u=$(read_input "设置用户名"); done
                        p=$(read_password "设置密码")
                        eu=$(escape_sed "$u"); ep=$(escape_sed "$p")
                        if grep -q "basicAuthUser:" "$config_file" 2>/dev/null; then
                            sed_i "/basicAuthUser:/,/^[^ #]/{
                                s|username:.*|username: \"${eu}\"|
                                s|password:.*|password: \"${ep}\"|
                            }" "$config_file"
                        else
                            cat >> "$config_file" << AUTHEOF
basicAuthUser:
  username: "${u}"
  password: "${p}"
AUTHEOF
                        fi
                        success "认证已开启 (用户: $u)"
                        changed=true
                    fi
                fi
                ;;
            4)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                if confirm "修改端口?"; then
                    local np
                    np=$(read_input "新端口" "$port_val")
                    if [[ "$np" =~ ^[0-9]+$ ]] && [[ "$np" -ge 1 && "$np" -le 65535 ]]; then
                        set_yaml_val "port" "$np" "$config_file"
                        success "端口已改为: $np"
                        changed=true
                        local cl; cl=$(get_yaml_val "listen" "$config_file")
                        [[ "$cl" == "true" ]] && open_firewall_port "$np"
                    else
                        error "无效端口: $np"
                    fi
                fi
                ;;
            5)
                echo ""
                echo -e "  当前: $(format_bool "${ua_val:-false}")"
                echo -e "  ${DIM}用户账户系统允许多用户独立使用 SillyTavern${NC}"
                if [[ "${ua_val:-false}" == "true" ]]; then
                    if confirm "关闭用户账户?"; then
                        set_yaml_val "enableUserAccounts" "false" "$config_file"
                        success "已关闭用户账户"
                        changed=true
                    fi
                else
                    if confirm "开启用户账户?"; then
                        set_yaml_val "enableUserAccounts" "true" "$config_file"
                        success "已开启用户账户"
                        changed=true
                    fi
                fi
                ;;
            6)
                echo ""
                echo -e "  当前: $(format_bool "${dl_val:-false}")"
                echo -e "  ${DIM}离散登录模式隐藏 SillyTavern 标识, 提供更私密的登录页${NC}"
                if [[ "${dl_val:-false}" == "true" ]]; then
                    if confirm "关闭离散登录?"; then
                        set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                        success "已关闭离散登录"
                        changed=true
                    fi
                else
                    if confirm "开启离散登录?"; then
                        set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                        success "已开启离散登录"
                        changed=true
                    fi
                fi
                ;;
            7)
                local editor=""
                for e in nano vim vi; do
                    command_exists "$e" && { editor="$e"; break; }
                done
                if [[ -n "$editor" ]]; then
                    $editor "$config_file"
                    changed=true
                else
                    error "未找到文本编辑器 (nano/vim/vi)"
                fi
                ;;
            8)
                if confirm "重置为默认配置? 当前配置将丢失!"; then
                    local df="$INSTALL_DIR/default/config.yaml"
                    [[ ! -f "$df" ]] && df="$INSTALL_DIR/default.yaml"
                    if [[ -f "$df" ]]; then
                        cp "$df" "$config_file"
                        sed_i 's/\r$//' "$config_file" 2>/dev/null || true
                        success "已重置为默认配置"
                        changed=true
                    else
                        error "找不到默认配置文件"
                    fi
                fi
                ;;
            9)
                local fp; fp=$(get_port)
                open_firewall_port "$fp"
                ;;
            0|"")
                return 0
                ;;
            *)
                warn "无效选项"
                ;;
        esac

        # 修改后提示重启
        if [[ "$changed" == true ]]; then
            echo ""
            if pm2_is_running; then
                warn "修改将在重启后生效"
                if confirm "立即重启 SillyTavern?"; then
                    pm2_restart
                fi
            fi
        fi

        pause_key
    done
}

# ==================== 完整安装流程 ====================
full_install() {
    print_banner

    echo -e "  ${BOLD}${GREEN}开始安装 SillyTavern${NC}"
    divider
    echo ""

    show_platform_info
    detect_network
    echo ""

    install_dependencies
    echo ""

    clone_sillytavern
    echo ""

    configure_sillytavern
    echo ""

    install_pm2
    echo ""

    save_config
    save_script_copy

    echo ""
    divider
    echo -e "  ${BOLD}${GREEN}🎉 安装完成!${NC}"
    divider
    echo ""

    info "安装目录: $INSTALL_DIR"

    show_access_info

    echo ""
    if confirm "立即启动 SillyTavern?"; then
        pm2_start
        echo ""
        show_access_info
    else
        echo ""
        info "后续启动方式:"
        if command_exists pm2; then
            echo -e "    ${CYAN}pm2 start sillytavern${NC}"
        fi
        echo -e "    ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
        if [[ "$PLATFORM" == "windows" ]]; then
            echo -e "    ${CYAN}双击 ksilly.bat${NC}"
        else
            echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
        fi
    fi

    echo ""
    if confirm "设置开机自启?"; then
        if ! pm2_is_running; then
            pm2_start 2>/dev/null
        fi
        pm2_setup_startup
    fi
}

# ==================== 主菜单 ====================
main_menu() {
    while true; do
        print_banner
        load_config

        # 状态行
        if check_installed; then
            local version="" branch_name=""
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"\([0-9][^"]*\)".*/\1/')
            [[ -d "$INSTALL_DIR/.git" ]] && \
                branch_name=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)

            local status_icon="${RED}●${NC}"
            local status_text="已停止"
            if pm2_is_running; then
                status_icon="${GREEN}●${NC}"
                status_text="运行中"
            else
                local pid
                pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
                if [[ -n "$pid" ]]; then
                    status_icon="${GREEN}●${NC}"
                    status_text="运行中"
                fi
            fi
            echo -e "  ${status_icon} ${status_text}  ${DIM}|${NC}  v${version:-?}  ${DIM}|${NC}  ${branch_name:-?}  ${DIM}|${NC}  ${INSTALL_DIR}"
        else
            echo -e "  ${YELLOW}● 未安装${NC}"
        fi
        echo ""
        divider
        echo ""

        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "    ${GREEN}1)${NC}  全新安装"
        echo -e "    ${GREEN}2)${NC}  检查更新"
        echo -e "    ${GREEN}3)${NC}  卸载"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "    ${GREEN}4)${NC}  启动"
        echo -e "    ${GREEN}5)${NC}  停止"
        echo -e "    ${GREEN}6)${NC}  重启"
        echo -e "    ${GREEN}7)${NC}  查看状态"
        echo ""
        echo -e "  ${BOLD}配置与维护${NC}"
        echo -e "    ${GREEN}8)${NC}  修改配置"
        echo -e "    ${GREEN}9)${NC}  查看日志"
        echo -e "    ${GREEN}10)${NC} 后台运行/开机自启"
        echo ""
        echo -e "  ${RED}0)${NC}  退出"
        echo ""
        divider

        local choice
        choice=$(read_input "选择操作")

        case "$choice" in
            1)
                if check_installed; then
                    warn "SillyTavern 已安装: $INSTALL_DIR"
                    confirm "重新安装?" || continue
                fi
                full_install
                pause_key
                ;;
            2)
                detect_network
                update_sillytavern
                pause_key
                ;;
            3)
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
                view_logs
                pause_key
                ;;
            10)
                if ! check_installed; then
                    error "请先安装 SillyTavern"
                else
                    setup_background
                fi
                pause_key
                ;;
            0|"")
                echo ""
                info "再见~ 👋"
                echo ""
                exit 0
                ;;
            *)
                warn "无效选项"
                sleep 0.5
                ;;
        esac
    done
}

# ==================== 入口 ====================
main() {
    # 防止 curl | bash 导致 stdin 不可用
    if [[ ! -t 0 ]]; then
        if [[ -e /dev/tty ]]; then
            exec </dev/tty
        else
            echo "错误: 请使用 bash <(curl ...) 方式运行, 而不是 curl ... | bash"
            exit 1
        fi
    fi

    detect_platform
    load_config

    case "${1:-}" in
        install)
            detect_network
            full_install
            ;;
        update)
            detect_network
            update_sillytavern
            ;;
        start)    start_sillytavern ;;
        stop)     stop_sillytavern ;;
        restart)  restart_sillytavern ;;
        status)   show_status ;;
        config)   modify_config_menu ;;
        logs)     view_logs ;;
        uninstall) uninstall_sillytavern ;;
        "")       main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|config|logs|uninstall}"
            echo "  不带参数进入交互式菜单"
            exit 1
            ;;
    esac
}

main "$@"
