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
LOG_FILE="/tmp/ksilly_install.log"
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
PINK='\033[38;5;206m'
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
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0

# ==================== 信号处理 ====================
trap 'echo ""; warn "哈？杂鱼要跑路了吗～♡"; exit 130' INT

# ==================== 日志管理 ====================

init_log() {
    echo "=== Ksilly 安装日志 $(date) ===" > "$LOG_FILE"
}

log_cmd() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>&1
}

# 静默运行命令，输出重定向到日志
run_silent() {
    local desc="$1"
    shift
    log_cmd "执行: $*"
    if "$@" >> "$LOG_FILE" 2>&1; then
        log_cmd "成功: $desc"
        return 0
    else
        log_cmd "失败: $desc"
        return 1
    fi
}

# ==================== 进度条函数 ====================

# 带动画的spinner
spin() {
    local pid=$1
    local msg="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    tput civis 2>/dev/null  # 隐藏光标
    while kill -0 "$pid" 2>/dev/null; do
        local c=${spinstr:i++%${#spinstr}:1}
        printf "\r  ${PINK}%s${NC} %s" "$c" "$msg" >&2
        sleep 0.1
    done
    tput cnorm 2>/dev/null  # 恢复光标
    printf "\r\033[K" >&2
}

# 显示进度条
# 用法: show_progress 当前值 总值 "描述"
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local width=30
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf "\r  ${PINK}▸${NC} %-20s ${CYAN}[%s]${NC} ${BOLD}%3d%%${NC}" "$desc" "$bar" "$percent" >&2

    if [[ $current -eq $total ]]; then
        echo "" >&2
    fi
}

# 整体安装进度管理
set_total_steps() {
    PROGRESS_TOTAL=$1
    PROGRESS_CURRENT=0
}

advance_progress() {
    local desc="$1"
    PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
    show_progress $PROGRESS_CURRENT $PROGRESS_TOTAL "$desc"
}

# 运行命令并显示spinner动画
run_with_spinner() {
    local msg="$1"
    shift
    (
        "$@" >> "$LOG_FILE" 2>&1
    ) &
    local cmd_pid=$!
    spin $cmd_pid "$msg"
    wait $cmd_pid
    return $?
}

# 运行命令并显示模拟进度条
run_with_progress() {
    local msg="$1"
    shift

    # 在后台运行实际命令
    (
        "$@" >> "$LOG_FILE" 2>&1
    ) &
    local cmd_pid=$!

    # 模拟进度（无法知道真实进度时使用）
    local progress=0
    local max_fake=90
    tput civis 2>/dev/null
    while kill -0 "$cmd_pid" 2>/dev/null; do
        if [[ $progress -lt $max_fake ]]; then
            progress=$((progress + 1))
            # 越接近90越慢
            local delay
            if [[ $progress -lt 30 ]]; then
                delay=0.1
            elif [[ $progress -lt 60 ]]; then
                delay=0.15
            elif [[ $progress -lt 80 ]]; then
                delay=0.25
            else
                delay=0.5
            fi
            show_progress $progress 100 "$msg"
            sleep $delay
        else
            sleep 0.2
        fi
    done

    wait $cmd_pid
    local exit_code=$?
    show_progress 100 100 "$msg"
    tput cnorm 2>/dev/null
    return $exit_code
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
    echo -e "  ${PINK}♡${NC} ${DIM}本小姐亲自为杂鱼服务呢～${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
ask()     { echo -e "  ${PINK}♡${NC} $1"; }
success() { echo -e "  ${GREEN}★${NC} $1"; }

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
            *) warn "y 或 n 都分不清吗，杂鱼～♡" ;;
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
    echo -e "  ${YELLOW}⚠ 输入密码时屏幕不会显示字符哦，不是坏了，杂鱼别慌～♡${NC}" >&2
    while [[ -z "$result" ]]; do
        echo -ne "  ${PINK}→${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "密码都能输空？真是杂鱼呢～再来一次♡"
        fi
    done
    echo "$result"
}

pause_key() {
    echo ""
    read -rp "  按 Enter 继续...杂鱼♡"
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
        error "需要 root 权限但没有 sudo...杂鱼连权限都没有吗～♡"
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
    echo -e "  ${BOLD}访问地址 (本小姐帮你查好了哦～♡):${NC}"
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
            echo -e "    公网访问   → ${YELLOW}获取不到公网IP呢，杂鱼自己查一下吧～${NC}"
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
    step "本小姐来看看杂鱼用的什么环境～♡"

    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        IS_TERMUX=true
        OS_TYPE="termux"
        PKG_MANAGER="pkg"
        NEED_SUDO=""
        info "原来是手机上的 Termux 啊，杂鱼还挺会玩的嘛～♡"
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
            info "Debian/Ubuntu ($OS_TYPE) 嘛，杂鱼品味还行～♡"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "RHEL/CentOS ($OS_TYPE)，杂鱼用企业级系统呢～♡"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "Arch ($OS_TYPE)！杂鱼是 Arch 用户吗，有点东西哦～♡"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "Alpine 呢，杂鱼喜欢轻量级的嘛～♡"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "macOS 啊，有钱的杂鱼呢～♡"
            ;;
        *)
            warn "这什么系统啊...本小姐都不认识，杂鱼用的什么奇怪东西～"
            PKG_MANAGER="unknown"
            ;;
    esac
}

detect_network() {
    step "检测一下杂鱼的网络环境～♡"

    local china_test=false

    if run_with_spinner "探测网络中..." curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com"; then
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
        info "在国内呢～本小姐帮杂鱼开加速镜像吧♡"
        find_github_proxy
    else
        IS_CHINA=false
        info "国际网络，杂鱼可以直连 GitHub 呢～♡"
    fi
}

find_github_proxy() {
    run_with_spinner "帮杂鱼找个能用的代理..." sleep 0.5
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            info "找到啦～用这个代理: ${proxy} ♡"
            return 0
        fi
    done
    warn "代理都不行呢...只能直连试试了，杂鱼祈祷吧～♡"
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
    run_with_spinner "更新软件包索引..." \
    bash -c "
        case '$PKG_MANAGER' in
            pkg)    pkg update -y ;;
            apt)    $NEED_SUDO apt-get update -qq ;;
            yum)    $NEED_SUDO yum makecache -q ;;
            dnf)    $NEED_SUDO dnf makecache -q ;;
            pacman) $NEED_SUDO pacman -Sy --noconfirm ;;
            apk)    $NEED_SUDO apk update ;;
            brew)   brew update ;;
        esac
    " 2>/dev/null
}

install_git() {
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') 已经有了呢～♡"
        return 0
    fi

    if run_with_progress "安装 Git" \
        bash -c "
            case '$PKG_MANAGER' in
                pkg)    pkg install -y git ;;
                apt)    $NEED_SUDO apt-get install -y -qq git ;;
                yum)    $NEED_SUDO yum install -y -q git ;;
                dnf)    $NEED_SUDO dnf install -y -q git ;;
                pacman) $NEED_SUDO pacman -S --noconfirm git ;;
                apk)    $NEED_SUDO apk add git ;;
                brew)   brew install git ;;
                *)      exit 1 ;;
            esac
        "; then
        command_exists git && info "Git 装好了哦，杂鱼～♡" || { error "Git 装不上...杂鱼的环境有问题吧～"; return 1; }
    else
        error "Git 安装失败了呢，杂鱼检查一下环境吧～"
        return 1
    fi
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ -n "$ver" && "$ver" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) 已经有了呢～♡"
        return 0
    fi

    command_exists node && warn "Node.js $(node -v) 版本太低了，杂鱼用的什么老古董～需要 v${MIN_NODE_VERSION}+ 哦♡"

    step "帮杂鱼安装 Node.js～♡"

    if [[ "$IS_TERMUX" == true ]]; then
        install_nodejs_termux
    elif [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi

    hash -r 2>/dev/null || true

    if check_node_version; then
        info "Node.js $(node -v) 安装好了～杂鱼感谢本小姐吧♡"
    else
        error "Node.js 装不上呢...杂鱼查看日志: $LOG_FILE"
        return 1
    fi

    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null
        info "npm 镜像设好了: npmmirror ♡"
    fi
}

install_nodejs_termux() {
    run_with_progress "安装 Node.js (Termux)" \
        bash -c "pkg install -y nodejs 2>/dev/null || pkg install -y nodejs-lts 2>/dev/null"
}

install_nodejs_standard() {
    run_with_progress "安装 Node.js" \
        bash -c "
            case '$PKG_MANAGER' in
                apt)
                    $NEED_SUDO apt-get install -y -qq ca-certificates curl gnupg
                    $NEED_SUDO mkdir -p /etc/apt/keyrings
                    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                        | $NEED_SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
                    echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' \
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
                *)      exit 1 ;;
            esac
        "
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
        *) error "这 CPU 架构本小姐不认识: $(uname -m)，杂鱼用的什么奇怪机器～"; return 1 ;;
    esac

    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if run_with_progress "下载 Node.js ${node_ver}" \
        curl -fSL -o "${tmp_dir}/${filename}" "${mirror}/${node_ver}/${filename}"; then

        run_with_spinner "解压安装中..." bash -c "
            cd '$tmp_dir'
            tar xf '$filename'
            $NEED_SUDO cp -rf 'node-${node_ver}-linux-${arch}'/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
            $NEED_SUDO cp -rf 'node-${node_ver}-linux-${arch}'/{bin,include,lib} /usr/local/
        "
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
    else
        rm -rf "$tmp_dir"
        error "Node.js 下载失败了呢...杂鱼的网络不行吗～♡"
        return 1
    fi
}

install_dependencies() {
    step "帮杂鱼安装系统依赖～♡"

    [[ "$IS_TERMUX" != true ]] && get_sudo
    update_pkg_cache

    if [[ "$IS_TERMUX" == true ]]; then
        run_with_progress "安装基础工具" pkg install -y curl git
    else
        run_with_progress "安装基础工具" \
            bash -c "
                case '$PKG_MANAGER' in
                    apt)    $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils ;;
                    yum)    $NEED_SUDO yum install -y -q curl wget tar xz ;;
                    dnf)    $NEED_SUDO dnf install -y -q curl wget tar xz ;;
                    pacman) $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz ;;
                    apk)    $NEED_SUDO apk add curl wget tar xz ;;
                    brew)   : ;;
                esac
            "
    fi

    install_git
    install_nodejs
}

# ==================== PM2 管理 ====================

install_pm2() {
    if command_exists pm2; then
        info "PM2 $(pm2 -v 2>/dev/null) 已经装好了呢～♡"
        return 0
    fi
    if run_with_spinner "安装 PM2..." npm install -g pm2; then
        if command_exists pm2; then
            info "PM2 安装好了～♡"
            return 0
        fi
    fi
    warn "PM2 全局安装失败了，用 npx 方式吧，杂鱼～♡"
    return 1
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
    install_pm2 || { error "PM2 用不了呢，杂鱼～♡"; return 1; }

    cd "$INSTALL_DIR"
    if is_pm2_managed; then
        run_silent "PM2 重启" pm2 restart "$SERVICE_NAME"
    else
        run_silent "PM2 启动" pm2 start server.js --name "$SERVICE_NAME"
    fi
    pm2 save 2>/dev/null
    cd - >/dev/null

    sleep 2
    if is_pm2_online; then
        success "SillyTavern 已经在后台跑起来了～杂鱼快去玩吧♡"
        show_access_info
        return 0
    else
        error "启动失败了呢...杂鱼用 'pm2 logs $SERVICE_NAME' 看看出了什么问题吧～♡"
        return 1
    fi
}

pm2_stop() {
    if is_pm2_online; then
        run_silent "停止服务" pm2 stop "$SERVICE_NAME"
        pm2 save 2>/dev/null
        info "SillyTavern 停下来了～杂鱼不玩了吗♡"
    elif command_exists pgrep; then
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            info "进程已经停掉了～♡"
        else
            info "本来就没在跑嘛，杂鱼在干什么呢～♡"
        fi
    else
        info "本来就没在跑嘛，杂鱼在干什么呢～♡"
    fi
}

pm2_remove() {
    if is_pm2_managed; then
        pm2 delete "$SERVICE_NAME" 2>/dev/null
        pm2 save 2>/dev/null
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
        pm2 save 2>/dev/null
        success "Termux 开机自启设好了～杂鱼记得装 Termux:Boot 哦♡"
        warn "需要安装 Termux:Boot 应用才能生效哦～"
    else
        echo ""
        info "生成自启动配置中..."
        local startup_cmd
        startup_cmd=$(pm2 startup 2>&1 | grep -E "sudo|env" | head -1 || true)
        if [[ -n "$startup_cmd" ]]; then
            info "杂鱼，把下面这行命令复制去执行一下～♡"
            echo ""
            echo -e "    ${CYAN}${startup_cmd}${NC}"
            echo ""
            info "执行完再跑一下: ${CYAN}pm2 save${NC}"
        else
            get_sudo
            run_silent "设置自启动" pm2 startup
            pm2 save 2>/dev/null
            info "自启动应该配好了～♡"
        fi
    fi
}

pm2_remove_autostart() {
    if [[ "$IS_TERMUX" == true ]]; then
        rm -f "$HOME/.termux/boot/sillytavern.sh"
        info "Termux 开机自启移除了～♡"
    else
        pm2 unstartup 2>/dev/null || true
        info "PM2 自启动移除了～♡"
    fi
}

migrate_from_systemd() {
    [[ "$IS_TERMUX" == true ]] && return
    command_exists systemctl || return

    if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        warn "发现旧版 systemd 服务呢～"
        info "新版本用 PM2 管理了，更好用哦♡"
        if confirm "移除旧版 systemd 服务？杂鱼～"; then
            get_sudo
            run_silent "移除旧服务" bash -c "
                $NEED_SUDO systemctl stop '$SERVICE_NAME' 2>/dev/null || true
                $NEED_SUDO systemctl disable '$SERVICE_NAME' 2>/dev/null || true
                $NEED_SUDO rm -f '/etc/systemd/system/${SERVICE_NAME}.service'
                $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
            "
            success "旧版服务清理干净了～♡"
        fi
    fi
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"

    if [[ "$IS_TERMUX" == true ]]; then
        info "Termux 不需要管防火墙的啦，杂鱼～♡"
        return
    fi

    get_sudo || return

    step "帮杂鱼检查防火墙～♡"
    local firewall_found=false

    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW: 端口 $port 已经放行了呢～♡"
            else
                run_silent "UFW放行" $NEED_SUDO ufw allow "$port/tcp"
                success "UFW: 端口 $port/tcp 放行了～♡"
            fi
        fi
    fi

    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 $port 已经放行了～♡"
            else
                run_silent "firewalld放行" bash -c "
                    $NEED_SUDO firewall-cmd --permanent --add-port='${port}/tcp'
                    $NEED_SUDO firewall-cmd --reload
                "
                success "firewalld: 端口 $port/tcp 放行了～♡"
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
                success "iptables: 端口 $port/tcp 放行了～♡"
            else
                info "iptables: 端口 $port 已经放行了呢～♡"
            fi
        fi
    fi

    [[ "$firewall_found" == false ]] && info "没检测到防火墙呢～♡"

    echo ""
    warn "用云服务器的杂鱼记得去安全组也放行端口 ${port}/tcp 哦～♡"
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
    step "帮杂鱼拉取 SillyTavern 代码～♡"

    INSTALL_DIR=$(read_input "安装到哪里呢，杂鱼" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "这里已经装过 SillyTavern 了呢～"
            if confirm "删掉重装？杂鱼想好了吗"; then
                rm -rf "$INSTALL_DIR"
            else
                info "那就保留吧～♡"
                return 0
            fi
        else
            error "这个目录里有别的东西: $INSTALL_DIR，杂鱼换个位置吧～"
            return 1
        fi
    fi

    echo ""
    ask "杂鱼想装哪个版本呢～♡"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}稳定版 (本小姐推荐这个♡)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}开发版 (杂鱼想尝鲜的话～)${NC}"
    echo ""

    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "选哪个" "1")
    done

    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"
    info "好的，选 $branch 分支～♡"

    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")

    if run_with_progress "克隆仓库" \
        git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR"; then
        success "代码拉下来了～♡"
    else
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理不行呢，本小姐试试直连..."
            if run_with_progress "直连克隆" \
                git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR"; then
                success "直连成功了呢～♡"
            else
                error "克隆失败了...杂鱼检查一下网络吧～♡"
                return 1
            fi
        else
            error "克隆失败了...杂鱼的网络有问题吧～♡"
            return 1
        fi
    fi

    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖～♡"
    cd "$INSTALL_DIR"
    if run_with_progress "安装依赖包" npm install --no-audit --no-fund; then
        success "依赖全装好了～杂鱼什么都不用管♡"
    else
        error "npm 依赖安装失败了...杂鱼查看日志: $LOG_FILE"
        cd - >/dev/null
        return 1
    fi
    cd - >/dev/null

    save_config
}

configure_sillytavern() {
    step "帮杂鱼配置 SillyTavern～♡"

    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed -i 's/\r$//' "$config_file"
            info "配置文件生成了～♡"
        else
            error "default.yaml 都没有...杂鱼的文件怎么回事～"
            return 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}${PINK}♡ 配置向导 ♡${NC}"
    echo -e "  ${DIM}本小姐来一步步教杂鱼设置～${NC}"
    divider

    # --- 监听设置 ---
    echo ""
    echo -e "  ${BOLD}1. 监听模式${NC}"
    echo -e "     ${DIM}开启 → 别的设备也能访问 (局域网/外网)${NC}"
    echo -e "     ${DIM}关闭 → 只有本机能用${NC}"
    echo ""

    local listen_enabled=false
    if confirm "开启监听吗，杂鱼～♡"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        success "监听开启了～别的设备也能访问哦♡"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "好吧，就杂鱼自己用～♡"
    fi

    # --- 端口 ---
    echo ""
    echo -e "  ${BOLD}2. 端口设置${NC}"
    local port
    port=$(read_input "要用哪个端口呢，杂鱼" "8000")
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        set_yaml_val "port" "$port" "$config_file"
        info "端口设成 $port 了～♡"
    else
        warn "这端口号不对吧...杂鱼，用默认的 8000 了哦～♡"
        port="8000"
    fi

    # --- 白名单 ---
    echo ""
    echo -e "  ${BOLD}3. 白名单模式${NC}"
    echo -e "     ${DIM}开启 → 只有白名单里的 IP 才能访问${NC}"
    echo -e "     ${DIM}远程访问的话建议关掉哦～${NC}"
    echo ""
    if confirm "关掉白名单？杂鱼～"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        success "白名单关了～♡"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "保持白名单开着也行～♡"
    fi

    # --- 基础认证 ---
    echo ""
    echo -e "  ${BOLD}4. 基础认证 (HTTP Auth)${NC}"
    echo -e "     ${DIM}访问的时候要输用户名密码～${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "     ${RED}杂鱼开了远程访问，不设密码很危险的哦！${NC}"
    fi
    echo ""
    if confirm "开启认证吗，杂鱼～♡"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        echo ""
        local auth_user=""
        while [[ -z "$auth_user" ]]; do
            auth_user=$(read_input "设个用户名吧，杂鱼")
            [[ -z "$auth_user" ]] && warn "空的？杂鱼认真点啦～♡"
        done

        local auth_pass
        auth_pass=$(read_password "再设个密码")

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

        success "认证开好了～用户名: $auth_user ♡"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "不设密码的话小心被别人进来哦，杂鱼～♡"
    fi

    # --- 防火墙 ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置全部搞定了～本小姐真厉害吧♡"
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
    echo -e "    ${DIM}关掉终端也能继续跑，还能自动重启呢～${NC}"
    echo -e "    ${DIM}杂鱼应该需要这个吧♡${NC}"
    echo ""

    if confirm "启用 PM2 后台运行？杂鱼～"; then
        install_pm2 || return 1
        success "PM2 准备好了～♡"

        echo ""
        if confirm "要不要顺便设开机自启？杂鱼～♡"; then
            pm2_setup_autostart
        fi
    fi
}

# ==================== 启动/停止 ====================

start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 都没装呢，杂鱼先去安装啊～♡"
        return 1
    fi

    if is_running; then
        warn "已经在跑了啦！杂鱼记性不好吗～♡"
        show_access_info
        return 0
    fi

    echo ""
    echo -e "  ${GREEN}1)${NC} 后台运行 ${DIM}(PM2，本小姐推荐♡)${NC}"
    echo -e "  ${GREEN}2)${NC} 前台运行 ${DIM}(Ctrl+C 停止)${NC}"
    echo ""
    local mode
    mode=$(read_input "选一个吧，杂鱼" "1")

    case "$mode" in
        1)
            step "用 PM2 后台启动～♡"
            pm2_start
            ;;
        2)
            local port
            port=$(get_port)
            step "前台启动 SillyTavern～♡"
            info "按 Ctrl+C 就能停下来哦，杂鱼～♡"
            show_access_info
            echo ""
            cd "$INSTALL_DIR"
            node server.js
            cd - >/dev/null
            ;;
        *)
            warn "选个 1 或 2 都不会吗，杂鱼～♡"
            ;;
    esac
}

stop_sillytavern() {
    if ! is_running; then
        info "本来就没在跑嘛～杂鱼在瞎操作什么♡"
        return 0
    fi
    step "停止 SillyTavern～♡"
    pm2_stop
}

restart_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 都没装，杂鱼重启个寂寞～♡"
        return 1
    fi
    step "重启 SillyTavern～♡"
    pm2_stop
    sleep 1
    pm2_start
}

# ==================== 状态显示 ====================

show_status() {
    if ! check_installed; then
        error "SillyTavern 还没装呢，杂鱼～♡"
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

    echo -e "  ${BOLD}杂鱼的 SillyTavern 状态～♡${NC}"
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

        echo -e "  ${BOLD}当前配置～♡${NC}"
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

    if ! run_with_spinner "连接远程仓库..." git fetch origin --quiet; then
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
        warn "还在跑呢，本小姐先帮杂鱼停掉～♡"
        pm2_stop
    fi

    cd "$INSTALL_DIR"

    run_with_spinner "备份配置中..." bash -c "
        backup_dir=\"\$HOME/.ksilly_backup_\$(date +%Y%m%d_%H%M%S)\"
        mkdir -p \"\$backup_dir\"
        [[ -f 'config.yaml' ]] && cp 'config.yaml' \"\$backup_dir/\"
        echo \"\$backup_dir\"
    "
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "备份在: $backup_dir ♡"

    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    if ! run_with_progress "拉取最新代码" git pull --ff-only; then
        warn "快速合并失败了，本小姐帮杂鱼强制更新～♡"
        local current_branch
        current_branch=$(git branch --show-current)
        run_with_progress "强制更新" bash -c "
            git fetch --all 2>/dev/null
            git reset --hard 'origin/$current_branch' 2>/dev/null
        "
    fi
    success "代码更新好了～♡"

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null

    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    run_with_progress "更新依赖包" npm install --no-audit --no-fund

    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        info "配置恢复了～♡"
    fi

    cd - >/dev/null

    save_script 2>/dev/null && info "管理脚本也更新了～♡"

    success "SillyTavern 更新完成！杂鱼满意吗～♡"

    echo ""
    if confirm "现在就启动吗，杂鱼～♡"; then
        pm2_start
    fi
}

handle_update() {
    if ! check_installed; then
        error "SillyTavern 都没装，更新什么呢杂鱼～♡"
        return
    fi

    detect_network

    step "帮杂鱼检查有没有更新～♡"

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

    if check_for_updates; then
        echo ""
        warn "有 ${UPDATE_BEHIND} 个新提交可以更新呢～♡"
        echo ""
        if confirm "更新吗，杂鱼～♡"; then
            do_update
        else
            info "不更新啊...杂鱼真是的～♡"
        fi
    else
        echo ""
        success "已经是最新版了～杂鱼不用担心♡"
    fi
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 都没装，卸什么载啊杂鱼～♡"
        return 1
    fi

    echo ""
    warn "杂鱼要把 SillyTavern 卸了吗...♡"
    echo -e "    安装目录: ${DIM}${INSTALL_DIR}${NC}"
    echo ""
    confirm "真的要卸载？不可恢复哦，杂鱼想好了吗～♡" || { info "算了就对了～♡"; return 0; }
    echo ""
    confirm "再确认一次...真的要删掉所有数据？杂鱼～♡" || { info "就说嘛～♡"; return 0; }

    pm2_stop
    pm2_remove

    local port
    port=$(get_port)
    remove_firewall_port "$port"

    if [[ "$IS_TERMUX" != true ]] && command_exists systemctl; then
        if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            get_sudo
            run_silent "清理systemd" bash -c "
                $NEED_SUDO systemctl stop '$SERVICE_NAME' 2>/dev/null || true
                $NEED_SUDO systemctl disable '$SERVICE_NAME' 2>/dev/null || true
                $NEED_SUDO rm -f '/etc/systemd/system/${SERVICE_NAME}.service'
                $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
            "
        fi
    fi

    rm -f "$HOME/.termux/boot/sillytavern.sh" 2>/dev/null

    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm "要备份聊天数据和角色卡吗？杂鱼总不会连数据都不要吧～♡"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            run_with_spinner "备份数据中..." bash -c "
                cp -r '$INSTALL_DIR/data' '$backup_path/'
                [[ -f '$INSTALL_DIR/config.yaml' ]] && cp '$INSTALL_DIR/config.yaml' '$backup_path/'
            "
            success "数据备份到了: $backup_path ♡"
        fi
    fi

    run_with_spinner "删除安装目录..." rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "SillyTavern 卸载完了...杂鱼再见♡"

    echo ""
    if confirm "顺便把 Node.js 也卸了？杂鱼～♡"; then
        if [[ "$IS_TERMUX" == true ]]; then
            run_with_spinner "卸载 Node.js..." pkg uninstall -y nodejs
        else
            get_sudo
            run_with_spinner "卸载 Node.js..." bash -c "
                case '$PKG_MANAGER' in
                    apt)    $NEED_SUDO apt-get remove -y nodejs 2>/dev/null; $NEED_SUDO rm -f /etc/apt/sources.list.d/nodesource.list ;;
                    yum)    $NEED_SUDO yum remove -y nodejs 2>/dev/null ;;
                    dnf)    $NEED_SUDO dnf remove -y nodejs 2>/dev/null ;;
                    pacman) $NEED_SUDO pacman -R --noconfirm nodejs npm 2>/dev/null ;;
                esac
            "
        fi
        info "Node.js 也卸掉了～♡"
    fi
}

# ==================== 配置修改菜单 ====================

modify_config_menu() {
    if ! check_installed; then
        error "SillyTavern 都没装，配什么置啊杂鱼～♡"
        return 1
    fi

    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件不见了...杂鱼弄丢了吗～♡"
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

        echo -e "  ${BOLD}杂鱼的当前配置～♡${NC}"
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
        echo -e "  ${PINK}杂鱼想改哪个呢～♡${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} 修改监听设置"
        echo -e "  ${GREEN}2)${NC} 修改端口"
        echo -e "  ${GREEN}3)${NC} 修改白名单模式"
        echo -e "  ${GREEN}4)${NC} 修改基础认证"
        echo -e "  ${GREEN}5)${NC} 修改用户账户系统"
        echo -e "  ${GREEN}6)${NC} 修改隐蔽登录"
        echo -e "  ${GREEN}7)${NC} 编辑完整配置文件 ${DIM}(给高级杂鱼用的)${NC}"
        echo -e "  ${GREEN}8)${NC} 重置为默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行管理"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "选一个吧")

        case "$choice" in
            1)
                echo ""
                echo -e "  当前: 监听 $(format_bool "$listen_val")"
                if confirm "开启监听吗，杂鱼～♡"; then
                    set_yaml_val "listen" "true" "$config_file"
                    success "监听开了～♡"
                    open_firewall_port "$(get_port)"
                else
                    set_yaml_val "listen" "false" "$config_file"
                    info "关掉了～♡"
                fi
                ;;
            2)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                local new_port
                new_port=$(read_input "新端口号，杂鱼" "$port_val")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    success "端口改成 $new_port 了～♡"
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    [[ "$cur_listen" == "true" ]] && open_firewall_port "$new_port"
                else
                    error "这端口号不对吧...杂鱼连数字都输不好吗～♡"
                fi
                ;;
            3)
                echo ""
                echo -e "  当前: 白名单 $(format_bool "$whitelist_val")"
                if confirm "关掉白名单？杂鱼～♡"; then
                    set_yaml_val "whitelistMode" "false" "$config_file"
                    success "白名单关了～♡"
                else
                    set_yaml_val "whitelistMode" "true" "$config_file"
                    info "保持开着吧～♡"
                fi
                ;;
            4)
                echo ""
                echo -e "  当前: 基础认证 $(format_bool "$auth_val")"
                if confirm "开启认证？杂鱼～♡"; then
                    set_yaml_val "basicAuthMode" "true" "$config_file"
                    echo ""
                    local auth_user=""
                    while [[ -z "$auth_user" ]]; do
                        auth_user=$(read_input "用户名，杂鱼")
                        [[ -z "$auth_user" ]] && warn "空的啊...杂鱼认真点～♡"
                    done
                    local auth_pass
                    auth_pass=$(read_password "密码")
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
                    success "认证设好了～用户: $auth_user ♡"
                else
                    set_yaml_val "basicAuthMode" "false" "$config_file"
                    info "关了，杂鱼小心被人白嫖哦～♡"
                fi
                ;;
            5)
                echo ""
                echo -e "  当前: 用户账户系统 $(format_bool "${user_acc:-false}")"
                echo -e "  ${DIM}开了的话可以创建多个用户，各自有独立数据哦～♡${NC}"
                echo ""
                if confirm "开启用户账户系统？杂鱼～♡"; then
                    set_yaml_val "enableUserAccounts" "true" "$config_file"
                    success "用户系统开了～♡"
                else
                    set_yaml_val "enableUserAccounts" "false" "$config_file"
                    info "关了～♡"
                fi
                ;;
            6)
                echo ""
                echo -e "  当前: 隐蔽登录 $(format_bool "${discreet:-false}")"
                echo -e "  ${DIM}开了的话登录页不显示头像和用户名，更隐蔽哦～♡${NC}"
                echo ""
                if confirm "开启隐蔽登录？杂鱼～♡"; then
                    set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                    success "隐蔽登录开了～♡"
                else
                    set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                    info "关了～♡"
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            8)
                if confirm "要重置配置？杂鱼之前的设置都会没了哦～♡"; then
                    if [[ -f "$INSTALL_DIR/default.yaml" ]]; then
                        cp "$INSTALL_DIR/default.yaml" "$config_file"
                        sed -i 's/\r$//' "$config_file"
                        success "重置好了～♡"
                    else
                        error "default.yaml 不见了...杂鱼～"
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
                warn "没这个选项啦，杂鱼看清楚再选～♡"
                ;;
        esac

        if [[ "$choice" =~ ^[1-6]$ ]] && is_running; then
            echo ""
            warn "改了配置要重启才生效哦，杂鱼～♡"
            if confirm "现在重启？"; then
                restart_sillytavern
            fi
        fi

        pause_key
    done
}

# ==================== PM2 管理菜单 ====================

pm2_menu() {
    if ! check_installed; then
        error "SillyTavern 都没装呢，杂鱼～♡"
        return 1
    fi

    while true; do
        print_banner

        echo -e "  ${BOLD}${PINK}♡ PM2 后台管理 ♡${NC}"
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
        echo -e "  ${PINK}杂鱼想做什么呢～♡${NC}"
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
        choice=$(read_input "选一个吧，杂鱼")

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
                    log_choice=$(read_input "选一个，杂鱼" "1")
                    case "$log_choice" in
                        1) echo ""; pm2 logs "$SERVICE_NAME" --lines 50 --nostream 2>/dev/null ;;
                        2) pm2 logs "$SERVICE_NAME" 2>/dev/null ;;
                        3) pm2 flush "$SERVICE_NAME" 2>/dev/null; success "日志清空了～♡" ;;
                    esac
                else
                    warn "还没注册到 PM2 呢，杂鱼先启动一次吧～♡"
                fi
                ;;
            6) pm2_setup_autostart ;;
            7) pm2_remove_autostart ;;
            8)
                if confirm "从 PM2 里移除？杂鱼确定吗～♡"; then
                    pm2_stop
                    pm2_remove
                    success "移除了～♡"
                fi
                ;;
            0) return 0 ;;
            *) warn "没这个选项啦，杂鱼～♡" ;;
        esac

        pause_key
    done
}

# ==================== 完整安装流程 ====================

full_install() {
    print_banner
    init_log

    echo -e "  ${BOLD}${PINK}♡ 本小姐来帮杂鱼安装 SillyTavern 吧～♡${NC}"
    echo -e "  ${DIM}  没有本小姐，杂鱼肯定装不上的吧～${NC}"
    divider

    # 总体进度
    set_total_steps 6

    detect_os
    advance_progress "环境检测"

    detect_network
    advance_progress "网络检测"

    install_dependencies
    advance_progress "依赖安装"

    echo ""
    clone_sillytavern
    advance_progress "代码克隆"

    configure_sillytavern
    advance_progress "配置向导"

    setup_background
    advance_progress "后台设置"

    save_config

    step "保存管理脚本～♡"
    if save_script; then
        success "脚本保存到: ${INSTALL_DIR}/ksilly.sh ♡"
        info "以后直接跑: ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
    else
        warn "脚本保存失败了，不过不影响使用～♡"
    fi

    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${PINK}🎉 安装完成了～杂鱼应该感谢本小姐吧♡${NC}"
    echo ""
    echo -e "  ${DIM}果然没有本小姐不行呢，杂鱼～${NC}"
    echo ""
    info "安装目录: $INSTALL_DIR"
    show_access_info
    echo ""
    divider
    echo ""

    if confirm "现在就启动？杂鱼等不及了吧～♡"; then
        start_sillytavern
    else
        echo ""
        info "好吧，杂鱼想启动的时候用这个:"
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
            local status_word="${RED}已停止${NC}"
            if is_running; then
                status_icon="${GREEN}●${NC}"
                status_word="${GREEN}运行中${NC}"
            fi

            echo -e "  ${status_icon} SillyTavern ${CYAN}v${version:-?}${NC} ${DIM}| ${INSTALL_DIR}${NC}"
            echo -e "    状态: ${status_word}"

            [[ ! -f "$INSTALL_DIR/ksilly.sh" ]] && save_script 2>/dev/null
        else
            echo -e "  ${YELLOW}●${NC} SillyTavern 还没装呢，杂鱼～♡"
        fi

        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}${PINK}♡ 杂鱼想做什么呢～♡${NC}"
        echo ""
        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "    ${GREEN}1)${NC} 安装 SillyTavern     ${DIM}让本小姐来帮你～♡${NC}"
        echo -e "    ${GREEN}2)${NC} 更新 SillyTavern     ${DIM}看看有没有新版本～${NC}"
        echo -e "    ${GREEN}3)${NC} 卸载 SillyTavern     ${DIM}杂鱼不要了吗...♡${NC}"
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
        echo -e "    ${RED}0)${NC} 退出"
        echo ""
        divider

        local choice
        choice=$(read_input "快选一个吧，杂鱼")

        case "$choice" in
            1)
                if check_installed; then
                    warn "已经装过了呢，杂鱼记性不好吗～♡"
                    warn "安装目录: $INSTALL_DIR"
                    confirm "重新安装？之前的会被覆盖哦～♡" || continue
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
                echo -e "  ${PINK}♡${NC} 杂鱼要走了吗～下次再来找本小姐吧♡"
                echo -e "  ${DIM}  ...才不是舍不得你呢，杂鱼！${NC}"
                echo ""
                exit 0
                ;;
            *)
                warn "没有这个选项啦！杂鱼连数字都看不懂吗～♡"
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
                error "这脚本只支持 Linux / macOS / Termux 哦，杂鱼用的什么系统啊～♡"
                exit 1
            fi
            ;;
    esac

    init_log
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
            echo -e "  ${PINK}♡${NC} 用法: $0 {install|update|start|stop|restart|status|uninstall}"
            echo -e "    不带参数就是交互式菜单哦，杂鱼～♡"
            exit 1
            ;;
    esac
}

main "$@"
