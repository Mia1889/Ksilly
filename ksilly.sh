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
#  版本: 1.0.2
#

set -euo pipefail

# ==================== 全局常量 ====================
SCRIPT_VERSION="1.0.2"
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
    echo -e "${BOLD}  简单 SillyTavern 部署脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "${PURPLE}  作者: Mia1889 | github.com/Mia1889/Ksilly${NC}"
    echo -e "  ─────────────────────────────────────────"
    echo ""
}

info()    { echo -e "  ${GREEN}[信息]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[警告]${NC} $1"; }
error()   { echo -e "  ${RED}[错误]${NC} $1"; }
ask()     { echo -e "  ${BLUE}[询问]${NC} $1"; }
success() { echo -e "  ${GREEN}[完成]${NC} $1"; }

step() {
    echo -e "\n  ${CYAN}▶ $1${NC}"
}

divider() {
    echo -e "  ${PURPLE}─────────────────────────────────────────${NC}"
}

confirm_no_default() {
    local prompt="$1"
    local result=""
    while true; do
        echo -ne "  ${BLUE}[询问]${NC} ${prompt} (y/n): " >&2
        read -r result
        case "$result" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) echo -e "  ${YELLOW}[警告]${NC} 请输入 y 或 n" >&2 ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result=""
    if [[ -n "$default" ]]; then
        echo -ne "  ${BLUE}[输入]${NC} ${prompt} [${default}]: " >&2
    else
        echo -ne "  ${BLUE}[输入]${NC} ${prompt}: " >&2
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
        echo -ne "  ${BLUE}[输入]${NC} ${prompt}: " >&2
        read -rs result
        echo "" >&2
        if [[ -z "$result" ]]; then
            echo -e "  ${YELLOW}[警告]${NC} 密码不能为空，请重新输入" >&2
        fi
    done
    echo "$result"
}

# ==================== 新增: 安全读取配置值 ====================
# 从 config.yaml 中读取值并清除 \r、空格等脏字符

get_yaml_val() {
    local key="$1"
    local file="$2"
    grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r\n "'\'''
}

# 获取端口
get_port() {
    local port
    port=$(get_yaml_val "port" "$INSTALL_DIR/config.yaml")
    # 如果为空或不是数字则默认 8000
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        port="8000"
    fi
    echo "$port"
}

# 获取本机局域网 IP（优先级: ip route > ip addr > hostname -I）
get_local_ip() {
    local ip=""

    # 方法1: 通过默认路由的 src 获取主 IP（最准确）
    if command_exists ip; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)
    fi

    # 方法2: 从 ip addr 中提取非 127 的第一个 IPv4
    if [[ -z "$ip" ]] && command_exists ip; then
        ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    fi

    # 方法3: hostname -I
    if [[ -z "$ip" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # 方法4: ifconfig
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi

    # 最终兜底
    if [[ -z "$ip" ]]; then
        ip="<你的服务器IP>"
    fi

    echo "$ip"
}

# ==================== 新增: 防火墙管理 ====================

# 检测并放行防火墙端口
open_firewall_port() {
    local port="$1"

    get_sudo

    step "检查防火墙并放行端口 ${port}..."

    local firewall_found=false

    # ---- UFW (Ubuntu/Debian 常用) ----
    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            firewall_found=true
            info "检测到 UFW 防火墙已启用"
            if $NEED_SUDO ufw status | grep -qw "$port"; then
                info "端口 $port 已在 UFW 放行规则中"
            else
                info "正在放行端口 $port (tcp)..."
                $NEED_SUDO ufw allow "$port/tcp" >/dev/null 2>&1
                success "UFW 已放行端口 $port/tcp"
            fi
        else
            info "UFW 未启用，无需配置"
        fi
    fi

    # ---- firewalld (CentOS/RHEL/Fedora 常用) ----
    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            firewall_found=true
            info "检测到 firewalld 防火墙已启用"
            if $NEED_SUDO firewall-cmd --list-ports 2>/dev/null | grep -qw "${port}/tcp"; then
                info "端口 $port 已在 firewalld 放行规则中"
            else
                info "正在放行端口 $port (tcp)..."
                $NEED_SUDO firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
                $NEED_SUDO firewall-cmd --reload >/dev/null 2>&1
                success "firewalld 已放行端口 $port/tcp"
            fi
        else
            info "firewalld 未运行，无需配置"
        fi
    fi

    # ---- iptables (通用兜底) ----
    if [[ "$firewall_found" == false ]] && command_exists iptables; then
        # 检查 iptables 是否有 DROP/REJECT 规则 (说明在用 iptables 做防火墙)
        local has_drop
        has_drop=$($NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -cE 'DROP|REJECT' || true)
        if [[ "$has_drop" -gt 0 ]]; then
            firewall_found=true
            info "检测到 iptables 防火墙规则"
            # 检查端口是否已放行
            if $NEED_SUDO iptables -L INPUT -n 2>/dev/null | grep -qw "dpt:${port}"; then
                info "端口 $port 已在 iptables 放行规则中"
            else
                info "正在放行端口 $port (tcp)..."
                $NEED_SUDO iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
                success "iptables 已放行端口 $port/tcp"

                # 尝试持久化
                if command_exists iptables-save; then
                    if [[ -d /etc/iptables ]]; then
                        $NEED_SUDO sh -c "iptables-save > /etc/iptables/rules.v4" 2>/dev/null || true
                    elif command_exists netfilter-persistent; then
                        $NEED_SUDO netfilter-persistent save 2>/dev/null || true
                    fi
                    info "iptables 规则已尝试持久化"
                fi
            fi
        fi
    fi

    if [[ "$firewall_found" == false ]]; then
        info "未检测到活动的防火墙，无需放行端口"
    fi

    # ---- 提醒云服务器安全组 ----
    echo ""
    warn "如果您使用的是云服务器 (阿里云/腾讯云/AWS 等)"
    warn "请确保在云控制台的安全组中也放行了端口 ${port}/tcp"
}

# ==================== 其余工具函数 ====================

load_config() {
    if [[ -f "$KSILLY_CONF" ]]; then
        source "$KSILLY_CONF"
        INSTALL_DIR="${KSILLY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    else
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    fi
}

save_config() {
    cat > "$KSILLY_CONF" <<EOF
# Ksilly 配置文件 - 请勿手动修改
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
            error "需要 root 权限但未找到 sudo，请以 root 用户运行"
            exit 1
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
            info "检测到 Debian/Ubuntu 系发行版 ($OS_TYPE)"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            command_exists dnf && PKG_MANAGER="dnf"
            info "检测到 RHEL/CentOS 系发行版 ($OS_TYPE)"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            info "检测到 Arch 系发行版 ($OS_TYPE)"
            ;;
        alpine)
            PKG_MANAGER="apk"
            info "检测到 Alpine Linux"
            ;;
        macos)
            PKG_MANAGER="brew"
            info "检测到 macOS"
            ;;
        *)
            warn "未能识别的操作系统: $OS_TYPE"
            warn "脚本将尝试继续运行，但可能会失败"
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
        info "检测到您位于中国大陆网络环境"
        info "将自动启用 GitHub 加速和 npm 镜像"
        find_github_proxy
    else
        IS_CHINA=false
        info "检测到国际网络环境，直连 GitHub"
    fi
}

find_github_proxy() {
    info "正在测试 GitHub 代理可用性..."
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local test_url="${proxy}https://github.com/SillyTavern/SillyTavern/raw/release/package.json"
        if curl -s --connect-timeout 5 --max-time 10 "$test_url" &>/dev/null; then
            GITHUB_PROXY="$proxy"
            success "找到可用代理: $proxy"
            return 0
        fi
    done
    warn "未找到可用的 GitHub 代理，将尝试直连"
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
    info "更新软件包缓存..."
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
        local git_ver
        git_ver=$(git --version | awk '{print $3}')
        info "Git 已安装 (版本: $git_ver)"
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
        *)      error "不支持的包管理器，请手动安装 git"; exit 1 ;;
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
        info "Node.js 已安装 (版本: $(node -v))，满足最低要求 (v${MIN_NODE_VERSION}+)"
        return 0
    fi

    command_exists node && warn "当前 Node.js 版本 $(node -v) 过低，需要 v${MIN_NODE_VERSION}+，将进行升级"

    step "安装 Node.js v20.x..."

    if [[ "$IS_CHINA" == true ]]; then
        install_nodejs_china
    else
        install_nodejs_standard
    fi

    hash -r 2>/dev/null || true

    if check_node_version; then
        success "Node.js $(node -v) 安装完成"
        success "npm $(npm -v) 已就绪"
    else
        error "Node.js 安装失败或版本不满足要求"
        exit 1
    fi

    if [[ "$IS_CHINA" == true ]]; then
        info "配置 npm 镜像为 npmmirror..."
        npm config set registry https://registry.npmmirror.com
        success "npm 镜像已设置"
    fi
}

install_nodejs_standard() {
    case "$PKG_MANAGER" in
        apt)
            info "通过 NodeSource 安装 Node.js 20.x..."
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
    info "从 npmmirror 下载 Node.js 二进制文件..."
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
        *) error "不支持的CPU架构: $(uname -m)"; exit 1 ;;
    esac

    local filename="node-${node_ver}-linux-${arch}.tar.xz"
    local download_url="${mirror}/${node_ver}/${filename}"
    info "下载地址: $download_url"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if curl -fSL --progress-bar -o "${tmp_dir}/${filename}" "$download_url"; then
        info "解压并安装..."
        cd "$tmp_dir"
        tar xf "$filename"
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib,share} /usr/local/ 2>/dev/null || \
        $NEED_SUDO cp -rf "node-${node_ver}-linux-${arch}"/{bin,include,lib} /usr/local/
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
    step "安装系统依赖..."

    get_sudo
    update_pkg_cache

    info "安装基础工具 (curl, wget, tar)..."
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
    step "克隆 SillyTavern 仓库..."

    INSTALL_DIR=$(read_input "请输入安装目录" "$DEFAULT_INSTALL_DIR")

    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/server.js" || -f "$INSTALL_DIR/start.sh" ]]; then
            warn "目录 $INSTALL_DIR 已存在 SillyTavern 安装"
            if confirm_no_default "是否删除现有安装并重新安装?"; then
                rm -rf "$INSTALL_DIR"
            else
                info "保留现有安装，跳过克隆"
                return 0
            fi
        else
            error "目录 $INSTALL_DIR 已存在且不是 SillyTavern 目录"
            exit 1
        fi
    fi

    echo ""
    ask "请选择要安装的分支:"
    echo -e "    ${GREEN}1)${NC} release  - 稳定版 (推荐)"
    echo -e "    ${YELLOW}2)${NC} staging  - 开发版 (最新功能)"
    echo ""
    local branch_choice=""
    while [[ "$branch_choice" != "1" && "$branch_choice" != "2" ]]; do
        branch_choice=$(read_input "请选择 (1/2)")
    done

    local branch="release"
    [[ "$branch_choice" == "2" ]] && branch="staging"
    info "选择分支: $branch"

    local repo_url
    repo_url=$(get_github_url "$SILLYTAVERN_REPO")
    info "克隆地址: $repo_url"

    if git clone -b "$branch" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR"; then
        success "SillyTavern 仓库克隆完成"
    else
        if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
            warn "代理克隆失败，尝试直连..."
            if git clone -b "$branch" --single-branch --depth 1 "$SILLYTAVERN_REPO" "$INSTALL_DIR"; then
                success "SillyTavern 仓库克隆完成 (直连)"
            else
                error "克隆失败，请检查网络连接"; exit 1
            fi
        else
            error "克隆失败，请检查网络连接"; exit 1
        fi
    fi

    # 修复 YAML 文件的 Windows 换行符
    step "规范化配置文件..."
    if command_exists dos2unix; then
        find "$INSTALL_DIR" -name "*.yaml" -exec dos2unix {} \; 2>/dev/null || true
    else
        find "$INSTALL_DIR" -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    fi
    success "配置文件已规范化"

    step "安装 npm 依赖..."
    cd "$INSTALL_DIR"
    if npm install --no-audit --no-fund 2>&1 | tail -5; then
        success "npm 依赖安装完成"
    else
        error "npm 依赖安装失败"; exit 1
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
            # 清除可能的 \r
            sed -i 's/\r$//' "$config_file"
            info "已从 default.yaml 生成 config.yaml"
        else
            error "未找到 default.yaml，无法生成配置"; exit 1
        fi
    fi

    echo ""
    divider
    echo -e "  ${BOLD}${CYAN}SillyTavern 配置向导${NC}"
    divider
    echo ""

    # --- 1. 监听 ---
    echo -e "  ${YELLOW}● 监听设置${NC}"
    echo -e "    开启后 SillyTavern 将监听所有网络接口 (0.0.0.0)"
    echo -e "    允许局域网内其他设备或外网访问"
    echo -e "    关闭则仅本机可访问 (127.0.0.1)"
    echo ""
    local listen_enabled=false
    if confirm_no_default "是否开启监听 (允许远程访问)?"; then
        sed -i 's/^\( *\)listen:.*/\1listen: true/' "$config_file"
        listen_enabled=true
        success "已开启监听"
    else
        sed -i 's/^\( *\)listen:.*/\1listen: false/' "$config_file"
        info "保持仅本机访问"
    fi

    # --- 端口 ---
    echo ""
    local port
    port=$(read_input "请设置端口号" "8000")
    sed -i "s/^\( *\)port:.*/\1port: ${port}/" "$config_file"
    info "端口设置为: $port"

    # --- 2. 白名单 ---
    echo ""
    echo -e "  ${YELLOW}● 白名单模式${NC}"
    echo -e "    开启后仅白名单中的 IP 可以访问"
    echo -e "    如需远程访问，建议关闭白名单模式"
    echo ""
    if confirm_no_default "是否关闭白名单模式 (whitelistMode)?"; then
        sed -i 's/^\( *\)whitelistMode:.*/\1whitelistMode: false/' "$config_file"
        success "已关闭白名单模式"
    else
        sed -i 's/^\( *\)whitelistMode:.*/\1whitelistMode: true/' "$config_file"
        info "保持白名单模式开启"
    fi

    # --- 3. 基础认证 ---
    echo ""
    echo -e "  ${YELLOW}● 基础认证 (basicAuth)${NC}"
    echo -e "    开启后访问 SillyTavern 需要输入用户名和密码"
    echo -e "    如开启了远程访问，${RED}强烈建议${NC}开启基础认证"
    echo ""
    if confirm_no_default "是否开启基础认证 (basicAuthMode)?"; then
        sed -i 's/^\( *\)basicAuthMode:.*/\1basicAuthMode: true/' "$config_file"

        echo ""
        local auth_user
        auth_user=$(read_input "请设置认证用户名")
        while [[ -z "$auth_user" ]]; do
            warn "用户名不能为空"
            auth_user=$(read_input "请设置认证用户名")
        done

        local auth_pass
        auth_pass=$(read_password "请设置认证密码")

        sed -i "/basicAuthUser:/,/^[^ #]/{
            s/\( *\)username:.*/\1username: \"${auth_user}\"/
            s/\( *\)password:.*/\1password: \"${auth_pass}\"/
        }" "$config_file"

        success "基础认证已开启"
        info "用户名: $auth_user"
        info "密码: ********"
    else
        sed -i 's/^\( *\)basicAuthMode:.*/\1basicAuthMode: false/' "$config_file"
        info "基础认证保持关闭"
    fi

    # --- 4. 防火墙 (仅在开启监听时) ---
    if [[ "$listen_enabled" == true ]]; then
        echo ""
        open_firewall_port "$port"
    fi

    echo ""
    success "配置文件已保存到: $config_file"
}

setup_service() {
    echo ""
    divider
    echo -e "  ${BOLD}${CYAN}后台运行与开机自启设置${NC}"
    divider
    echo ""

    if ! command_exists systemctl; then
        warn "当前系统不支持 systemd，无法设置后台运行和开机自启"
        warn "您可以手动使用 screen/tmux 来保持后台运行"
        return 0
    fi

    local enable_service=false
    local enable_autostart=false

    echo -e "  ${YELLOW}● 后台运行${NC}"
    echo -e "    开启后 SillyTavern 将以系统服务方式在后台运行"
    echo -e "    关闭终端也不会停止运行"
    echo ""
    if confirm_no_default "是否开启后台运行 (systemd 服务)?"; then
        enable_service=true
    fi

    if [[ "$enable_service" == true ]]; then
        echo ""
        echo -e "  ${YELLOW}● 开机自启动${NC}"
        echo -e "    开启后系统重启时自动启动 SillyTavern"
        echo ""
        if confirm_no_default "是否开启开机自启动?"; then
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
        success "systemd 服务创建完成"

        if [[ "$enable_autostart" == true ]]; then
            $NEED_SUDO systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
            success "开机自启动已开启"
        else
            $NEED_SUDO systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
            info "开机自启动未开启"
        fi
    fi
}

# 显示访问地址信息
show_access_info() {
    local port
    port=$(get_port)

    local listen_mode
    listen_mode=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")

    echo ""
    if [[ "$listen_mode" == "true" ]]; then
        local ip_addr
        ip_addr=$(get_local_ip)
        info "本地访问: http://127.0.0.1:${port}"
        info "远程访问: http://${ip_addr}:${port}"
    else
        info "访问地址: http://127.0.0.1:${port}"
    fi
}

start_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "通过 systemd 启动 SillyTavern..."
        get_sudo
        $NEED_SUDO systemctl start "$SERVICE_NAME"
        sleep 2

        if $NEED_SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
            success "SillyTavern 已成功启动!"
            show_access_info
        else
            error "启动失败，查看日志: journalctl -u $SERVICE_NAME -n 20"
        fi
    else
        local port
        port=$(get_port)
        step "前台启动 SillyTavern..."
        info "访问地址: http://127.0.0.1:${port}"
        info "按 Ctrl+C 停止运行"
        echo ""
        cd "$INSTALL_DIR"
        node server.js
        cd - >/dev/null
    fi
}

stop_sillytavern() {
    if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "停止 SillyTavern 服务..."
        get_sudo
        $NEED_SUDO systemctl stop "$SERVICE_NAME"
        success "SillyTavern 已停止"
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            step "停止 SillyTavern 进程 (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
            success "SillyTavern 已停止"
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

show_status() {
    step "SillyTavern 运行状态"
    echo ""

    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    info "安装目录: $INSTALL_DIR"

    if [[ -f "$INSTALL_DIR/package.json" ]]; then
        local version
        version=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')
        info "版本: $version"
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        local branch
        branch=$(cd "$INSTALL_DIR" && git branch --show-current 2>/dev/null || echo "未知")
        info "分支: $branch"
    fi

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        info "Systemd 服务状态:"
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "    运行状态: ${GREEN}● 运行中${NC}"
        else
            echo -e "    运行状态: ${RED}● 已停止${NC}"
        fi
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "    开机自启: ${GREEN}● 已启用${NC}"
        else
            echo -e "    开机自启: ${YELLOW}● 未启用${NC}"
        fi
    else
        local pid
        pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            echo -e "    运行状态: ${GREEN}● 运行中${NC} (PID: $pid)"
        else
            echo -e "    运行状态: ${RED}● 未运行${NC}"
        fi
        echo -e "    服务模式: ${YELLOW}未配置 systemd 服务${NC}"
    fi

    if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
        echo ""
        info "当前配置:"
        local listen_val whitelist_val auth_val port_val
        listen_val=$(get_yaml_val "listen" "$INSTALL_DIR/config.yaml")
        whitelist_val=$(get_yaml_val "whitelistMode" "$INSTALL_DIR/config.yaml")
        auth_val=$(get_yaml_val "basicAuthMode" "$INSTALL_DIR/config.yaml")
        port_val=$(get_port)

        echo -e "    监听所有接口: $(format_bool "$listen_val")"
        echo -e "    白名单模式:   $(format_bool "$whitelist_val")"
        echo -e "    基础认证:     $(format_bool "$auth_val")"
        echo -e "    端口:         ${CYAN}${port_val}${NC}"

        show_access_info
    fi
}

update_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    step "更新 SillyTavern..."

    if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        warn "检测到 SillyTavern 正在运行，需要先停止"
        if confirm_no_default "是否停止 SillyTavern 并继续更新?"; then
            stop_sillytavern
        else
            info "已取消更新"
            return 0
        fi
    fi

    cd "$INSTALL_DIR"

    info "备份配置文件..."
    local backup_dir="$HOME/.ksilly_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    [[ -f "config.yaml" ]] && cp "config.yaml" "$backup_dir/"
    success "配置已备份到: $backup_dir"

    info "拉取最新代码..."

    if [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]]; then
        git remote set-url origin "$(get_github_url "$SILLYTAVERN_REPO")"
    fi

    if git pull --ff-only; then
        success "代码更新完成"
    else
        warn "快速合并失败，尝试强制更新..."
        local current_branch
        current_branch=$(git branch --show-current)
        git fetch --all
        git reset --hard "origin/$current_branch"
        success "代码强制更新完成"
    fi

    [[ "$IS_CHINA" == true && -n "$GITHUB_PROXY" ]] && git remote set-url origin "$SILLYTAVERN_REPO"

    # 规范化换行符
    find . -name "*.yaml" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

    info "更新 npm 依赖..."
    npm install --no-audit --no-fund 2>&1 | tail -3

    if [[ -f "$backup_dir/config.yaml" ]]; then
        cp "$backup_dir/config.yaml" "config.yaml"
        success "配置文件已恢复"
    fi

    cd - >/dev/null

    success "SillyTavern 更新完成!"

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        echo ""
        if confirm_no_default "是否立即启动 SillyTavern?"; then
            start_sillytavern
        fi
    fi
}

uninstall_sillytavern() {
    if ! check_installed; then
        error "SillyTavern 未安装"
        return 1
    fi

    echo ""
    warn "⚠  即将卸载 SillyTavern"
    warn "安装目录: $INSTALL_DIR"
    echo ""

    confirm_no_default "确定要卸载 SillyTavern 吗? 此操作不可恢复!" || { info "已取消卸载"; return 0; }
    echo ""
    confirm_no_default "再次确认: 真的要删除所有数据吗?" || { info "已取消卸载"; return 0; }

    stop_sillytavern

    # 移除防火墙规则
    local port
    port=$(get_port)
    remove_firewall_port "$port"

    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "移除 systemd 服务..."
        get_sudo
        $NEED_SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        $NEED_SUDO rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        $NEED_SUDO systemctl daemon-reload
        success "systemd 服务已移除"
    fi

    local data_dir="$INSTALL_DIR/data"
    if [[ -d "$data_dir" ]]; then
        echo ""
        if confirm_no_default "是否备份聊天数据和角色卡?"; then
            local backup_path="$HOME/SillyTavern_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_path"
            cp -r "$data_dir" "$backup_path/"
            [[ -f "$INSTALL_DIR/config.yaml" ]] && cp "$INSTALL_DIR/config.yaml" "$backup_path/"
            success "数据已备份到: $backup_path"
        fi
    fi

    step "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    success "安装目录已删除"

    rm -f "$KSILLY_CONF"
    success "Ksilly 配置已清理"

    echo ""
    success "SillyTavern 卸载完成!"

    if confirm_no_default "是否同时卸载 Node.js?"; then
        step "卸载 Node.js..."
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

# 移除防火墙端口 (卸载时调用)
remove_firewall_port() {
    local port="$1"
    get_sudo

    if command_exists ufw; then
        local ufw_status
        ufw_status=$($NEED_SUDO ufw status 2>/dev/null | head -1 || true)
        if echo "$ufw_status" | grep -qi "active"; then
            $NEED_SUDO ufw delete allow "$port/tcp" 2>/dev/null || true
            info "已从 UFW 移除端口 $port 规则"
        fi
    fi

    if command_exists firewall-cmd; then
        local fwd_state
        fwd_state=$($NEED_SUDO firewall-cmd --state 2>/dev/null || true)
        if [[ "$fwd_state" == "running" ]]; then
            $NEED_SUDO firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null || true
            $NEED_SUDO firewall-cmd --reload 2>/dev/null || true
            info "已从 firewalld 移除端口 $port 规则"
        fi
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
        error "SillyTavern 未安装，请先安装"
        return 1
    fi

    local config_file="$INSTALL_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        error "配置文件不存在: $config_file"
        return 1
    fi

    while true; do
        print_banner
        echo -e "  ${BOLD}${CYAN}配置修改菜单${NC}"
        divider
        echo ""

        local listen_val whitelist_val auth_val port_val
        listen_val=$(get_yaml_val "listen" "$config_file")
        whitelist_val=$(get_yaml_val "whitelistMode" "$config_file")
        auth_val=$(get_yaml_val "basicAuthMode" "$config_file")
        port_val=$(get_port)

        echo -e "  当前配置:"
        echo -e "    监听: $(format_bool "$listen_val")  |  白名单: $(format_bool "$whitelist_val")  |  认证: $(format_bool "$auth_val")  |  端口: ${CYAN}${port_val}${NC}"
        echo ""
        divider
        echo ""
        echo -e "  ${GREEN}1)${NC} 修改监听设置         (listen)"
        echo -e "  ${GREEN}2)${NC} 修改白名单模式       (whitelistMode)"
        echo -e "  ${GREEN}3)${NC} 修改基础认证设置     (basicAuthMode)"
        echo -e "  ${GREEN}4)${NC} 修改端口             (port)"
        echo -e "  ${GREEN}5)${NC} 编辑完整配置文件     (使用 nano/vi)"
        echo -e "  ${GREEN}6)${NC} 重置为默认配置"
        echo -e "  ${GREEN}7)${NC} 防火墙放行管理"
        echo ""
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        divider

        local choice
        choice=$(read_input "请选择操作")

        case "$choice" in
            1)
                echo ""
                if confirm_no_default "是否开启监听 (允许远程访问)?"; then
                    sed -i 's/^\( *\)listen:.*/\1listen: true/' "$config_file"
                    success "已开启监听"
                    echo ""
                    local current_port
                    current_port=$(get_port)
                    open_firewall_port "$current_port"
                else
                    sed -i 's/^\( *\)listen:.*/\1listen: false/' "$config_file"
                    success "已关闭监听"
                fi
                ;;
            2)
                echo ""
                if confirm_no_default "是否关闭白名单模式?"; then
                    sed -i 's/^\( *\)whitelistMode:.*/\1whitelistMode: false/' "$config_file"
                    success "已关闭白名单模式"
                else
                    sed -i 's/^\( *\)whitelistMode:.*/\1whitelistMode: true/' "$config_file"
                    success "已开启白名单模式"
                fi
                ;;
            3)
                echo ""
                if confirm_no_default "是否开启基础认证?"; then
                    sed -i 's/^\( *\)basicAuthMode:.*/\1basicAuthMode: true/' "$config_file"
                    local auth_user
                    auth_user=$(read_input "请设置认证用户名")
                    while [[ -z "$auth_user" ]]; do
                        warn "用户名不能为空"
                        auth_user=$(read_input "请设置认证用户名")
                    done
                    local auth_pass
                    auth_pass=$(read_password "请设置认证密码")
                    sed -i "/basicAuthUser:/,/^[^ #]/{
                        s/\( *\)username:.*/\1username: \"${auth_user}\"/
                        s/\( *\)password:.*/\1password: \"${auth_pass}\"/
                    }" "$config_file"
                    success "基础认证已开启 (用户: $auth_user)"
                else
                    sed -i 's/^\( *\)basicAuthMode:.*/\1basicAuthMode: false/' "$config_file"
                    success "已关闭基础认证"
                fi
                ;;
            4)
                echo ""
                local new_port
                new_port=$(read_input "请输入新端口号" "${port_val}")
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    sed -i "s/^\( *\)port:.*/\1port: ${new_port}/" "$config_file"
                    success "端口已修改为: $new_port"
                    # 如果开启了监听，自动放行新端口
                    local cur_listen
                    cur_listen=$(get_yaml_val "listen" "$config_file")
                    if [[ "$cur_listen" == "true" ]]; then
                        open_firewall_port "$new_port"
                    fi
                else
                    error "无效的端口号: $new_port"
                fi
                ;;
            5)
                local editor="nano"
                command_exists nano || editor="vi"
                $editor "$config_file"
                ;;
            6)
                if confirm_no_default "确定要重置配置为默认值吗?"; then
                    cp "$INSTALL_DIR/default.yaml" "$config_file"
                    sed -i 's/\r$//' "$config_file"
                    success "配置已重置为默认值"
                fi
                ;;
            7)
                echo ""
                local fw_port
                fw_port=$(get_port)
                open_firewall_port "$fw_port"
                ;;
            0)
                return 0
                ;;
            *)
                warn "无效选项"
                ;;
        esac

        echo ""
        if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            warn "配置修改后需要重启 SillyTavern 才能生效"
            if confirm_no_default "是否立即重启?"; then
                get_sudo
                $NEED_SUDO systemctl restart "$SERVICE_NAME"
                sleep 2
                success "SillyTavern 已重启"
            fi
        fi

        echo ""
        read -rp "  按 Enter 继续..."
    done
}

view_logs() {
    if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
        step "SillyTavern 最近日志 (按 q 退出):"
        echo ""
        journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    else
        warn "未使用 systemd 服务，无法查看日志"
    fi
}

# ==================== 完整安装流程 ====================

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
    echo -e "  ${BOLD}${GREEN}🎉 SillyTavern 安装完成!${NC}"
    echo ""
    info "安装目录: $INSTALL_DIR"

    show_access_info

    echo ""
    divider
    echo ""

    if confirm_no_default "是否立即启动 SillyTavern?"; then
        start_sillytavern
    else
        echo ""
        info "稍后可通过以下方式启动:"
        if command_exists systemctl && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null 2>&1; then
            echo -e "    ${CYAN}sudo systemctl start ${SERVICE_NAME}${NC}"
        fi
        echo -e "    ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
        echo -e "    或重新运行此脚本选择启动"
    fi

    echo ""
}

# ==================== 主菜单 ====================

main_menu() {
    while true; do
        print_banner
        load_config

        if check_installed; then
            local version=""
            [[ -f "$INSTALL_DIR/package.json" ]] && \
                version=$(grep '"version"' "$INSTALL_DIR/package.json" | head -1 | sed 's/.*"version".*"\(.*\)".*/\1/')

            local status_icon="${RED}●${NC}"
            if command_exists systemctl && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                status_icon="${GREEN}●${NC}"
            else
                local pid
                pid=$(pgrep -f "node.*server\.js" 2>/dev/null | head -1 || true)
                [[ -n "$pid" ]] && status_icon="${GREEN}●${NC}"
            fi
            echo -e "  状态: ${status_icon} SillyTavern v${version:-未知} | 目录: ${INSTALL_DIR}"
        else
            echo -e "  状态: ${YELLOW}● 未安装${NC}"
        fi
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}安装与管理${NC}"
        echo -e "  ${GREEN} 1)${NC}  安装 SillyTavern"
        echo -e "  ${GREEN} 2)${NC}  更新 SillyTavern"
        echo -e "  ${GREEN} 3)${NC}  卸载 SillyTavern"
        echo ""
        echo -e "  ${BOLD}运行控制${NC}"
        echo -e "  ${GREEN} 4)${NC}  启动 SillyTavern"
        echo -e "  ${GREEN} 5)${NC}  停止 SillyTavern"
        echo -e "  ${GREEN} 6)${NC}  重启 SillyTavern"
        echo -e "  ${GREEN} 7)${NC}  查看运行状态"
        echo ""
        echo -e "  ${BOLD}配置与维护${NC}"
        echo -e "  ${GREEN} 8)${NC}  修改配置"
        echo -e "  ${GREEN} 9)${NC}  查看日志"
        echo -e "  ${GREEN}10)${NC}  后台运行/开机自启设置"
        echo ""
        echo -e "  ${RED} 0)${NC}  退出"
        echo ""
        divider

        local choice
        choice=$(read_input "请选择操作")

        case "$choice" in
            1)
                if check_installed; then
                    warn "SillyTavern 已安装在 $INSTALL_DIR"
                    confirm_no_default "是否重新安装?" || continue
                fi
                full_install
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            2)
                detect_os; detect_network
                update_sillytavern
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            3)
                detect_os
                uninstall_sillytavern
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            4)
                start_sillytavern
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            5)
                stop_sillytavern
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            6)
                if ! check_installed; then
                    error "SillyTavern 未安装"
                else
                    step "重启 SillyTavern..."
                    stop_sillytavern
                    sleep 1
                    start_sillytavern
                fi
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            7)
                show_status
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            8)
                modify_config_menu
                ;;
            9)
                view_logs
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            10)
                if ! check_installed; then
                    error "SillyTavern 未安装，请先安装"
                else
                    detect_os
                    setup_service
                fi
                echo ""
                read -rp "  按 Enter 继续..."
                ;;
            0)
                echo ""
                info "感谢使用 Ksilly! 再见~ 👋"
                echo ""
                exit 0
                ;;
            *)
                warn "无效选项: $choice"
                sleep 1
                ;;
        esac
    done
}

# ==================== 入口 ====================

main() {
    if [[ "$(uname)" != "Linux" && "$(uname)" != "Darwin" ]]; then
        error "此脚本仅支持 Linux 和 macOS"
        exit 1
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
            echo "  不带参数则进入交互式菜单"
            exit 1
            ;;
    esac
}

main "$@"
