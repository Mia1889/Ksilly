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
#

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

# ==================== 信号处理 ====================
trap 'echo ""; warn "操作已取消"; exit 130' INT

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
    echo -e "  ${BOLD}SillyTavern 一键部署脚本${NC} ${DIM}v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}by Mia1889 · github.com/Mia1889/Ksilly${NC}"
    divider
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
ask()     { echo -e "  ${BLUE}?${NC} $1"; }
success() { echo -e "  ${GREEN}★${NC} $1"; }

step() {
    echo ""
    echo -e "  ${CYAN}▸ $1${NC}"
}

divider() {
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
}

# ==================== 输入函数 ====================

confirm() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${BLUE}?${NC} ${prompt} ${DIM}(y/n)${NC}: " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) warn "请输入 y 或 n" ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result=""
    if [[ -n "$default" ]]; then
        echo -ne "  ${BLUE}→${NC} ${prompt} ${DIM}[$default]${NC}: " >&2
    else
        echo -ne "  ${BLUE}→${NC} ${prompt}: " >&2
    fi
    read -r result
    [[ -z "$result" && -n "$default" ]] && result="$default"
    echo "$result"
}

read_password() {
    local prompt="$1"
    local result=""
    echo -e "  ${YELLOW}⚠ 提示: 输入密码时屏幕不会显示任何字符，这是正常的安全行为${NC}" >&2
    while [[ -z "$result" ]]; do
        echo -ne "  ${BLUE}→${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "密码不能为空，请重新输入"
        fi
    done
    echo "$result"
}

pause_key() {
    echo ""
    read -rp "  按 Enter 继续..."
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
        error "需要 root 权限但未找到 sudo，请以 root 用户运行"
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
    # 使用缓存避免重复请求
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
    echo -e "  ${BOLD}访问地址:${NC}"
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
            echo -e "    公网访问   → ${YELLOW}无法自动获取公网IP，请自行查看${NC}"
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

# 保存脚本到安装目录，方便后续使用
save_script() {
    [[ -z "$INSTALL_DIR" || ! -d "$INSTALL_DIR" ]] && return 1

    local target="$INSTALL_DIR/ksilly.sh"
    local url="$SCRIPT_RAW_URL"

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && url="${GITHUB_PROXY}${url}"

    if curl -fsSL --connect-timeout 10 "$url" -o "$target" 2>/dev/null; then
        chmod +x "$target"
        return 0
    fi

    # 代理失败时尝试直连
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
    step "检测运行环境"

    # Termux 检测
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        IS_TERMUX=true
        OS_TYPE="termux"
        PKG_MANAGER="pkg"
        NEED_SUDO=""
        info "运行环境: Termux (Android)"
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
            info "运行环境: Debian/Ubuntu ($OS_TYPE)"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "运行环境: RHEL/CentOS ($OS_TYPE)"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "运行环境: Arch ($OS_TYPE)"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "运行环境: Alpine"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "运行环境: macOS"
            ;;
        *)
            warn "未识别的系统: $OS_TYPE，将尝试继续"
            PKG_MANAGER="unknown"
            ;;
    esac
}

detect_network() {
    step "检测网络环境"

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
        info "网络环境: 中国大陆 (将启用加速镜像)"
        find_github_proxy
    else
        IS_CHINA=false
        info "网络环境: 国际网络 (直连 GitHub)"
    fi
}

find_github_proxy() {
    info "测试 GitHub 代理可用性..."
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
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
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        echo "${GITHUB_PROXY}${url}"
    else
        echo "$url"
    fi
}

# ==================== 依赖安装 ====================

update_pkg_cache() {
    info "更新软件包索引..."
    case "$PKG_MANAGER" in
        pkg)    pkg update -y 2>/dev/null ;;
        apt)    $NEED_SUDO apt-get update -qq 2>/dev/null ;;
        yum)    $NEED_SUDO yum makecache -q 2>/dev/null ;;
        dnf)    $NEED_SUDO dnf makecache -q 2>/dev/null ;;
        pacman) $NEED_SUDO pacman -Sy --noconfirm 2>/dev/null ;;
        apk)    $NEED_SUDO apk update 2>/dev/null ;;
        brew)   brew update 2>/dev/null ;;
    esac
}

install_git() {
    if command_exists git; then
        info "Git $(git --version | awk '{print $3}') ✓"
        return 0
    fi

    info "安装 Git..."
    case "$PKG_MANAGER" in
        pkg)    pkg install -y git ;;
        apt)    $NEED_SUDO apt-get install -y -qq git ;;
        yum)    $NEED_SUDO yum install -y -q git ;;
        dnf)    $NEED_SUDO dnf install -y -q git ;;
        pacman) $NEED_SUDO pacman -S --noconfirm git ;;
        apk)    $NEED_SUDO apk add git ;;
        brew)   brew install git ;;
        *)      error "请手动安装 git"; return 1 ;;
    esac

    command_exists git && info "Git 安装完成" || { error "Git 安装失败"; return 1; }
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
    [[ -n "$ver" && "$ver" -ge "$MIN_NODE_VERSION" ]] 2>/dev/null
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) ✓"
        return 0
    fi

    command_exists node && warn "Node.js $(node -v) 版本过低，需要 v${MIN_NODE_VERSION}+"

    step "安装 Node.js"

    if [[ "$IS_TERMUX" == true ]]; then
        install_nodejs_termux
    elif [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi

    hash -r 2>/dev/null || true

    if check_node_version; then
        info "Node.js $(node -v) 安装完成"
    else
        error "Node.js 安装失败"; return 1
    fi

    # 设置 npm 镜像
    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null
        info "npm 镜像: npmmirror"
    fi
}

install_nodejs_termux() {
    pkg install -y nodejs 2>/dev/null || pkg install -y nodejs-lts 2>/dev/null
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
        brew)   brew install node@20 ;;
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
        *) error "不支持的 CPU 架构: $(uname -m)"; return 1 ;;
    esac

    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    info "下载 Node.js ${node_ver}..."
    if curl -fSL --progress-bar -o "${tmp_dir}/${filename}" "${mirror}/${node_ver}/${filename}"; then
        cd "$tmp_dir"
        tar xf "$filename"
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib} /usr/local/
        cd - >/dev/null
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
    else
        rm -rf "$tmp_dir"
        error "Node.js 下载失败"; return 1
    fi
}

install_dependencies() {
    step "安装系统依赖"

    [[ "$IS_TERMUX" != true ]] && get_sudo
    update_pkg_cache

    if [[ "$IS_TERMUX" == true ]]; then
        pkg install -y curl git 2>/dev/null
    else
        case "$PKG_MANAGER" in
            apt)    $NEED_SUDO apt-get install -y -qq curl wget tar xz-utils ;;
            yum)    $NEED_SUDO yum install -y -q curl wget tar xz ;;
            dnf)    $NEED_SUDO dnf install -y -q curl wget tar xz ;;
            pacman) $NEED_SUDO pacman -S --noconfirm --needed curl wget tar xz ;;
            apk)    $NEED_SUDO apk add curl wget tar xz ;;
            brew)   : ;;
        esac
    fi

    install_git
    install_nodejs
}

# ==================== PM2 管理 ====================

install_pm2() {
    if command_exists pm2; then
        info "PM2 $(pm2 -v 2>/dev/null) ✓"
        return 0
    fi
    info "安装 PM2..."
    npm install -g pm2 2>/dev/null
    if command_exists pm2; then
        info "PM2 安装完成"
        return 0
    else
        # 尝试用 npx
        warn "全局安装失败，将使用 npx 方式"
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
    # 检查 PM2
    if is_pm2_online; then return 0; fi
    # 检查直接进程
    if command_exists pgrep; then
        pgrep -f "node.*server\.js" &>/dev/null && return 0
    else
        ps aux 2>/dev/null | grep -v grep | grep -q "node.*server\.js" && return 0
    fi
    return 1
}

pm2_start() {
    install_pm2 || { error "PM2 不可用"; return 1; }

    cd "$INSTALL_DIR"
    if is_pm2_managed; then
        pm2 restart "$SERVICE_NAME" 2>/dev/null
    else
        pm2 start server.js --name "$SERVICE_NAME" 2>/dev/null
    fi
    pm2 save 2>/dev/null
    cd - >/dev/null

    sleep 2
    if is_pm2_online; then
        success "SillyTavern 已在后台启动"
        show_access_info
        return 0
    else
        error "启动失败，使用 'pm2 logs $SERVICE_NAME' 查看日志"
        return 1
    fi
}

pm2_stop() {
    if is_pm2_online; then
        pm2 stop "$SERVICE_NAME" 2>/dev/null
        pm2 save 2>/dev/null
        info "SillyTavern 已停止"
    elif command_exists pgrep; then
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            info "SillyTavern 进程已停止"
        else
            info "SillyTavern 未在运行"
        fi
    else
        info "SillyTavern 未在运行"
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
        success "Termux 开机自启已配置"
        warn "请确保已安装 Termux:Boot 应用"
    else
        echo ""
        info "正在生成自启动配置..."
        local startup_cmd
        startup_cmd=$(pm2 startup 2>&1 | grep -E "sudo|env" | head -1 || true)
        if [[ -n "$startup_cmd" ]]; then
            info "请手动执行以下命令完成自启动设置:"
            echo ""
            echo -e "    ${CYAN}${startup_cmd}${NC}"
            echo ""
            info "执行后再运行: ${CYAN}pm2 save${NC}"
        else
            # 尝试直接执行
            get_sudo
            pm2 startup 2>/dev/null || true
            pm2 save 2>/dev/null
            info "自启动配置已尝试完成"
        fi
    fi
}

pm2_remove_autostart() {
    if [[ "$IS_TERMUX" == true ]]; then
        rm -f "$HOME/.termux/boot/sillytavern.sh"
        info "Termux 开机自启已移除"
    else
        pm2 unstartup 2>/dev/null || true
        info "PM2 自启动已移除"
    fi
}

# 旧版 systemd 迁移
migrate_from_systemd() {
    [[ "$IS_TERMUX" == true ]] && return
    command_exists systemctl || return

    if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        warn "检测到旧版 systemd 服务"
        info "新版本已改用 PM2 管理后台进程"
        if confirm "是否移除旧版 systemd 服务?"; then
            get_sudo
            $NEED_SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
            success "旧版 systemd 服务已移除"
        fi
    fi
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"

    if [[ "$IS_TERMUX" == true ]]; then
        info "Termux 环境无需配置防火墙"
        return
    fi

    get_sudo || return

    step "检查防火墙"
    local firewall_found=false

    # UFW
    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
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
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "firewalld: 端口 $port 已放行"
            else
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld: 已放行端口 $port/tcp"
            fi
        fi
    fi

    # iptables
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
                success "iptables: 已放行端口 $port/tcp"
            else
                info "iptables: 端口 $port 已放行"
            fi
        fi
    fi

    [[ "$firewall_found" == false ]] && info "未检测到活动防火墙"

    echo ""
    warn "云服务器用户请确保安全组也放行了端口 ${port}/tcp"
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
    step "克隆 SillyTavern"

    INSTALL_DIR=$(read_input "安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "目录已存在 SillyTavern 安装"
            if confirm "删除现有安装并重新安装?"; then
                rm -rf "$INSTALL_DIR"
            else
                info "保留现有安装"
                return 0
            fi
        else
            error "目录已存在且不是 SillyTavern: $INSTALL_DIR"
            return 1
        fi
    fi

    echo ""
    ask "选择安装分支:"
    echo -e "    ${GREEN}1)${NC} release  ${DIM}稳定版 (推荐)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging  ${DIM}开发版 (最新功能)${NC}"
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

    if ! git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" 2>/dev/null; then
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理失败，尝试直连..."
            if ! git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR" 2>/dev/null; then
                error "克隆失败，请检查网络"; return 1
            fi
        else
            error "克隆失败，请检查网络"; return 1
        fi
    fi
    success "仓库克隆完成"

    # 规范化换行符
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖"
    cd "$INSTALL_DIR"
    if npm install --no-audit --no-fund 2>&1 | tail -3; then
        success "npm 依赖安装完成"
    else
        error "npm 依赖安装失败"; cd - >/dev/null; return 1
    fi
    cd - >/dev/null

    save_config
}

configure_sillytavern() {
    step "配置 SillyTavern"

    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed -i 's/\r$//' "$config_file"
            info "已生成配置文件"
        else
            error "未找到 default.yaml"; return 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}配置向导${NC}"
    divider

    # --- 监听设置 ---
    echo ""
    echo -e "  ${BOLD}1. 监听模式${NC}"
    echo -e "     ${DIM}开启后允许局域网/外网设备访问 (0.0.0.0)${NC}"
    echo -e "     ${DIM}关闭则仅本机可用 (127.0.0.1)${NC}"
    echo ""

    local listen_enabled=false
    if confirm "开启监听 (允许远程访问)?"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        success "已开启监听"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "仅本机访问"
    fi

    # --- 端口 ---
    echo ""
    echo -e "  ${BOLD}2. 端口设置${NC}"
    local port
    port=$(read_input "设置端口号" "8000")
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        set_yaml_val "port" "$port" "$config_file"
        info "端口: $port"
    else
        warn "无效端口，使用默认 8000"
        port="8000"
    fi

    # --- 白名单 ---
    echo ""
    echo -e "  ${BOLD}3. 白名单模式${NC}"
    echo -e "     ${DIM}开启后仅白名单 IP 可访问${NC}"
    echo -e "     ${DIM}需要远程访问时建议关闭${NC}"
    echo ""
    if confirm "关闭白名单模式?"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        success "白名单已关闭"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "白名单保持开启"
    fi

    # --- 基础认证 ---
    echo ""
    echo -e "  ${BOLD}4. 基础认证 (HTTP Auth)${NC}"
    echo -e "     ${DIM}访问时需输入用户名和密码${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "     ${RED}已开启远程访问，强烈建议启用认证${NC}"
    fi
    echo ""
    if confirm "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        echo ""
        local auth_user=""
        while [[ -z "$auth_user" ]]; do
            auth_user=$(read_input "设置认证用户名")
            [[ -z "$auth_user" ]] && warn "用户名不能为空"
        done

        local auth_pass
        auth_pass=$(read_password "设置认证密码")

        # 处理 basicAuthUser 嵌套结构
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

        success "认证已开启 (用户: $auth_user)"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "认证保持关闭"
    fi

    # --- 防火墙 ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置已保存"
}

setup_background() {
    echo ""
    divider
    echo -e "  ${BOLD}后台运行设置${NC}"
    divider

    # 检查旧版 systemd
    [[ "$IS_TERMUX" != true ]] && get_sudo 2>/dev/null
    migrate_from_systemd

    echo ""
    echo -e "  ${BOLD}● PM2 后台运行${NC}"
    echo -e "    ${DIM}使用 PM2 管理 SillyTavern 进程${NC}"
    echo -e "    ${DIM}关闭终端后继续运行，支持自动重启${NC}"
    echo ""

    if confirm "启用 PM2 后台运行?"; then
        install_pm2 || return 1
        success "PM2 已就绪"

        echo ""
        if confirm "同时设置开机自启动?"; then
            pm2_setup_autostart
        fi
    fi
}

# ==================== 启动/停止 ====================

start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    if is_running; then
        warn "SillyTavern 已在运行中"
        show_access_info
        return 0
    fi

    echo ""
    echo -e "  ${GREEN}1)${NC} 后台运行 ${DIM}(PM2，推荐)${NC}"
    echo -e "  ${GREEN}2)${NC} 前台运行 ${DIM}(Ctrl+C 停止)${NC}"
    echo ""
    local mode
    mode=$(read_input "选择启动方式" "1")

    case "$mode" in
        1)
            step "以 PM2 后台模式启动"
            pm2_start
            ;;
        2)
            local port
            port=$(get_port)
            step "前台启动 SillyTavern"
            info "按 Ctrl+C 停止"
            show_access_info
            echo ""
            cd "$INSTALL_DIR"
            node server.js
            cd - >/dev/null
            ;;
        *)
            warn "无效选择"
            ;;
    esac
}

stop_sillytavern() {
    if ! is_running; then
        info "SillyTavern 未在运行"
        return 0
    fi
    step "停止 SillyTavern"
    pm2_stop
}

restart_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi
    step "重启 SillyTavern"
    pm2_stop
    sleep 1
    pm2_start
}

# ==================== 状态显示 ====================

show_status() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    print_banner

    local version="" branch="" config_file="$INSTALL_DIR/config.yaml"

    [[ -f "$INSTALL_DIR/package.json" ]] && \
        version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')

    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null)

    # 运行状态
    local status_text status_color
    if is_running; then
        status_text="运行中"
        status_color="$GREEN"
    else
        status_text="已停止"
        status_color="$RED"
    fi

    echo -e "  ${BOLD}基本信息${NC}"
    divider
    echo -e "    版本       ${CYAN}${version:-未知}${NC}"
    echo -e "    分支       ${CYAN}${branch:-未知}${NC}"
    echo -e "    目录       ${DIM}${INSTALL_DIR}${NC}"
    echo -e "    状态       ${status_color}● ${status_text}${NC}"

    # PM2 状态
    if is_pm2_managed; then
        echo -e "    进程管理   ${GREEN}PM2${NC}"
    else
        echo -e "    进程管理   ${DIM}未配置${NC}"
    fi

    echo ""

    # 配置信息
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

    # 设置代理
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    if ! git fetch origin --quiet 2>/dev/null; then
        # 还原并返回失败
        [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
            git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null
        cd - >/dev/null
        return 1
    fi

    # 还原 remote URL
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
        warn "SillyTavern 正在运行，将先停止"
        pm2_stop
    fi

    cd "$INSTALL_DIR"

    # 备份配置
    info "备份配置..."
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "备份: $backup_dir"

    # 设置代理
    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")" 2>/dev/null
    fi

    info "拉取最新代码..."
    if ! git pull --ff-only 2>/dev/null; then
        warn "快速合并失败，尝试强制更新..."
        local current_branch
        current_branch=$(git branch --show-current)
        git fetch --all 2>/dev/null
        git reset --hard "origin/$current_branch" 2>/dev/null
    fi
    success "代码更新完成"

    # 还原 URL
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO" 2>/dev/null

    # 规范化
    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    info "更新 npm 依赖..."
    npm install --no-audit --no-fund 2>&1 | tail -3

    # 恢复配置
    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        info "配置已恢复"
    fi

    cd - >/dev/null

    # 更新脚本副本
    save_script 2>/dev/null && info "管理脚本已更新"

    success "SillyTavern 更新完成!"

    echo ""
    if confirm "立即启动 SillyTavern?"; then
        pm2_start
    fi
}

handle_update() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return
    fi

    detect_network

    step "检查更新"

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
    info "连接远程仓库..."

    if check_for_updates; then
        echo ""
        warn "发现 ${UPDATE_BEHIND} 个新提交可更新"
        echo ""
        if confirm "是否更新 SillyTavern?"; then
            do_update
        else
            info "已取消更新"
        fi
    else
        echo ""
        success "当前已是最新版本，无需更新"
    fi
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    echo ""
    warn "即将卸载 SillyTavern"
    echo -e "    安装目录: ${DIM}${INSTALL_DIR}${NC}"
    echo ""
    confirm "确定要卸载吗? 此操作不可恢复!" || { info "已取消"; return 0; }
    echo ""
    confirm "再次确认: 删除所有数据?" || { info "已取消"; return 0; }

    # 停止进程
    pm2_stop
    pm2_remove

    # 防火墙清理
    local port
    port=$(get_port)
    remove_firewall_port "$port"

    # 移除旧版 systemd (如果存在)
    if [[ "$IS_TERMUX" != true ]] && command_exists systemctl; then
        if $NEED_SUDO systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            get_sudo
            $NEED_SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
            $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
            $NEED_SUDO systemctl daemon-reload 2>/dev/null || true
        fi
    fi

    # 移除 Termux 自启动
    rm -f "$HOME/.termux/boot/sillytavern.sh" 2>/dev/null

    # 备份数据
    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm "备份聊天数据和角色卡?"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            cp -r "$INSTALL_DIR/data" "$backup_path/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$backup_path/"
            success "数据备份: $backup_path"
        fi
    fi

    # 删除目录
    rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "SillyTavern 已卸载"

    echo ""
    if confirm "同时卸载 Node.js?"; then
        if [[ "$IS_TERMUX" == true ]]; then
            pkg uninstall -y nodejs 2>/dev/null || true
        else
            get_sudo
            case "$PKG_MANAGER" in
                apt)    $NEED_SUDO apt-get remove -y nodejs 2>/dev/null; $NEED_SUDO rm -f /etc/apt/sources.list.d/nodesource.list ;;
                yum)    $NEED_SUDO yum remove -y nodejs 2>/dev/null ;;
                dnf)    $NEED_SUDO dnf remove -y nodejs 2>/dev/null ;;
                pacman) $NEED_SUDO pacman -R --noconfirm nodejs npm 2>/dev/null ;;
            esac
        fi
        info "Node.js 已卸载"
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

    while true; do
        print_banner

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
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 修改监听设置"
        echo -e "  ${GREEN}2)${NC} 修改端口"
        echo -e "  ${GREEN}3)${NC} 修改白名单模式"
        echo -e "  ${GREEN}4)${NC} 修改基础认证"
        echo -e "  ${GREEN}5)${NC} 修改用户账户系统  ${DIM}(enableUserAccounts)${NC}"
        echo -e "  ${GREEN}6)${NC} 修改隐蔽登录      ${DIM}(enableDiscreetLogin)${NC}"
        echo -e "  ${GREEN}7)${NC} 编辑完整配置文件"
        echo -e "  ${GREEN}8)${NC} 重置为默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行管理"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "选择操作")

        case "$choice" in
            1)
                echo ""
                echo -e "  当前状态: 监听 $(format_bool "$listen_val")"
                if confirm "是否开启监听?"; then
                    set_yaml_val "listen" "true" "$config_file"
                    success "已开启监听"
                    open_firewall_port "$(get_port)"
                else
                    set_yaml_val "listen" "false" "$config_file"
                    info "已关闭监听"
                fi
                ;;
            2)
                echo ""
                echo -e "  当前端口: ${CYAN}${port_val}${NC}"
                local new_port
                new_port=$(read_input "新端口号" "$port_val")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    success "端口已修改为: $new_port"
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    [[ "$cur_listen" == "true" ]] && open_firewall_port "$new_port"
                else
                    error "无效端口: $new_port"
                fi
                ;;
            3)
                echo ""
                echo -e "  当前状态: 白名单 $(format_bool "$whitelist_val")"
                if confirm "关闭白名单模式?"; then
                    set_yaml_val "whitelistMode" "false" "$config_file"
                    success "白名单已关闭"
                else
                    set_yaml_val "whitelistMode" "true" "$config_file"
                    info "白名单已开启"
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
                        [[ -z "$auth_user" ]] && warn "不能为空"
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
                    success "认证已开启 (用户: $auth_user)"
                else
                    set_yaml_val "basicAuthMode" "false" "$config_file"
                    info "认证已关闭"
                fi
                ;;
            5)
                echo ""
                echo -e "  当前状态: 用户账户系统 $(format_bool "${user_acc:-false}")"
                echo -e "  ${DIM}开启后可创建多个独立用户，各自拥有独立数据${NC}"
                echo ""
                if confirm "开启用户账户系统?"; then
                    set_yaml_val "enableUserAccounts" "true" "$config_file"
                    success "用户账户系统已开启"
                else
                    set_yaml_val "enableUserAccounts" "false" "$config_file"
                    info "用户账户系统已关闭"
                fi
                ;;
            6)
                echo ""
                echo -e "  当前状态: 隐蔽登录 $(format_bool "${discreet:-false}")"
                echo -e "  ${DIM}开启后登录页面不显示用户头像和用户名${NC}"
                echo ""
                if confirm "开启隐蔽登录?"; then
                    set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                    success "隐蔽登录已开启"
                else
                    set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                    info "隐蔽登录已关闭"
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            8)
                if confirm "重置配置为默认值?"; then
                    if [[ -f "$INSTALL_DIR/default.yaml" ]]; then
                        cp "$INSTALL_DIR/default.yaml" "$config_file"
                        sed -i 's/\r$//' "$config_file"
                        success "已重置为默认配置"
                    else
                        error "未找到 default.yaml"
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
                warn "无效选项"
                ;;
        esac

        # 提示重启
        if [[ "$choice" =~ ^[1-6]$ ]] && is_running; then
            echo ""
            warn "配置修改后需重启生效"
            if confirm "立即重启 SillyTavern?"; then
                restart_sillytavern
            fi
        fi

        pause_key
    done
}

# ==================== PM2 管理菜单 ====================

pm2_menu() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    while true; do
        print_banner

        # 显示当前状态
        echo -e "  ${BOLD}PM2 后台运行状态${NC}"
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

        # 检查自启动
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
        choice=$(read_input "选择操作")

        case "$choice" in
            1) install_pm2 ;;
            2) pm2_start ;;
            3) pm2_stop ;;
            4) restart_sillytavern ;;
            5)
                if is_pm2_managed; then
                    echo ""
                    echo -e "  ${GREEN}1)${NC} 查看最近日志"
                    echo -e "  ${GREEN}2)${NC} 实时跟踪日志 ${DIM}(Ctrl+C 退出)${NC}"
                    echo -e "  ${GREEN}3)${NC} 清空日志"
                    echo ""
                    local log_choice
                    log_choice=$(read_input "选择" "1")
                    case "$log_choice" in
                        1) echo ""; pm2 logs "$SERVICE_NAME" --lines 50 --nostream 2>/dev/null ;;
                        2) pm2 logs "$SERVICE_NAME" 2>/dev/null ;;
                        3) pm2 flush "$SERVICE_NAME" 2>/dev/null; success "日志已清空" ;;
                    esac
                else
                    warn "SillyTavern 未在 PM2 中注册"
                fi
                ;;
            6) pm2_setup_autostart ;;
            7) pm2_remove_autostart ;;
            8)
                if confirm "从 PM2 中移除 SillyTavern 进程?"; then
                    pm2_stop
                    pm2_remove
                    success "已从 PM2 移除"
                fi
                ;;
            0) return 0 ;;
            *) warn "无效选项" ;;
        esac

        pause_key
    done
}

# ==================== 完整安装流程 ====================

full_install() {
    print_banner

    echo -e "  ${BOLD}${GREEN}开始安装 SillyTavern${NC}"
    divider

    detect_os
    detect_network
    install_dependencies

    echo ""
    clone_sillytavern
    configure_sillytavern
    setup_background

    save_config

    # 保存脚本到安装目录
    step "保存管理脚本"
    if save_script; then
        success "脚本已保存到: ${INSTALL_DIR}/ksilly.sh"
        info "后续可直接运行: ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
    else
        warn "脚本保存失败，可稍后重试"
    fi

    echo ""
    divider
    echo ""
    echo -e "  ${BOLD}${GREEN}🎉 SillyTavern 安装完成!${NC}"
    echo ""
    info "安装目录: $INSTALL_DIR"
    show_access_info
    echo ""
    divider
    echo ""

    if confirm "立即启动 SillyTavern?"; then
        start_sillytavern
    else
        echo ""
        info "稍后启动方式:"
        echo -e "    ${CYAN}bash ${INSTALL_DIR}/ksilly.sh${NC}"
        echo -e "    或 ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
    fi
}

# ==================== 主菜单 ====================

main_menu() {
    while true; do
        print_banner
        load_config

        # 状态行
        if check_installed; then
            local version=""
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                version=$(grep '"version"' "$INSTALL_DIR/package.json" 2>/dev/null | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')

            local status_icon="${RED}●${NC}"
            is_running && status_icon="${GREEN}●${NC}"

            echo -e "  ${status_icon} SillyTavern ${CYAN}v${version:-?}${NC} ${DIM}| ${INSTALL_DIR}${NC}"

            # 尝试保存/更新本地脚本副本
            [[ ! -f "$INSTALL_DIR/ksilly.sh" ]] && save_script 2>/dev/null
        else
            echo -e "  ${YELLOW}●${NC} SillyTavern 未安装"
        fi

        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "    ${GREEN}1)${NC} 安装 SillyTavern"
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
        echo -e "    ${RED}0)${NC} 退出"
        echo ""
        divider

        local choice
        choice=$(read_input "选择操作")

        case "$choice" in
            1)
                if check_installed; then
                    warn "SillyTavern 已安装在 $INSTALL_DIR"
                    confirm "重新安装?" || continue
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
    # 平台检查
    local uname_s
    uname_s=$(uname -s 2>/dev/null || echo "Unknown")

    case "$uname_s" in
        Linux|Darwin) ;;
        *)
            # 可能是 Termux (也报告 Linux)
            if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
                error "此脚本仅支持 Linux / macOS / Termux"
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
            echo "  不带参数进入交互式菜单"
            exit 1
            ;;
    esac
}

main "$@"
