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
#  版本: 2.1.0
#

# ==================== 全局常量 ====================
SCRIPT_VERSION="2.1.0"
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
INSTALL_LOG="/tmp/ksilly_install_$$.log"

# ==================== 信号处理 ====================
trap 'echo ""; warn "哼，跑掉了呢...杂鱼♡"; rm -f "$INSTALL_LOG"; exit 130' INT

# ==================== 进度条函数 ====================

# 简单的步骤进度条 - 用于已知步骤数的安装流程
# 用法: show_progress $current $total "描述"
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 4))
    local empty=$((25 - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    printf "\r  ${PINK}♡${NC} [${CYAN}%s${NC}] ${BOLD}%3d%%${NC} %s" "$bar" "$percent" "$desc"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# 旋转动画 - 用于不确定耗时的操作
# 用法: spin_start "描述" 
#       执行操作...
#       spin_stop
SPIN_PID=""
spin_start() {
    local desc="$1"
    (
        local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        while true; do
            local char="${spinchars:i%${#spinchars}:1}"
            printf "\r  ${PINK}%s${NC} %s..." "$char" "$desc"
            i=$((i + 1))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
    disown $SPIN_PID 2>/dev/null
}

spin_stop() {
    if [[ -n "$SPIN_PID" ]]; then
        kill $SPIN_PID 2>/dev/null
        wait $SPIN_PID 2>/dev/null
        SPIN_PID=""
        printf "\r\033[K"  # 清除当前行
    fi
}

# 带进度条执行命令（安装类），屏蔽所有复杂输出到日志文件
# 用法: run_silent "描述" 命令...
run_silent() {
    local desc="$1"
    shift
    spin_start "$desc"
    if "$@" >> "$INSTALL_LOG" 2>&1; then
        spin_stop
        info "$desc ...才不是特意帮你弄好的呢 ✓"
        return 0
    else
        spin_stop
        error "$desc 失败了...不是人家的问题哦，看看日志吧杂鱼: $INSTALL_LOG"
        return 1
    fi
}

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
    echo -e "  ${BOLD}SillyTavern 一键部署脚本${NC} ${DIM}v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}by Mia1889 · github.com/Mia1889/Ksilly${NC}"
    echo -e "  ${PINK}♡ 才不是为了你才做的呢${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
ask()     { echo -e "  ${PINK}♡${NC} $1"; }
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
        echo -ne "  ${PINK}♡${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) warn "y 或者 n 都分不清吗...杂鱼♡" ;;
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
    echo -e "  ${YELLOW}⚠ 输入密码的时候看不到字是正常的啦...不会连这个都要人家教吧？杂鱼♡${NC}" >&2
    while [[ -z "$result" ]]; do
        echo -ne "  ${PINK}→${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "空密码？你认真的吗...再输一次啦！"
        fi
    done
    echo "$result"
}

pause_key() {
    echo ""
    read -rp "  按 Enter 继续...才不是在等你呢 ♡ "
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
        error "需要 root 权限但找不到 sudo...连权限都没有就来装软件了吗，杂鱼♡"
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
    echo -e "  ${BOLD}访问地址 ${PINK}♡${NC} ${DIM}(记好了哦杂鱼)${NC}"
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
            echo -e "    公网访问   → ${YELLOW}获取不到公网IP呢...自己查去吧♡${NC}"
        fi
    fi
}

# ==================== 配置管理 ====================

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
    step "检测运行环境...让人家看看你用的什么破机器♡"

    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        IS_TERMUX=true
        OS_TYPE="termux"
        PKG_MANAGER="pkg"
        NEED_SUDO=""
        info "Termux (Android) ...用手机装酒馆？真有你的呢杂鱼♡"
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
            info "Debian/Ubuntu ($OS_TYPE) ← 还行，没用太奇怪的系统"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "RHEL/CentOS ($OS_TYPE) ← 古早味系统呢♡"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "Arch ($OS_TYPE) ← 哦~用Arch的吗，有点东西嘛"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "Alpine ← 小巧的系统呢"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "macOS ← 果子用户是吧♡"
            ;;
        *)
            warn "这什么奇怪的系统: $OS_TYPE...算了勉强试试吧"
            PKG_MANAGER="unknown"
            ;;
    esac
}

detect_network() {
    step "检测网络环境...看看杂鱼的网络行不行♡"

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
        info "中国大陆网络 ← 人家帮你开加速镜像了，感谢我吧♡"
        find_github_proxy
    else
        IS_CHINA=false
        info "国际网络 ← 直连 GitHub，真好呢~"
    fi
}

find_github_proxy() {
    info "帮你找能用的代理呢...真是操心♡"
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "找到啦~ ${proxy}"
            return 0
        fi
    done
    warn "代理全挂了呢...硬连吧杂鱼♡"
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
        pkg)    run_silent "更新软件包索引" pkg update -y ;;
        apt)    run_silent "更新软件包索引" $NEED_SUDO apt-get update -qq ;;
        yum)    run_silent "更新软件包索引" $NEED_SUDO yum makecache -q ;;
        dnf)    run_silent "更新软件包索引" $NEED_SUDO dnf makecache -q ;;
        pacman) run_silent "更新软件包索引" $NEED_SUDO pacman -Sy --noconfirm ;;
        apk)    run_silent "更新软件包索引" $NEED_SUDO apk update ;;
        brew)   run_silent "更新软件包索引" brew update ;;
    esac
}

install_git() {
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') ✓ 已经有了嘛"
        return 0
    fi

    case "$PKG_MANAGER" in
        pkg)    run_silent "安装 Git" pkg install -y git ;;
        apt)    run_silent "安装 Git" $NEED_SUDO apt-get install -y -qq git ;;
        yum)    run_silent "安装 Git" $NEED_SUDO yum install -y -q git ;;
        dnf)    run_silent "安装 Git" $NEED_SUDO dnf install -y -q git ;;
        pacman) run_silent "安装 Git" $NEED_SUDO pacman -S --noconfirm git ;;
        apk)    run_silent "安装 Git" $NEED_SUDO apk add git ;;
        brew)   run_silent "安装 Git" brew install git ;;
        *)      error "不知道怎么装 git 啦...自己想办法吧杂鱼"; return 1 ;;
    esac

    command_exists git && info "Git 装好了♡" || { error "Git 装不上...杂鱼的环境有问题吧"; return 1; }
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ -n "$ver" && "$ver" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) ✓ 版本够用"
        return 0
    fi

    command_exists node && warn "Node.js $(node -v) 版本太旧了啦~ 需要 v${MIN_NODE_VERSION}+ 才行"

    step "安装 Node.js...等着吧杂鱼♡"

    if [[ "$IS_TERMUX" == true ]]; then
        install_nodejs_termux
    elif [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi

    hash -r 2>/dev/null || true

    if check_node_version; then
        info "Node.js $(node -v) 装好啦~ 感恩吧♡"
    else
        error "Node.js 没装上...你的系统是不是有什么问题啊杂鱼"; return 1
    fi

    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null
        info "npm 镜像已切换到 npmmirror ♡"
    fi
}

install_nodejs_termux() {
    run_silent "安装 Node.js (Termux)" pkg install -y nodejs || \
    run_silent "安装 Node.js LTS (Termux)" pkg install -y nodejs-lts
}

install_nodejs_standard() {
    case "$PKG_MANAGER" in
        apt)
            run_silent "安装必要工具" $NEED_SUDO apt-get install -y -qq ca-certificates curl gnupg
            $NEED_SUDO mkdir -p /etc/apt/keyrings 2>/dev/null
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                | $NEED_SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
                | $NEED_SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
            run_silent "更新源" $NEED_SUDO apt-get update -qq
            run_silent "安装 Node.js" $NEED_SUDO apt-get install -y -qq nodejs
            ;;
        yum|dnf)
            spin_start "配置 NodeSource 源"
            curl -fsSL https://rpm.nodesource.com/setup_20.x | $NEED_SUDO bash - >> "$INSTALL_LOG" 2>&1
            spin_stop
            run_silent "安装 Node.js" $NEED_SUDO $PKG_MANAGER install -y nodejs
            ;;
        pacman) run_silent "安装 Node.js" $NEED_SUDO pacman -S --noconfirm nodejs npm ;;
        apk)    run_silent "安装 Node.js" $NEED_SUDO apk add nodejs npm ;;
        brew)   run_silent "安装 Node.js" brew install node@20 ;;
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
        *) error "这什么奇怪的 CPU 架构: $(uname -m) ...人家搞不定啦"; return 1 ;;
    esac

    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    spin_start "下载 Node.js ${node_ver}"
    if curl -fSL -o "${tmp_dir}/${filename}" "${mirror}/${node_ver}/${filename}" >> "$INSTALL_LOG" 2>&1; then
        spin_stop
        info "下载完成 ✓"
        spin_start "解压并安装 Node.js"
        cd "$tmp_dir"
        tar xf "$filename" >> "$INSTALL_LOG" 2>&1
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib} /usr/local/ 2>/dev/null
        cd - >/dev/null
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
        spin_stop
        info "Node.js 安装完成 ✓"
    else
        spin_stop
        rm -rf "$tmp_dir"
        error "Node.js 下载失败了...网络不行吧杂鱼"; return 1
    fi
}

install_dependencies() {
    step "安装系统依赖...帮杂鱼把环境搞好♡"

    local total_steps=4
    local current_step=0

    [[ "$IS_TERMUX" != true ]] && get_sudo

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "更新软件包索引..."
    update_pkg_cache

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "安装基础工具..."
    if [[ "$IS_TERMUX" == true ]]; then
        run_silent "安装基础工具" pkg install -y curl git
    else
        case "$PKG_MANAGER" in
            apt)    run_silent "安装基础工具" $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils ;;
            yum)    run_silent "安装基础工具" $NEED_SUDO yum install -y -q curl wget tar xz ;;
            dnf)    run_silent "安装基础工具" $NEED_SUDO dnf install -y -q curl wget tar xz ;;
            pacman) run_silent "安装基础工具" $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz ;;
            apk)    run_silent "安装基础工具" $NEED_SUDO apk add curl wget tar xz ;;
            brew)   : ;;
        esac
    fi

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "安装 Git..."
    install_git

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "安装 Node.js..."
    install_nodejs
}

# ==================== PM2 管理 ====================

install_pm2() {
    if command_exists pm2; then
        info "PM2 $(pm2 -v 2>/dev/null) ✓"
        return 0
    fi
    run_silent "安装 PM2" npm install -g pm2
    if command_exists pm2; then
        info "PM2 安装完成♡"
        return 0
    else
        warn "全局安装失败了呢...用 npx 凑合吧杂鱼"
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
    install_pm2 || { error "PM2 用不了...杂鱼想办法吧"; return 1; }

    cd "$INSTALL_DIR"
    if is_pm2_managed; then
        pm2 restart "$SERVICE_NAME" >> "$INSTALL_LOG" 2>&1
    else
        pm2 start server.js --name "$SERVICE_NAME" >> "$INSTALL_LOG" 2>&1
    fi
    pm2 save >> "$INSTALL_LOG" 2>&1
    cd - >/dev/null

    sleep 2
    if is_pm2_online; then
        success "SillyTavern 在后台跑起来了哦~ 不用谢♡"
        show_access_info
        return 0
    else
        error "启动失败了...用 'pm2 logs $SERVICE_NAME' 看看怎么回事吧杂鱼"
        return 1
    fi
}

pm2_stop() {
    if is_pm2_online; then
        pm2 stop "$SERVICE_NAME" >> "$INSTALL_LOG" 2>&1
        pm2 save >> "$INSTALL_LOG" 2>&1
        info "SillyTavern 已停下来了♡"
    elif command_exists pgrep; then
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            info "进程已经被人家干掉了♡"
        else
            info "本来就没在跑呀...杂鱼在慌什么♡"
        fi
    else
        info "没有在运行呢~ 杂鱼多虑了♡"
    fi
}

pm2_remove() {
    if is_pm2_managed; then
        pm2 delete "$SERVICE_NAME" >> "$INSTALL_LOG" 2>&1
        pm2 save >> "$INSTALL_LOG" 2>&1
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
        pm2 save >> "$INSTALL_LOG" 2>&1
        success "Termux 开机自启搞定啦♡"
        warn "记得装 Termux:Boot 哦~ 不然白设了"
    else
        echo ""
        info "生成自启动配置中..."
        local startup_cmd
        startup_cmd=$(pm2 startup 2>&1 | grep -E "sudo|env" | head -1 || true)
        if [[ -n "$startup_cmd" ]]; then
            info "来，把下面这条命令复制去执行:"
            echo ""
            echo -e "    ${CYAN}${startup_cmd}${NC}"
            echo ""
            info "执行完了再跑一下: ${CYAN}pm2 save${NC}"
            echo -e "    ${DIM}连这都要人家手把手教...杂鱼♡${NC}"
        else
            get_sudo
            pm2 startup >> "$INSTALL_LOG" 2>/dev/null || true
            pm2 save >> "$INSTALL_LOG" 2>/dev/null
            info "自启动配置完成~"
        fi
    fi
}

pm2_remove_autostart() {
    if [[ "$IS_TERMUX" == true ]]; then
        rm -f "$HOME/.termux/boot/sillytavern.sh"
        info "Termux 自启已移除"
    else
        pm2 unstartup >> "$INSTALL_LOG" 2>/dev/null || true
        info "PM2 自启已移除♡"
    fi
}

migrate_from_systemd() {
    [[ "$IS_TERMUX" == true ]] && return
    command_exists systemctl || return

    if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        warn "发现旧版 systemd 服务...该升级了杂鱼♡"
        info "新版改用 PM2 啦，更好用哦~"
        if confirm "移除旧版 systemd 服务?"; then
            get_sudo
            $NEED_SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
            success "旧服务清理掉了~ 干干净净♡"
        fi
    fi
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"

    if [[ "$IS_TERMUX" == true ]]; then
        info "Termux 不需要管防火墙啦~"
        return
    fi

    get_sudo || return

    step "检查防火墙...帮杂鱼把端口打通♡"
    local firewall_found=false

    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW: 端口 $port 早就开了嘛~"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW: 端口 $port/tcp 放行了♡"
            fi
        fi
    fi

    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 $port 已放行~"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld: 端口 $port/tcp 搞定♡"
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
                success "iptables: 端口 $port/tcp 放行♡"
            else
                info "iptables: 端口 $port 已经放行了嘛"
            fi
        fi
    fi

    [[ "$firewall_found" == false ]] && info "没检测到防火墙，不用管~"

    echo ""
    warn "用云服务器的杂鱼记得去安全组也放行端口 ${port}/tcp 哦♡"
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

# ==================== SillyTavern 核心操作 ====================

clone_sillytavern() {
    step "克隆 SillyTavern 仓库...人家帮你拉代码了♡"

    INSTALL_DIR=$(read_input "安装目录 (不知道就按回车)" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "这里已经装过了呢~"
            if confirm "删掉重装？"; then
                rm -rf "$INSTALL_DIR"
            else
                info "那就保留吧♡"
                return 0
            fi
        else
            error "目录存在但不是酒馆: $INSTALL_DIR ...杂鱼搞什么呢"
            return 1
        fi
    fi

    echo ""
    ask "选一个分支吧杂鱼~"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}稳定版 (怕出问题的杂鱼选这个♡)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}开发版 (喜欢尝鲜？胆子不小嘛~)${NC}"
    echo ""

    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "选择" "1")
    done

    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"
    info "分支: $branch"

    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")

    spin_start "克隆仓库中 (可能要一会儿哦~)"
    local clone_success=false
    if git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" >> "$INSTALL_LOG" 2>&1; then
        clone_success=true
    elif [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        spin_stop
        warn "代理不行呢，试试直连..."
        spin_start "直连克隆中"
        if git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR" >> "$INSTALL_LOG" 2>&1; then
            clone_success=true
        fi
    fi
    spin_stop

    if [[ "$clone_success" == true ]]; then
        success "仓库拉下来了♡"
    else
        error "克隆失败...网络有问题吧杂鱼"
        return 1
    fi

    # 规范化换行符
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖...这步可能有点慢，杂鱼耐心等着♡"
    cd "$INSTALL_DIR"
    
    spin_start "安装 npm 依赖"
    if npm install --no-audit --no-fund >> "$INSTALL_LOG" 2>&1; then
        spin_stop
        success "npm 依赖全部装好了♡"
    else
        spin_stop
        error "npm 依赖安装炸了...查查日志吧: $INSTALL_LOG"
        cd - >/dev/null
        return 1
    fi
    cd - >/dev/null

    save_config
}

configure_sillytavern() {
    step "配置 SillyTavern...人家帮你设好♡"

    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed -i 's/\r$//' "$config_file"
            info "配置文件生成好了~"
        else
            error "default.yaml 都没有...这仓库有问题吧"; return 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}${PINK}♡ 配置向导 ♡${NC} ${DIM}(跟着人家选就行了杂鱼~)${NC}"
    divider

    # --- 监听设置 ---
    echo ""
    echo -e "  ${BOLD}1. 监听模式${NC}"
    echo -e "     ${DIM}开了就能让别的设备也访问你的酒馆哦~${NC}"
    echo -e "     ${DIM}不开就只能自己本机玩♡${NC}"
    echo ""

    local listen_enabled=false
    if confirm "开启监听 (允许远程访问)?"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        success "监听开啦~ 别人也能来了♡"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "好吧，自己一个人玩呗~"
    fi

    # --- 端口 ---
    echo ""
    echo -e "  ${BOLD}2. 端口设置${NC}"
    local port
    port=$(read_input "设置端口号 (不懂就默认)" "8000")
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        set_yaml_val "port" "$port" "$config_file"
        info "端口: $port ✓"
    else
        warn "这端口号不对吧...算了用默认 8000"
        port="8000"
    fi

    # --- 白名单 ---
    echo ""
    echo -e "  ${BOLD}3. 白名单模式${NC}"
    echo -e "     ${DIM}开着的话只有白名单里的 IP 能访问${NC}"
    echo -e "     ${DIM}要远程用的话建议关掉♡${NC}"
    echo ""
    if confirm "关闭白名单模式?"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        success "白名单关了~ 谁都能来了♡"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "白名单留着吧"
    fi

    # --- 基础认证 ---
    echo ""
    echo -e "  ${BOLD}4. 基础认证 (HTTP Auth)${NC}"
    echo -e "     ${DIM}进酒馆需要输用户名密码${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "     ${RED}都开远程了不设密码？杂鱼想被人白嫖吗♡ 建议开启！${NC}"
    fi
    echo ""
    if confirm "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        echo ""
        local auth_user=""
        while [[ -z "$auth_user" ]]; do
            auth_user=$(read_input "设一个用户名")
            [[ -z "$auth_user" ]] && warn "空的？认真点啦杂鱼！"
        done

        local auth_pass
        auth_pass=$(read_password "设一个密码")

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

        success "认证设好了~ 用户: $auth_user ♡"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "不设就不设吧...裸奔可别怪人家没提醒♡"
    fi

    # --- 防火墙 ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置全部搞定了！感谢人家吧杂鱼~ ♡"
}

setup_background() {
    echo ""
    divider
    echo -e "  ${BOLD}${PINK}♡ 后台运行设置 ♡${NC}"
    divider

    [[ "$IS_TERMUX" != true ]] && get_sudo 2>/dev/null
    migrate_from_systemd

    echo ""
    echo -e "  ${BOLD}● PM2 后台运行${NC}"
    echo -e "    ${DIM}关了终端也不会停，多贴心♡${NC}"
    echo -e "    ${DIM}还能自动重启，比杂鱼可靠多了~${NC}"
    echo ""

    if confirm "启用 PM2 后台运行?"; then
        install_pm2 || return 1
        success "PM2 就绪♡"

        echo ""
        if confirm "顺便设个开机自启?"; then
            pm2_setup_autostart
        fi
    fi
}

# ==================== 启动/停止 ====================

start_sillytavern() {
    if ! check_installed; then
        error "都还没装呢...杂鱼先去装好再来♡"
        return 1
    fi

    if is_running; then
        warn "已经在跑了啦~ 杂鱼别重复操作♡"
        show_access_info
        return 0
    fi

    echo ""
    echo -e "  ${GREEN}1)${NC} 后台运行 ${DIM}(PM2，推荐~)${NC}"
    echo -e "  ${GREEN}2)${NC} 前台运行 ${DIM}(Ctrl+C 停止)${NC}"
    echo ""
    local mode
    mode=$(read_input "选择启动方式" "1")

    case "$mode" in
        1)
            step "PM2 后台启动中..."
            pm2_start
            ;;
        2)
            local port
            port=$(get_port)
            step "前台启动 SillyTavern"
            info "按 Ctrl+C 可以停掉哦~ 杂鱼记住了吗♡"
            show_access_info
            echo ""
            cd "$INSTALL_DIR"
            node server.js
            cd - >/dev/null
            ;;
        *)
            warn "选项都选不对吗...杂鱼♡"
            ;;
    esac
}

stop_sillytavern() {
    if ! is_running; then
        info "本来就没在跑啊...杂鱼紧张什么♡"
        return 0
    fi
    step "停止 SillyTavern"
    pm2_stop
}

restart_sillytavern() {
    if ! check_installed; then
        error "都没装呢！杂鱼先装好再说♡"
        return 1
    fi
    step "重启 SillyTavern...稍等一下♡"
    pm2_stop
    sleep 1
    pm2_start
}

# ==================== 状态显示 ====================

show_status() {
    if ! check_installed; then
        error "SillyTavern 还没装呢...杂鱼先去装好♡"
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
        status_text="运行中"
        status_color="$GREEN"
    else
        status_text="已停止"
        status_color="$RED"
    fi

    echo -e "  ${BOLD}基本信息${NC} ${DIM}(人家帮你看了一眼♡)${NC}"
    divider
    echo -e "    版本       ${CYAN}${version:-未知}${NC}"
    echo -e "    分支       ${CYAN}${branch:-未知}${NC}"
    echo -e "    目录       ${DIM}${INSTALL_DIR}${NC}"
    echo -e "    状态       ${status_color}● ${status_text}${NC}"

    if is_pm2_managed; then
        echo -e "    进程管理   ${GREEN}PM2${NC}"
    else
        echo -e "    进程管理   ${DIM}未配置${NC}"
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

        echo -e "  ${BOLD}当前配置${NC}"
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
    local total_steps=5
    local current_step=0

    if is_running; then
        warn "酒馆还在跑呢，人家先帮你停掉♡"
        pm2_stop
    fi

    cd "$INSTALL_DIR"

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "备份配置..."
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "备份到: $backup_dir"

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "拉取最新代码..."

    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    spin_start "拉取最新代码"
    if ! git pull --ff-only >> "$INSTALL_LOG" 2>&1; then
        spin_stop
        warn "快速合并不行呢...强制更新♡"
        local current_branch
        current_branch=$(git branch --show-current)
        spin_start "强制更新中"
        git fetch --all >> "$INSTALL_LOG" 2>&1
        git reset --hard "origin/$current_branch" >> "$INSTALL_LOG" 2>&1
        spin_stop
    else
        spin_stop
    fi

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "规范化文件..."
    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "更新 npm 依赖..."
    spin_start "更新 npm 依赖"
    npm install --no-audit --no-fund >> "$INSTALL_LOG" 2>&1
    spin_stop
    info "依赖更新完成 ✓"

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "恢复配置..."
    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        info "配置已恢复♡"
    fi

    cd - >/dev/null

    save_script 2>/dev/null && info "管理脚本也更新了~"

    echo ""
    success "SillyTavern 更新完成！才不是特意帮你弄的呢♡"

    echo ""
    if confirm "现在就启动?"; then
        pm2_start
    fi
}

handle_update() {
    if ! check_installed; then
        error "都没装呢...杂鱼先去安装♡"
        return
    fi

    detect_network

    step "检查更新...帮杂鱼看看有没有新版本♡"

    local current_ver=""
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        current_ver=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')

    local branch=""
    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)

    echo ""
    echo -e "    当前版本: ${CYAN}${current_ver:-未知}${NC}"
    echo -e "    当前分支: ${CYAN}${branch:-未知}${NC}"

    echo ""
    spin_start "连接远程仓库"
    local has_update=false
    if check_for_updates; then
        has_update=true
    fi
    spin_stop

    if [[ "$has_update" == true ]]; then
        echo ""
        warn "有 ${UPDATE_BEHIND} 个新提交呢~ 杂鱼该更新了♡"
        echo ""
        if confirm "更新 SillyTavern?"; then
            do_update
        else
            info "不更新啊...随你吧杂鱼♡"
        fi
    else
        echo ""
        success "已经是最新版了~ 没什么好更新的♡"
    fi
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "都没装过...杂鱼卸什么呢♡"
        return 1
    fi

    echo ""
    warn "要卸载 SillyTavern 了哦...真的舍得吗杂鱼♡"
    echo -e "    安装目录: ${DIM}${INSTALL_DIR}${NC}"
    echo ""
    confirm "确定卸载？删了就没了！" || { info "哼，就知道你舍不得♡"; return 0; }
    echo ""
    confirm "再确认一次...真的删？" || { info "犹豫就对了♡"; return 0; }

    local total_steps=4
    local current_step=0

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "停止进程..."
    pm2_stop
    pm2_remove

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "清理防火墙..."
    local port
    port=$(get_port)
    remove_firewall_port "$port"

    # 移除旧版 systemd
    if [[ "$IS_TERMUX" != true ]] && command_exists systemctl; then
        if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            get_sudo
            $NEED_SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
        fi
    fi

    rm -f "$HOME/.termux/boot/sillytavern.sh" 2>/dev/null

    # 备份数据
    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm "要不要把聊天记录和角色卡备份一下？"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            cp -r "$INSTALL_DIR/data" "$backup_path/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$backup_path/"
            success "备份好了: $backup_path ...人家还是挺贴心的吧♡"
        fi
    fi

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "删除文件..."
    rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"

    current_step=$((current_step + 1))
    show_progress $current_step $total_steps "清理完成"
    success "SillyTavern 卸载完了...再见了♡"

    echo ""
    if confirm "顺便把 Node.js 也卸了?"; then
        if [[ "$IS_TERMUX" == true ]]; then
            run_silent "卸载 Node.js" pkg uninstall -y nodejs
        else
            get_sudo
            case "$PKG_MANAGER" in
                apt)    run_silent "卸载 Node.js" $NEED_SUDO apt-get remove -y nodejs; $NEED_SUDO rm -f /etc/apt/sources.list.d/nodesource.list ;;
                yum)    run_silent "卸载 Node.js" $NEED_SUDO yum remove -y nodejs ;;
                dnf)    run_silent "卸载 Node.js" $NEED_SUDO dnf remove -y nodejs ;;
                pacman) run_silent "卸载 Node.js" $NEED_SUDO pacman -R --noconfirm nodejs npm ;;
            esac
        fi
        info "Node.js 也清理掉了~"
    fi
}

# ==================== 配置修改菜单 ====================

modify_config_menu() {
    if ! check_installed; then
        error "SillyTavern 都没装呢...改什么配置啊杂鱼♡"
        return 1
    fi

    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件都没有...怎么搞的"
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

        echo -e "  ${BOLD}当前配置${NC} ${DIM}(人家帮你列出来了♡)${NC}"
        divider
        echo -e "    监听模式       $(format_bool "$listen_val")"
        echo -e "    端口           ${CYAN}${port_val}${NC}"
        echo -e "    白名单模式     $(format_bool "$whitelist_val")"
        echo -e "    基础认证       $(format_bool "$auth_val")"
        echo -e "    用户账户系统   $(format_bool "${user_acc:-false}")"
        echo -e "    隐蔽登录       $(format_bool "${discreet:-false}")"
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 修改监听设置"
        echo -e "  ${GREEN}2)${NC} 修改端口"
        echo -e "  ${GREEN}3)${NC} 修改白名单模式"
        echo -e "  ${GREEN}4)${NC} 修改基础认证"
        echo -e "  ${GREEN}5)${NC} 修改用户账户系统  ${DIM}(enableUserAccounts)${NC}"
        echo -e "  ${GREEN}6)${NC} 修改隐蔽登录      ${DIM}(enableDiscreetLogin)${NC}"
        echo -e "  ${GREEN}7)${NC} 编辑完整配置文件  ${DIM}(给高手用的♡)${NC}"
        echo -e "  ${GREEN}8)${NC} 重置为默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行管理"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "想改哪个？杂鱼♡")

        case "$choice" in
            1)
                echo ""
                echo -e "  当前状态: 监听 $(format_bool "$listen_val")"
                if confirm "开启监听?"; then
                    set_yaml_val "listen" "true" "$config_file"
                    success "监听开了♡"
                    open_firewall_port "$(get_port)"
                else
                    set_yaml_val "listen" "false" "$config_file"
                    info "关了~"
                fi
                ;;
            2)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                local new_port
                new_port=$(read_input "新端口号" "$port_val")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    success "端口改成 $new_port 了♡"
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    [[ "$cur_listen" == "true" ]] && open_firewall_port "$new_port"
                else
                    error "这什么端口号: $new_port ...杂鱼认真的吗♡"
                fi
                ;;
            3)
                echo ""
                echo -e "  当前状态: 白名单 $(format_bool "$whitelist_val")"
                if confirm "关闭白名单模式?"; then
                    set_yaml_val "whitelistMode" "false" "$config_file"
                    success "白名单关了~"
                else
                    set_yaml_val "whitelistMode" "true" "$config_file"
                    info "白名单留着♡"
                fi
                ;;
            4)
                echo ""
                echo -e "  当前状态: 基础认证 $(format_bool "$auth_val")"
                if confirm "开启基础认证?"; then
                    set_yaml_val "basicAuthMode" "true" "$config_file"
                    echo ""
                    local auth_user=""
                    while [[ -z "$auth_user" ]]; do
                        auth_user=$(read_input "认证用户名")
                        [[ -z "$auth_user" ]] && warn "空的？杂鱼认真点！"
                    done
                    local auth_pass
                    auth_pass=$(read_password "认证密码")
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
                    success "认证设好了♡ 用户: $auth_user"
                else
                    set_yaml_val "basicAuthMode" "false" "$config_file"
                    info "认证关了...裸奔可别怪人家♡"
                fi
                ;;
            5)
                echo ""
                echo -e "  当前状态: 用户账户系统 $(format_bool "${user_acc:-false}")"
                echo -e "  ${DIM}开了以后可以建多个用户，各自的数据独立♡${NC}"
                echo ""
                if confirm "开启用户账户系统?"; then
                    set_yaml_val "enableUserAccounts" "true" "$config_file"
                    success "用户账户系统开了♡"
                else
                    set_yaml_val "enableUserAccounts" "false" "$config_file"
                    info "关了~"
                fi
                ;;
            6)
                echo ""
                echo -e "  当前状态: 隐蔽登录 $(format_bool "${discreet:-false}")"
                echo -e "  ${DIM}开了就不显示头像和用户名，偷偷登录♡${NC}"
                echo ""
                if confirm "开启隐蔽登录?"; then
                    set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                    success "隐蔽登录开了♡ 偷偷摸摸的呢~"
                else
                    set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                    info "关了~"
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            8)
                if confirm "重置为默认配置？之前的设置全没了哦"; then
                    if [[ -f "$INSTALL_DIR/default.yaml" ]]; then
                        cp "$INSTALL_DIR/default.yaml" "$config_file"
                        sed -i 's/\r$//' "$config_file"
                        success "重置好了~ 从头来过吧杂鱼♡"
                    else
                        error "default.yaml 都没了...没法重置"
                    fi
                fi
                ;;
            9)
                open_firewall_port "$(get_port)"
                ;;
            0)
                return 0
                ;;
            *)
                warn "选项都选不对吗...杂鱼♡"
                ;;
        esac

        if [[ "$choice" =~ ^[1-6]$ ]] && is_running; then
            echo ""
            warn "改了配置要重启才生效哦~"
            if confirm "现在重启 SillyTavern?"; then
                restart_sillytavern
            fi
        fi

        pause_key
    done
}

# ==================== PM2 管理菜单 ====================

pm2_menu() {
    if ! check_installed; then
        error "SillyTavern 都没装呢♡"
        return 1
    fi

    while true; do
        print_banner

        echo -e "  ${BOLD}PM2 后台运行状态${NC} ${DIM}(人家帮你看♡)${NC}"
        divider

        if command_exists pm2; then
            echo -e "    PM2        ${GREEN}已安装${NC} ($(pm2 -v 2>/dev/null))"
        else
            echo -e "    PM2        ${DIM}未安装${NC}"
        fi

        if is_pm2_managed; then
            if is_pm2_online; then
                echo -e "    进程状态   ${GREEN}● 运行中${NC}"
            else
                echo -e "    进程状态   ${RED}● 已停止${NC}"
            fi
        else
            echo -e "    进程状态   ${DIM}未托管${NC}"
        fi

        if [[ "$IS_TERMUX" == true ]]; then
            if [[ -f "$HOME/.termux/boot/sillytavern.sh" ]]; then
                echo -e "    开机自启   ${GREEN}● 已配置${NC}"
            else
                echo -e "    开机自启   ${DIM}未配置${NC}"
            fi
        fi

        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 安装/更新 PM2"
        echo -e "  ${GREEN}2)${NC} 启动 (PM2 后台)"
        echo -e "  ${GREEN}3)${NC} 停止"
        echo -e "  ${GREEN}4)${NC} 重启"
        echo -e "  ${GREEN}5)${NC} 查看日志"
        echo -e "  ${GREEN}6)${NC} 设置开机自启"
        echo -e "  ${GREEN}7)${NC} 移除开机自启"
        echo -e "  ${GREEN}8)${NC} 从 PM2 中移除进程"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "选吧杂鱼♡")

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
                    log_choice=$(read_input "选择" "1")
                    case "$log_choice" in
                        1) echo ""; pm2 logs "$SERVICE_NAME" --lines 50 --nostream 2>/dev/null ;;
                        2) pm2 logs "$SERVICE_NAME" 2>/dev/null ;;
                        3) pm2 flush "$SERVICE_NAME" >> "$INSTALL_LOG" 2>/dev/null; success "日志清了♡" ;;
                    esac
                else
                    warn "SillyTavern 还没注册到 PM2 呢"
                fi
                ;;
            6) pm2_setup_autostart ;;
            7) pm2_remove_autostart ;;
            8)
                if confirm "从 PM2 移除 SillyTavern?"; then
                    pm2_stop
                    pm2_remove
                    success "移除了♡"
                fi
                ;;
            0) return 0 ;;
            *) warn "无效选项...杂鱼♡" ;;
        esac

        pause_key
    done
}

# ==================== 完整安装流程 ====================

full_install() {
    print_banner

    echo -e "  ${BOLD}${PINK}♡ 开始安装 SillyTavern ♡${NC}"
    echo -e "  ${DIM}既然杂鱼求人家了...就勉为其难帮你装吧~${NC}"
    divider

    # 清空安装日志
    > "$INSTALL_LOG"

    detect_os
    detect_network
    install_dependencies

    echo ""
    clone_sillytavern
    configure_sillytavern
    setup_background

    save_config

    step "保存管理脚本"
    spin_start "下载最新管理脚本"
    local save_result=true
    save_script || save_result=false
    spin_stop
    if [[ "$save_result" == true ]]; then
        success "脚本保存到: ${INSTALL_DIR}/ksilly.sh"
        info "以后直接跑: ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC} ...记住了吗杂鱼♡"
    else
        warn "脚本保存失败了...不过不影响使用啦"
    fi

    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${PINK}🎉 SillyTavern 安装完成！${NC}"
    echo -e "  ${DIM}全部搞定了哦~ 夸夸人家吧杂鱼♡${NC}"
    echo ""
    info "安装目录: $INSTALL_DIR"
    show_access_info
    echo ""
    divider
    echo ""

    # 清理安装日志
    rm -f "$INSTALL_LOG"

    if confirm "现在就启动 SillyTavern?"; then
        start_sillytavern
    else
        echo ""
        info "后面想启动就跑:"
        echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
        echo -e "    ${DIM}或者 ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
        echo -e "    ${DIM}别说人家没教你哦♡${NC}"
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

            [[ ! -f "$INSTALL_DIR/ksilly.sh" ]] && save_script 2>/dev/null
        else
            echo -e "  ${YELLOW}●${NC} SillyTavern 还没装呢~ ${DIM}杂鱼快去安装♡${NC}"
        fi

        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "    ${GREEN}1)${NC} 安装 SillyTavern     ${DIM}← 杂鱼从这里开始♡${NC}"
        echo -e "    ${GREEN}2)${NC} 更新 SillyTavern"
        echo -e "    ${GREEN}3)${NC} 卸载 SillyTavern"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "    ${GREEN}4)${NC} 启动"
        echo -e "    ${GREEN}5)${NC} 停止"
        echo -e "    ${GREEN}6)${NC} 重启"
        echo -e "    ${GREEN}7)${NC} 查看状态"
        echo ""
        echo -e "  ${BOLD}配置与维护${NC}"
        echo -e "    ${GREEN}8)${NC} 修改配置"
        echo -e "    ${GREEN}9)${NC} 后台运行管理 (PM2)"
        echo ""
        echo -e "    ${RED}0)${NC} 退出 ${DIM}← 舍得走吗♡${NC}"
        echo ""
        divider

        local choice
        choice=$(read_input "选一个吧杂鱼~")

        case "$choice" in
            1)
                if check_installed; then
                    warn "已经装过了哦~ $INSTALL_DIR"
                    confirm "还要重装？杂鱼真是折腾♡" || continue
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
            0)
                echo ""
                info "走了啊~ 下次再来找人家吧♡ 杂鱼再见~"
                echo ""
                rm -f "$INSTALL_LOG"
                exit 0
                ;;
            *)
                warn "连数字都选不对吗...杂鱼♡"
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
                error "只支持 Linux / macOS / Termux 哦~ 杂鱼用的什么系统啊♡"
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
        "")        main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|uninstall}"
            echo "  不带参数进入交互式菜单...连这都不会吗杂鱼♡"
            exit 1
            ;;
    esac
}

main "$@"
