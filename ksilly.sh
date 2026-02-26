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
#  版本: 1.1.0
#

set -euo pipefail

# ==================== 全局常量 ====================
SCRIPT_VERSION="1.1.0"
KSILLY_CONF="$HOME/.ksilly.conf"
DEFAULT_INSTALL_DIR="$HOME/SillyTavern"
SILLYTAVERN_REPO="https://github.com/SillyTavern/SillyTavern.git"
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
GITHUB_PROXY=""
INSTALL_DIR=""
OS_TYPE=""
PKG_MANAGER=""
CURRENT_USER=$(whoami)
NEED_SUDO=""

# ==================== 工具函数 ====================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo '  ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗'
    echo '  ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝'
    echo '  █████╔╝ ███████╗██║██║     ██║   ╚████╔╝ '
    echo '  ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝  '
    echo '  ██║  ██╗███████║██║███████╗███████╗██║   '
    echo '  ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝  '
    echo -e "${NC}"
    echo -e "  ${BOLD}简单 SillyTavern 部署脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "  ${DIM}github.com/Mia1889/Ksilly${NC}"
    echo -e "  ─────────────────────────────────────────"
    echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }

step() {
    echo -e "\n  ${CYAN}▶ $1${NC}"
}

divider() {
    echo -e "  ${DIM}─────────────────────────────────────────${NC}"
}

confirm_no_default() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${BLUE}?${NC} ${prompt} (y/n): " >&2
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
        echo -ne "  ${BLUE}»${NC} ${prompt} [${DIM}${default}${NC}]: " >&2
    else
        echo -ne "  ${BLUE}»${NC} ${prompt}: " >&2
    fi
    read -r result
    if [[ -z "$result" && -n "$default" ]]; then
        result="$default"
    fi
    echo "$result"
}

read_password() {
    local prompt="$1"
    local result=""
    while [[ -z "$result" ]]; do
        echo -ne "  ${BLUE}»${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            warn "密码不能为空"
        fi
    done
    echo "$result"
}

# ==================== 安全读取配置值 ====================

get_yaml_val() {
    local key="$1"
    local file="$2"
    local val=""
    val=$(grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1 | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | tr -d '\r\n "'\''' | sed 's/#.*//')
    echo "$val"
}

# 安全地在 YAML 中设置一个顶层键值
set_yaml_val() {
    local key="$1"
    local value="$2"
    local file="$3"
    if grep -qE "^[[:space:]]*${key}:" "$file" 2>/dev/null; then
        sed -i "s|^\([[:space:]]*\)${key}:.*|\1${key}: ${value}|" "$file"
    else
        # 键不存在则追加
        echo "${key}: ${value}" >> "$file"
    fi
}

get_port() {
    local port
    port=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml")
    if ! echo "$port" | grep -qE '^[0-9]+$'; then
        port="8000"
    fi
    echo "$port"
}

# ==================== 修复: 可移植的 IP 获取 ====================

get_local_ip() {
    local ip=""

    # 方法1: ip route get — 最准确，取 src 字段
    if command_exists ip; then
        ip=$(ip route get 1.1.1.1 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
    fi

    # 方法2: ip addr — 取第一个全局作用域 IPv4
    if [[ -z "$ip" ]] && command_exists ip; then
        ip=$(ip -4 addr show scope global 2>/dev/null \
            | awk '/inet /{split($2,a,"/"); print a[1]; exit}')
    fi

    # 方法3: hostname -I
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # 方法4: ifconfig (macOS / 旧系统)
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null \
            | awk '/inet /{gsub(/addr:/,"",$2); if($2!="127.0.0.1"){print $2; exit}}')
    fi

    # 方法5: 通过连接探测 (终极兜底)
    if [[ -z "$ip" ]]; then
        if command_exists python3; then
            ip=$(python3 -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(('8.8.8.8',80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || true)
        elif command_exists python; then
            ip=$(python -c "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(('8.8.8.8',80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || true)
        fi
    fi

    # 仍然失败
    if [[ -z "$ip" || "$ip" == "127.0.0.1" ]]; then
        ip="<你的服务器IP>"
    fi

    echo "$ip"
}

# ==================== 防火墙管理 ====================

open_firewall_port() {
    local port="$1"
    get_sudo

    step "检查防火墙 (端口 ${port})..."

    local firewall_found=false

    # ---- UFW ----
    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "UFW: 端口 $port 已放行"
            else
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW: 已放行 $port/tcp"
            fi
        fi
    fi

    # ---- firewalld ----
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
                success "firewalld: 已放行 $port/tcp"
            fi
        fi
    fi

    # ---- iptables ----
    if [[ "$firewall_found" == false ]] && command_exists iptables; then
        local has_drop
        has_drop=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || true)
        if [[ "$has_drop" -gt 0 ]]; then
            firewall_found=true
            if $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                info "iptables: 端口 $port 已放行"
            else
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
                success "iptables: 已放行 $port/tcp"
                if command_exists iptables-save; then
                    if [[ -d /etc/iptables ]]; then
                        $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
                    elif command_exists netfilter-persistent; then
                        $NEED_SUDO netfilter-persistent save 2>/dev/null || true
                    fi
                fi
            fi
        fi
    fi

    if [[ "$firewall_found" == false ]]; then
        info "未检测到活动防火墙"
    fi

    warn "云服务器请在控制台安全组中放行 ${port}/tcp"
}

remove_firewall_port() {
    local port="$1"
    get_sudo

    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
        fi
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

# ==================== 通用工具 ====================

load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        # shellcheck source=/dev/null
        source "$KSILLY_CONF"
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

command_exists() {
    command -v "$1" &>/dev/null
}

get_sudo() {
    if [[ "$EUID" -eq 0 ]]; then
        NEED_SUDO=""
    else
        if command_exists sudo; then
            NEED_SUDO="sudo"
        else
            error "需要 root 权限但未找到 sudo"; exit 1
        fi
    fi
}

# ==================== 检测函数 ====================

detect_os() {
    step "检测操作系统..."

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
            info "Debian/Ubuntu 系 ($OS_TYPE)"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "RHEL/CentOS 系 ($OS_TYPE)"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "Arch 系 ($OS_TYPE)"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "Alpine Linux"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "macOS"
            ;;
        *)
            warn "未识别系统: $OS_TYPE，将尝试继续"
            PKG_MANAGER="unknown"
            ;;
    esac
}

detect_network() {
    step "检测网络环境..."

    local china_test=false

    if curl -s --connect-timeout 3 --max-time 5 "https://www.baidu.com" &>/dev/null; then
        if ! curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" &>/dev/null; then
            china_test=true
        fi
    fi

    if [[ "$china_test" == false ]]; then
        local country=""
        country=$(curl -s --connect-timeout 5 --max-time 8 "https://ipapi.co/country_code/" 2>/dev/null || true)
        [[ "$country" == "CN" ]] && china_test=true
    fi

    if [[ "$china_test" == true ]]; then
        IS_CHINA=true
        info "中国大陆网络 → 启用加速镜像"
        find_github_proxy
    else
        IS_CHINA=false
        info "国际网络 → 直连"
    fi
}

find_github_proxy() {
    info "测试 GitHub 代理..."
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            success "可用代理: $proxy"
            return 0
        fi
    done
    warn "未找到可用代理，将直连"
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

# ==================== 安装函数 ====================

update_pkg_cache() {
    case "$PKG_MANAGER" in
        apt)    $NEED_SUDO apt-get update -qq ;;
        yum)    $NEED_SUDO yum makecache -q ;;
        dnf)    $NEED_SUDO dnf makecache -q ;;
        pacman) $NEED_SUDO pacman -Sy --noconfirm ;;
        apk)    $NEED_SUDO apk update ;;
        brew)   brew update ;;
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
        brew)   brew install git ;;
        *)      error "请手动安装 git"; exit 1 ;;
    esac

    command_exists git && success "Git 安装完成" || { error "Git 安装失败"; exit 1; }
}

check_node_version() {
    command_exists node || return 1
    local ver
    ver=$(node -v | sed 's/v//' | cut -d. -f1)
    [[ "$ver" -ge "$MIN_NODE_VERSION" ]]
}

install_nodejs() {
    if check_node_version; then
        info "Node.js $(node -v) ✓"
        return 0
    fi

    command_exists node && warn "Node.js $(node -v) 过低，需 v${MIN_NODE_VERSION}+"

    step "安装 Node.js v20.x..."

    if [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi

    hash -r 2>/dev/null || true

    if check_node_version; then
        success "Node.js $(node -v) + npm $(npm -v)"
    else
        error "Node.js 安装失败"; exit 1
    fi

    if [[ "$IS_CHINA" == true ]]; then
        npm config set registry https://registry.npmmirror.com
        info "npm 镜像 → npmmirror"
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
        *) error "不支持的架构: $(uname -m)"; exit 1 ;;
    esac

    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local download_url="${mirror}/${node_ver}/${filename}"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if curl -fSL --progress-bar -o "${tmp_dir}/${filename}" "$download_url"; then
        cd "$tmp_dir"
        tar xf "$filename"
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib} /usr/local/
        cd - >/dev/null
        rm -rf "$tmp_dir"
        hash -r 2>/dev/null || true
    else
        rm -rf "$tmp_dir"
        error "Node.js 下载失败"; exit 1
    fi
}

install_dependencies() {
    step "安装系统依赖..."
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

    install_git
    install_nodejs
}

# ==================== SillyTavern 操作 ====================

clone_sillytavern() {
    step "克隆 SillyTavern..."

    INSTALL_DIR=$(read_input "安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "已存在安装: $INSTALL_DIR"
            if confirm_no_default "删除并重新安装?"; then
                rm -rf "$INSTALL_DIR"
            else
                info "保留现有安装"
                return 0
            fi
        else
            error "目录已存在且非 SillyTavern: $INSTALL_DIR"; exit 1
        fi
    fi

    echo ""
    echo -e "  ${BOLD}选择分支:${NC}"
    echo -e "    ${GREEN}1)${NC} release ${DIM}(稳定版，推荐)${NC}"
    echo -e "    ${YELLOW}2)${NC} staging ${DIM}(开发版)${NC}"
    echo ""
    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "选择 (1/2)")
    done

    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"

    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")

    if git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR"; then
        success "克隆完成 (${branch})"
    else
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理失败，尝试直连..."
            if git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR"; then
                success "克隆完成 (直连)"
            else
                error "克隆失败"; exit 1
            fi
        else
            error "克隆失败"; exit 1
        fi
    fi

    # 规范化换行符
    find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    step "安装 npm 依赖..."
    cd "$INSTALL_DIR"
    if npm install --no-audit --no-fund 2>&1 | tail -3; then
        success "依赖安装完成"
    else
        error "依赖安装失败"; exit 1
    fi
    cd - >/dev/null

    save_config
}

configure_sillytavern() {
    step "配置 SillyTavern..."

    local config_file="$INSTALL_DIR/config.yaml"
    local default_file="$INSTALL_DIR/default.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$default_file" ]]; then
            cp "$default_file" "$config_file"
            sed -i 's/\r$//' "$config_file"
            info "已生成 config.yaml"
        else
            error "未找到 default.yaml"; exit 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}${CYAN}配置向导${NC}"
    divider

    # --- 1. 监听 ---
    echo ""
    echo -e "  ${YELLOW}● 监听设置${NC} ${DIM}— 控制是否允许远程访问${NC}"
    echo -e "    ${DIM}开启 → 0.0.0.0 (局域网/外网可访问)${NC}"
    echo -e "    ${DIM}关闭 → 127.0.0.1 (仅本机)${NC}"
    echo ""
    local listen_enabled=false
    if confirm_no_default "开启监听 (允许远程访问)?"; then
        set_yaml_val "listen" "true" "$config_file"
        listen_enabled=true
        success "监听: 开启"
    else
        set_yaml_val "listen" "false" "$config_file"
        info "监听: 关闭"
    fi

    # --- 端口 ---
    echo ""
    local port
    port=$(read_input "端口号" "8000")
    set_yaml_val "port" "$port" "$config_file"
    info "端口: $port"

    # --- 2. 白名单 ---
    echo ""
    echo -e "  ${YELLOW}● 白名单模式${NC} ${DIM}— 仅允许白名单 IP 访问${NC}"
    echo -e "    ${DIM}远程访问场景建议关闭${NC}"
    echo ""
    if confirm_no_default "关闭白名单模式?"; then
        set_yaml_val "whitelistMode" "false" "$config_file"
        success "白名单: 关闭"
    else
        set_yaml_val "whitelistMode" "true" "$config_file"
        info "白名单: 开启"
    fi

    # --- 3. 基础认证 ---
    echo ""
    echo -e "  ${YELLOW}● 基础认证${NC} ${DIM}— 访问时需输入用户名密码${NC}"
    if [[ "$listen_enabled" == true ]]; then
        echo -e "    ${RED}已开启远程访问，强烈建议开启!${NC}"
    fi
    echo ""
    if confirm_no_default "开启基础认证?"; then
        set_yaml_val "basicAuthMode" "true" "$config_file"

        local auth_user
        auth_user=$(read_input "认证用户名")
        while [[ -z "$auth_user" ]]; do
            warn "用户名不能为空"
            auth_user=$(read_input "认证用户名")
        done

        local auth_pass
        auth_pass=$(read_password "认证密码")

        # 使用更可靠的 sed 修改 basicAuthUser 块
        sed -i "/basicAuthUser:/,/^[^ #]/{
            s|\([[:space:]]*\)username:.*|\1username: \"${auth_user}\"|
            s|\([[:space:]]*\)password:.*|\1password: \"${auth_pass}\"|
        }" "$config_file"

        success "认证: 开启 (用户: $auth_user)"
    else
        set_yaml_val "basicAuthMode" "false" "$config_file"
        info "认证: 关闭"
    fi

    # --- 4. 用户账户系统 ---
    echo ""
    echo -e "  ${YELLOW}● 用户账户系统${NC} ${DIM}— 多用户独立配置与数据隔离${NC}"
    echo -e "    ${DIM}开启后每个用户拥有独立的设置、角色和聊天记录${NC}"
    echo ""
    if confirm_no_default "开启用户账户系统 (enableUserAccounts)?"; then
        set_yaml_val "enableUserAccounts" "true" "$config_file"
        success "用户账户: 开启"
    else
        set_yaml_val "enableUserAccounts" "false" "$config_file"
        info "用户账户: 关闭"
    fi

    # --- 5. 隐蔽登录 ---
    echo ""
    echo -e "  ${YELLOW}● 隐蔽登录${NC} ${DIM}— 登录页隐藏应用名称与图标${NC}"
    echo -e "    ${DIM}适合公开网络，防止他人看到 SillyTavern 字样${NC}"
    echo ""
    if confirm_no_default "开启隐蔽登录 (enableDiscreetLogin)?"; then
        set_yaml_val "enableDiscreetLogin" "true" "$config_file"
        success "隐蔽登录: 开启"
    else
        set_yaml_val "enableDiscreetLogin" "false" "$config_file"
        info "隐蔽登录: 关闭"
    fi

    # --- 6. 防火墙 ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置已保存: $config_file"
}

setup_service() {
    echo ""
    divider
    echo -e "  ${BOLD}${CYAN}后台运行设置${NC}"
    divider
    echo ""

    if ! command_exists systemctl; then
        warn "系统不支持 systemd，请使用 screen/tmux 保持后台运行"
        return 0
    fi

    local enable_service=false
    local enable_autostart=false

    echo -e "  ${YELLOW}● 后台运行${NC} ${DIM}— 关闭终端也不停止${NC}"
    echo ""
    if confirm_no_default "开启后台运行 (systemd 服务)?"; then
        enable_service=true

        echo ""
        echo -e "  ${YELLOW}● 开机自启${NC} ${DIM}— 系统重启后自动运行${NC}"
        echo ""
        if confirm_no_default "开启开机自启?"; then
            enable_autostart=true
        fi
    fi

    if [[ "$enable_service" == true ]]; then
        step "创建 systemd 服务..."
        get_sudo

        local node_path
        node_path=$(which node)

        $NEED_SUDO tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=SillyTavern Server
Documentation=https://docs.sillytavern.app
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
        success "服务创建完成"

        if [[ "$enable_autostart" == true ]]; then
            $NEED_SUDO systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
            success "开机自启: 已开启"
        else
            $NEED_SUDO systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
            info "开机自启: 未开启"
        fi
    fi
}

# ==================== 显示访问地址 ====================

show_access_info() {
    local port
    port=$(get_port)

    local listen_mode
    listen_mode=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")

    echo ""
    echo -e "  ${BOLD}访问地址:${NC}"
    echo -e "    本地: ${CYAN}http://127.0.0.1:${port}${NC}"
    if [[ "$listen_mode" == "true" ]]; then
        local ip_addr
        ip_addr=$(get_local_ip)
        echo -e "    远程: ${CYAN}http://${ip_addr}:${port}${NC}"
    fi
}

# ==================== 启动/停止/状态 ====================

start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "启动 SillyTavern (systemd)..."
        get_sudo
        $NEED_SUDO systemctl start "$SERVICE_NAME"
        sleep 2

        if $NEED_SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
            success "SillyTavern 已启动"
            show_access_info
        else
            error "启动失败 → journalctl -u $SERVICE_NAME -n 20"
        fi
    else
        step "前台启动 SillyTavern..."
        show_access_info
        echo ""
        info "按 Ctrl+C 停止"
        echo ""
        cd "$INSTALL_DIR"
        node server.js
        cd - >/dev/null
    fi
}

stop_sillytavern() {
    if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "停止 SillyTavern..."
        get_sudo
        $NEED_SUDO systemctl stop "$SERVICE_NAME"
        success "已停止"
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            step "停止进程 (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            success "已停止"
        else
            info "SillyTavern 未在运行"
        fi
    fi
}

format_bool() {
    local val="${1:-false}"
    if [[ "$val" == "true" ]]; then
        echo -e "${GREEN}开启${NC}"
    else
        echo -e "${YELLOW}关闭${NC}"
    fi
}

format_status_dot() {
    local val="${1:-false}"
    if [[ "$val" == "true" ]]; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}●${NC}"
    fi
}

show_status() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    step "运行状态"
    echo ""

    # 版本与分支
    local version="未知" branch="未知"
    [[ -f "$INSTALL_DIR/package.json" ]] && \
        version=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
    [[ -d "$INSTALL_DIR/.git" ]] && \
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")

    echo -e "  版本: ${BOLD}${version}${NC}  分支: ${BOLD}${branch}${NC}  目录: ${DIM}${INSTALL_DIR}${NC}"
    echo ""

    # 运行状态
    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        local running=false autostart=false
        systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && running=true
        systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && autostart=true
        echo -e "  运行: $(format_status_dot $running) $(if $running; then echo '运行中'; else echo '已停止'; fi)    自启: $(format_status_dot $autostart) $(if $autostart; then echo '已启用'; else echo '未启用'; fi)"
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            echo -e "  运行: ${GREEN}● 运行中${NC} (PID: $pid)    服务: ${DIM}未配置 systemd${NC}"
        else
            echo -e "  运行: ${RED}● 未运行${NC}    服务: ${DIM}未配置 systemd${NC}"
        fi
    fi

    # 配置摘要
    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        echo ""
        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
        whitelist_val=$(get_yaml_val "whitelistMode" "$INSTALL_DIR/config.yaml")
        auth_val=$(get_yaml_val "basicAuthMode" "$INSTALL_DIR/config.yaml")
        ua_val=$(get_yaml_val "enableUserAccounts" "$INSTALL_DIR/config.yaml")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$INSTALL_DIR/config.yaml")
        port_val=$(get_port)

        echo -e "  监听: $(format_bool "$listen_val")  白名单: $(format_bool "$whitelist_val")  认证: $(format_bool "$auth_val")  端口: ${CYAN}${port_val}${NC}"
        echo -e "  用户账户: $(format_bool "$ua_val")  隐蔽登录: $(format_bool "$dl_val")"

        show_access_info
    fi
}

# ==================== 更新 ====================

update_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    step "更新 SillyTavern..."

    if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        warn "SillyTavern 正在运行"
        if confirm_no_default "停止并继续更新?"; then
            stop_sillytavern
        else
            info "取消更新"; return 0
        fi
    fi

    cd "$INSTALL_DIR"

    # 备份
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    info "配置已备份: $backup_dir"

    # 拉取
    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")"

    if git pull --ff-only; then
        success "代码已更新"
    else
        warn "快速合并失败，强制更新..."
        local current_branch
        current_branch=$(git branch --show-current)
        git fetch --all
        git reset --hard "origin/$current_branch"
        success "代码已强制更新"
    fi

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && \
        git remote set-url origin "$SILLYTAVERN_REPO"

    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    npm install --no-audit --no-fund 2>&1 | tail -3

    [[ -f "$backup_dir/config.yaml" ]] && cp "$backup_dir/config.yaml" "config.yaml"

    cd - >/dev/null

    success "更新完成!"

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        if confirm_no_default "立即启动?"; then
            start_sillytavern
        fi
    fi
}

# ==================== 卸载 ====================

uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"; return 1
    fi

    echo ""
    warn "⚠  即将卸载: $INSTALL_DIR"
    echo ""
    confirm_no_default "确定卸载? 不可恢复!" || { info "取消"; return 0; }
    confirm_no_default "再次确认!" || { info "取消"; return 0; }

    stop_sillytavern

    local port
    port=$(get_port)
    remove_firewall_port "$port"

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        get_sudo
        $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        $NEED_SUDO systemctl daemon-reload
        info "systemd 服务已移除"
    fi

    if [[ -d "$INSTALL_DIR/data" ]]; then
        echo ""
        if confirm_no_default "备份聊天数据和角色卡?"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            cp -r "$INSTALL_DIR/data" "$backup_path/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$backup_path/"
            success "已备份到: $backup_path"
        fi
    fi

    rm -rf "$INSTALL_DIR"
    rm -f "$KSILLY_CONF"
    success "卸载完成"

    echo ""
    if confirm_no_default "同时卸载 Node.js?"; then
        get_sudo
        case "$PKG_MANAGER" in
            apt)    $NEED_SUDO apt-get remove -y nodejs; $NEED_SUDO rm -f /etc/apt/sources.list.d/nodesource.list ;;
            yum)    $NEED_SUDO yum remove -y nodejs ;;
            dnf)    $NEED_SUDO dnf remove -y nodejs ;;
            pacman) $NEED_SUDO pacman -R --noconfirm nodejs npm ;;
        esac
        success "Node.js 已卸载"
    fi
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
        echo -e "  ${BOLD}${CYAN}配置修改${NC}"
        divider
        echo ""

        local listen_val whitelist_val auth_val port_val ua_val dl_val
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        ua_val=$(get_yaml_val "enableUserAccounts" "$config_file")
        dl_val=$(get_yaml_val "enableDiscreetLogin" "$config_file")
        port_val=$(get_port)

        # 配置概览 - 紧凑两行
        echo -e "  监听: $(format_bool "$listen_val")  白名单: $(format_bool "$whitelist_val")  认证: $(format_bool "$auth_val")  端口: ${CYAN}${port_val}${NC}"
        echo -e "  用户账户: $(format_bool "$ua_val")  隐蔽登录: $(format_bool "$dl_val")"
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 监听设置            ${DIM}listen${NC}"
        echo -e "  ${GREEN}2)${NC} 白名单模式          ${DIM}whitelistMode${NC}"
        echo -e "  ${GREEN}3)${NC} 基础认证            ${DIM}basicAuthMode${NC}"
        echo -e "  ${GREEN}4)${NC} 端口                ${DIM}port${NC}"
        echo -e "  ${GREEN}5)${NC} 用户账户系统        ${DIM}enableUserAccounts${NC}"
        echo -e "  ${GREEN}6)${NC} 隐蔽登录            ${DIM}enableDiscreetLogin${NC}"
        echo -e "  ${GREEN}7)${NC} 编辑配置文件        ${DIM}nano/vi${NC}"
        echo -e "  ${GREEN}8)${NC} 重置默认配置"
        echo -e "  ${GREEN}9)${NC} 防火墙放行管理"
        echo ""
        echo -e "  ${RED}0)${NC} 返回"
        echo ""
        divider

        local choice
        choice=$(read_input "选择")

        case "$choice" in
            1)
                echo ""
                if confirm_no_default "开启监听 (允许远程访问)?"; then
                    set_yaml_val "listen" "true" "$config_file"
                    success "监听: 开启"
                    open_firewall_port "$(get_port)"
                else
                    set_yaml_val "listen" "false" "$config_file"
                    success "监听: 关闭"
                fi
                ;;
            2)
                echo ""
                if confirm_no_default "关闭白名单模式?"; then
                    set_yaml_val "whitelistMode" "false" "$config_file"
                    success "白名单: 关闭"
                else
                    set_yaml_val "whitelistMode" "true" "$config_file"
                    success "白名单: 开启"
                fi
                ;;
            3)
                echo ""
                if confirm_no_default "开启基础认证?"; then
                    set_yaml_val "basicAuthMode" "true" "$config_file"
                    local auth_user
                    auth_user=$(read_input "认证用户名")
                    while [[ -z "$auth_user" ]]; do
                        warn "用户名不能为空"
                        auth_user=$(read_input "认证用户名")
                    done
                    local auth_pass
                    auth_pass=$(read_password "认证密码")
                    sed -i "/basicAuthUser:/,/^[^ #]/{
                        s|\([[:space:]]*\)username:.*|\1username: \"${auth_user}\"|
                        s|\([[:space:]]*\)password:.*|\1password: \"${auth_pass}\"|
                    }" "$config_file"
                    success "认证: 开启 (用户: $auth_user)"
                else
                    set_yaml_val "basicAuthMode" "false" "$config_file"
                    success "认证: 关闭"
                fi
                ;;
            4)
                echo ""
                local new_port
                new_port=$(read_input "新端口号" "${port_val}")
                if echo "$new_port" | grep -qE '^[0-9]+$' && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    set_yaml_val "port" "$new_port" "$config_file"
                    success "端口: $new_port"
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    [[ "$cur_listen" == "true" ]] && open_firewall_port "$new_port"
                else
                    error "无效端口: $new_port"
                fi
                ;;
            5)
                echo ""
                if confirm_no_default "开启用户账户系统?"; then
                    set_yaml_val "enableUserAccounts" "true" "$config_file"
                    success "用户账户: 开启"
                else
                    set_yaml_val "enableUserAccounts" "false" "$config_file"
                    success "用户账户: 关闭"
                fi
                ;;
            6)
                echo ""
                if confirm_no_default "开启隐蔽登录?"; then
                    set_yaml_val "enableDiscreetLogin" "true" "$config_file"
                    success "隐蔽登录: 开启"
                else
                    set_yaml_val "enableDiscreetLogin" "false" "$config_file"
                    success "隐蔽登录: 关闭"
                fi
                ;;
            7)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            8)
                if confirm_no_default "重置为默认配置?"; then
                    cp "$INSTALL_DIR/default.yaml" "$config_file"
                    sed -i 's/\r$//' "$config_file"
                    success "已重置"
                fi
                ;;
            9)
                echo ""
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
        echo ""
        if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            warn "需重启生效"
            if confirm_no_default "立即重启?"; then
                get_sudo
                $NEED_SUDO systemctl restart "$SERVICE_NAME"
                sleep 2
                success "已重启"
                show_access_info
            fi
        fi

        echo ""
        read -rp "  按 Enter 继续..."
    done
}

view_logs() {
    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "最近日志:"
        echo ""
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    else
        warn "未使用 systemd，无法查看日志"
    fi
}

# ==================== 完整安装 ====================

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
    configure_sillytavern
    echo ""
    setup_service
    echo ""
    save_config

    divider
    echo ""
    echo -e "  ${BOLD}${GREEN}🎉 安装完成!${NC}"

    show_access_info

    echo ""
    divider
    echo ""

    if confirm_no_default "立即启动?"; then
        start_sillytavern
    else
        echo ""
        info "启动方式:"
        if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            echo -e "    ${CYAN}sudo systemctl start ${SERVICE_NAME}${NC}"
        fi
        echo -e "    ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
    fi

    echo ""
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
                version=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')

            local is_running=false
            if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                is_running=true
            else
                local pid
                pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
                [[ -n "$pid" ]] && is_running=true
            fi

            if $is_running; then
                echo -e "  ${GREEN}●${NC} SillyTavern v${version:-?} 运行中    ${DIM}${INSTALL_DIR}${NC}"
            else
                echo -e "  ${RED}●${NC} SillyTavern v${version:-?} 已停止    ${DIM}${INSTALL_DIR}${NC}"
            fi
        else
            echo -e "  ${YELLOW}●${NC} 未安装"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装${NC}                      ${BOLD}运行${NC}"
        echo -e "  ${GREEN}1)${NC} 安装                   ${GREEN}4)${NC} 启动"
        echo -e "  ${GREEN}2)${NC} 更新                   ${GREEN}5)${NC} 停止"
        echo -e "  ${GREEN}3)${NC} 卸载                   ${GREEN}6)${NC} 重启"
        echo ""
        echo -e "  ${BOLD}配置${NC}                      ${BOLD}维护${NC}"
        echo -e "  ${GREEN}7)${NC} 修改配置               ${GREEN}9)${NC} 查看日志"
        echo -e "  ${GREEN}8)${NC} 运行状态              ${GREEN}10)${NC} 服务设置"
        echo ""
        echo -e "  ${RED} 0)${NC} 退出"
        echo ""
        divider

        local choice
        choice=$(read_input "选择")

        case "$choice" in
            1)
                if check_installed; then
                    warn "已安装: $INSTALL_DIR"
                    confirm_no_default "重新安装?" || continue
                fi
                full_install
                read -rp "  按 Enter 继续..."
                ;;
            2)
                detect_os; detect_network
                update_sillytavern
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            3)
                detect_os
                uninstall_sillytavern
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            4)
                start_sillytavern
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            5)
                stop_sillytavern
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            6)
                if ! check_installed; then
                    error "未安装"
                else
                    stop_sillytavern; sleep 1; start_sillytavern
                fi
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            7)
                modify_config_menu
                ;;
            8)
                show_status
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            9)
                view_logs
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            10)
                if ! check_installed; then
                    error "请先安装"
                else
                    detect_os; setup_service
                fi
                echo ""; read -rp "  按 Enter 继续..."
                ;;
            0)
                echo ""; info "再见~ 👋"; echo ""
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
    if [[ "$(uname)" != "Linux" && "$(uname)" != "Darwin" ]]; then
        error "仅支持 Linux 和 macOS"; exit 1
    fi

    load_config

    case "${1:-}" in
        install)   detect_os; detect_network; full_install ;;
        update)    detect_os; detect_network; load_config; update_sillytavern ;;
        start)     start_sillytavern ;;
        stop)      stop_sillytavern ;;
        restart)   stop_sillytavern; sleep 1; start_sillytavern ;;
        status)    show_status ;;
        uninstall) detect_os; uninstall_sillytavern ;;
        "")        main_menu ;;
        *)
            echo "用法: $0 {install|update|start|stop|restart|status|uninstall}"
            exit 1
            ;;
    esac
}

main "$@"
