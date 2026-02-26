#!/bin/bash

#=============================================================================
#  Ksilly - 简单SillyTavern部署脚本
#  版本: 1.0.0
#  描述: 傻瓜式一键部署 SillyTavern，支持中国大陆网络加速
#=============================================================================

set -e

# ======================== 颜色定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ======================== 全局变量 ========================
INSTALL_DIR="/opt/SillyTavern"
SERVICE_NAME="sillytavern"
IS_CHINA=false
OS_TYPE=""
PKG_MANAGER=""
LISTEN_ADDRESS="127.0.0.1"
LISTEN_PORT="8000"
WHITELIST_MODE=true
BASIC_AUTH_MODE=false
AUTH_USERNAME=""
AUTH_PASSWORD=""
ENABLE_SERVICE=false
ENABLE_AUTOSTART=false
CURRENT_USER=$(whoami)
ACTUAL_USER=${SUDO_USER:-$CURRENT_USER}
ACTUAL_HOME=$(eval echo ~${ACTUAL_USER})
NODE_MAJOR_VERSION=20
GIT_MIRROR=""
NPM_MIRROR=""
GITHUB_PROXY=""
BRANCH="release"

# ======================== 工具函数 ========================

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
 ██╗  ██╗███████╗██╗██╗     ██╗  ██╗   ██╗
 ██║ ██╔╝██╔════╝██║██║     ██║  ╚██╗ ██╔╝
 █████╔╝ ███████╗██║██║     ██║   ╚████╔╝
 ██╔═██╗ ╚════██║██║██║     ██║    ╚██╔╝
 ██║  ██╗███████║██║███████╗███████╗██║
 ╚═╝  ╚═╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝
EOF
    echo -e "${WHITE}  简单 SillyTavern 部署脚本 v1.0.0${NC}"
    echo -e "${PURPLE}  ─────────────────────────────────────${NC}"
    echo ""
}

log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

confirm() {
    local prompt="$1"
    local default="$2"
    local result

    if [ "$default" = "Y" ]; then
        prompt="${prompt} [Y/n]: "
    elif [ "$default" = "N" ]; then
        prompt="${prompt} [y/N]: "
    else
        prompt="${prompt} [y/n]: "
    fi

    while true; do
        echo -ne "${WHITE}${prompt}${NC}"
        read -r result
        result=${result:-$default}
        case "$result" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo -e "${RED}请输入 y 或 n${NC}" ;;
        esac
    done
}

read_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        echo -ne "${WHITE}${prompt} [默认: ${default}]: ${NC}"
    else
        echo -ne "${WHITE}${prompt}: ${NC}"
    fi
    read -r result
    echo "${result:-$default}"
}

read_password() {
    local prompt="$1"
    local result

    echo -ne "${WHITE}${prompt}: ${NC}"
    read -rs result
    echo ""
    echo "$result"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        local c=${spin:i++%${#spin}:1}
        echo -ne "\r${CYAN}  ${c} ${msg}...${NC}"
        sleep 0.1
    done
    echo -ne "\r\033[K"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ======================== 系统检测 ========================

detect_os() {
    log_step "检测操作系统"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE=$ID
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="centos"
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
    else
        OS_TYPE="unknown"
    fi

    case "$OS_TYPE" in
        ubuntu|debian|linuxmint|pop)
            PKG_MANAGER="apt"
            log_info "检测到系统: ${OS_TYPE} (Debian系)"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            if command_exists dnf; then
                PKG_MANAGER="dnf"
            fi
            log_info "检测到系统: ${OS_TYPE} (RedHat系)"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            log_info "检测到系统: ${OS_TYPE} (Arch系)"
            ;;
        opensuse*|sles)
            PKG_MANAGER="zypper"
            log_info "检测到系统: ${OS_TYPE} (SUSE系)"
            ;;
        alpine)
            PKG_MANAGER="apk"
            log_info "检测到系统: ${OS_TYPE} (Alpine)"
            ;;
        macos)
            PKG_MANAGER="brew"
            log_info "检测到系统: macOS"
            ;;
        *)
            log_error "不支持的操作系统: ${OS_TYPE}"
            log_info "支持的系统: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch, Alpine, macOS"
            exit 1
            ;;
    esac
}

# ======================== 网络环境检测 ========================

detect_network() {
    log_step "检测网络环境"

    log_info "正在检测网络环境，请稍候..."

    # 方法1: 通过访问国内外网站的响应时间判断
    local china_score=0

    # 测试能否直接访问 Google
    if ! curl -s --connect-timeout 3 --max-time 5 https://www.google.com > /dev/null 2>&1; then
        china_score=$((china_score + 1))
    fi

    # 测试能否快速访问 GitHub
    local github_time
    github_time=$(curl -o /dev/null -s -w '%{time_total}' --connect-timeout 5 --max-time 10 https://github.com 2>/dev/null || echo "999")
    if (( $(echo "$github_time > 3" | bc -l 2>/dev/null || echo 1) )); then
        china_score=$((china_score + 1))
    fi

    # 测试能否快速访问百度
    if curl -s --connect-timeout 3 --max-time 5 https://www.baidu.com > /dev/null 2>&1; then
        china_score=$((china_score + 1))
    fi

    # 测试 IP 归属地
    local ip_info
    ip_info=$(curl -s --connect-timeout 5 --max-time 8 https://ipinfo.io/country 2>/dev/null || echo "")
    if [ "$ip_info" = "CN" ]; then
        china_score=$((china_score + 2))
    fi

    # 备用方案检测
    if [ -z "$ip_info" ]; then
        ip_info=$(curl -s --connect-timeout 5 --max-time 8 https://myip.ipip.net 2>/dev/null || echo "")
        if echo "$ip_info" | grep -q "中国"; then
            china_score=$((china_score + 2))
        fi
    fi

    if [ $china_score -ge 2 ]; then
        IS_CHINA=true
        log_warn "检测到您位于中国大陆网络环境"
        log_info "将自动启用加速镜像源"
        setup_china_mirrors
    else
        IS_CHINA=false
        log_info "检测到您位于海外/可直连网络环境"
        log_info "将使用默认源"
    fi
}

setup_china_mirrors() {
    echo ""
    log_info "配置中国大陆加速镜像..."

    # GitHub 加速代理（多个备选）
    local proxies=(
        "https://ghproxy.cn"
        "https://mirror.ghproxy.com"
        "https://gh-proxy.com"
        "https://github.moeyy.xyz"
    )

    # 测试哪个代理可用
    for proxy in "${proxies[@]}"; do
        if curl -s --connect-timeout 3 --max-time 5 "${proxy}" > /dev/null 2>&1; then
            GITHUB_PROXY="${proxy}"
            log_info "GitHub 加速代理: ${GITHUB_PROXY}"
            break
        fi
    done

    if [ -z "$GITHUB_PROXY" ]; then
        log_warn "未找到可用的 GitHub 加速代理，将尝试直连"
        # 尝试使用 gitee 镜像或 gitclone
        GITHUB_PROXY=""
    fi

    # NPM 镜像源
    NPM_MIRROR="https://registry.npmmirror.com"
    log_info "NPM 镜像源: ${NPM_MIRROR}"

    # Git 镜像
    GIT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn"
    log_info "系统镜像源: 清华大学镜像"

    echo ""
}

# ======================== 依赖安装 ========================

update_package_manager() {
    log_info "更新软件包索引..."

    case "$PKG_MANAGER" in
        apt)
            # 如果在中国，先更换 apt 源
            if [ "$IS_CHINA" = true ]; then
                setup_apt_china_mirror
            fi
            apt-get update -qq > /dev/null 2>&1
            ;;
        yum|dnf)
            if [ "$IS_CHINA" = true ]; then
                setup_yum_china_mirror
            fi
            $PKG_MANAGER makecache -q > /dev/null 2>&1 || true
            ;;
        pacman)
            pacman -Sy --noconfirm > /dev/null 2>&1
            ;;
        apk)
            if [ "$IS_CHINA" = true ]; then
                setup_apk_china_mirror
            fi
            apk update > /dev/null 2>&1
            ;;
        zypper)
            zypper refresh > /dev/null 2>&1
            ;;
    esac
}

setup_apt_china_mirror() {
    local sources_file="/etc/apt/sources.list"
    local codename

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        codename=$VERSION_CODENAME
    fi

    if [ -z "$codename" ]; then
        return
    fi

    # 备份原始源
    if [ ! -f "${sources_file}.bak.ksilly" ]; then
        cp "$sources_file" "${sources_file}.bak.ksilly" 2>/dev/null || true
        log_info "已备份原始 apt 源到 ${sources_file}.bak.ksilly"
    fi

    case "$OS_TYPE" in
        ubuntu)
            cat > "$sources_file" << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-security main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-backports main restricted universe multiverse
EOF
            ;;
        debian)
            cat > "$sources_file" << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename} main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename}-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security ${codename}-security main contrib non-free
EOF
            ;;
    esac
}

setup_yum_china_mirror() {
    case "$OS_TYPE" in
        centos|rhel)
            if [ -f /etc/yum.repos.d/CentOS-Base.repo ] && [ ! -f /etc/yum.repos.d/CentOS-Base.repo.bak.ksilly ]; then
                cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak.ksilly
                # 使用清华源
                sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true
                sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g' /etc/yum.repos.d/CentOS-*.repo 2>/dev/null || true
            fi
            ;;
    esac
}

setup_apk_china_mirror() {
    if [ ! -f /etc/apk/repositories.bak.ksilly ]; then
        cp /etc/apk/repositories /etc/apk/repositories.bak.ksilly 2>/dev/null || true
    fi
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
}

install_basic_deps() {
    log_step "安装基础依赖"

    local deps_to_install=()
    local need_curl=false
    local need_wget=false

    if ! command_exists curl; then
        need_curl=true
        deps_to_install+=("curl")
    fi
    if ! command_exists wget; then
        need_wget=true
        deps_to_install+=("wget")
    fi
    if ! command_exists bc; then
        deps_to_install+=("bc")
    fi
    if ! command_exists tar; then
        deps_to_install+=("tar")
    fi

    if [ ${#deps_to_install[@]} -gt 0 ]; then
        log_info "安装基础工具: ${deps_to_install[*]}"
        case "$PKG_MANAGER" in
            apt)
                apt-get install -y -qq "${deps_to_install[@]}" > /dev/null 2>&1
                ;;
            yum|dnf)
                $PKG_MANAGER install -y -q "${deps_to_install[@]}" > /dev/null 2>&1
                ;;
            pacman)
                pacman -S --noconfirm "${deps_to_install[@]}" > /dev/null 2>&1
                ;;
            apk)
                apk add --no-cache "${deps_to_install[@]}" > /dev/null 2>&1
                ;;
            zypper)
                zypper install -y "${deps_to_install[@]}" > /dev/null 2>&1
                ;;
        esac
    fi
    log_info "基础工具就绪 ✓"
}

install_git() {
    log_step "安装 Git"

    if command_exists git; then
        local git_version
        git_version=$(git --version | awk '{print $3}')
        log_info "Git 已安装 (版本: ${git_version}) ✓"
        return 0
    fi

    log_info "正在安装 Git..."

    case "$PKG_MANAGER" in
        apt)
            apt-get install -y -qq git > /dev/null 2>&1
            ;;
        yum|dnf)
            $PKG_MANAGER install -y -q git > /dev/null 2>&1
            ;;
        pacman)
            pacman -S --noconfirm git > /dev/null 2>&1
            ;;
        apk)
            apk add --no-cache git > /dev/null 2>&1
            ;;
        zypper)
            zypper install -y git > /dev/null 2>&1
            ;;
        brew)
            brew install git > /dev/null 2>&1
            ;;
    esac

    if command_exists git; then
        local git_version
        git_version=$(git --version | awk '{print $3}')
        log_info "Git 安装成功 (版本: ${git_version}) ✓"
    else
        log_error "Git 安装失败"
        exit 1
    fi
}

install_nodejs() {
    log_step "安装 Node.js"

    # 检查是否已安装且版本符合要求 (>=18)
    if command_exists node; then
        local node_version
        node_version=$(node --version | sed 's/v//')
        local node_major
        node_major=$(echo "$node_version" | cut -d. -f1)

        if [ "$node_major" -ge 18 ]; then
            log_info "Node.js 已安装 (版本: v${node_version}) ✓"

            if command_exists npm; then
                local npm_version
                npm_version=$(npm --version)
                log_info "npm 已安装 (版本: ${npm_version}) ✓"
            fi
            # 如果在中国，设置 npm 镜像
            if [ "$IS_CHINA" = true ] && command_exists npm; then
                npm config set registry "$NPM_MIRROR" 2>/dev/null || true
                log_info "已设置 npm 镜像: ${NPM_MIRROR}"
            fi
            return 0
        else
            log_warn "Node.js 版本过低 (v${node_version})，需要 >= 18"
            log_info "将安装 Node.js ${NODE_MAJOR_VERSION}.x"
        fi
    else
        log_info "未检测到 Node.js，将安装 Node.js ${NODE_MAJOR_VERSION}.x"
    fi

    # 安装 Node.js
    case "$PKG_MANAGER" in
        apt)
            install_nodejs_debian
            ;;
        yum|dnf)
            install_nodejs_rhel
            ;;
        pacman)
            pacman -S --noconfirm nodejs npm > /dev/null 2>&1
            ;;
        apk)
            apk add --no-cache nodejs npm > /dev/null 2>&1
            ;;
        zypper)
            install_nodejs_suse
            ;;
        brew)
            brew install node@${NODE_MAJOR_VERSION} > /dev/null 2>&1
            ;;
    esac

    # 验证安装
    if command_exists node; then
        local node_version
        node_version=$(node --version)
        log_info "Node.js 安装成功 (版本: ${node_version}) ✓"
    else
        log_error "Node.js 安装失败，尝试备用方案..."
        install_nodejs_fallback
    fi

    if command_exists npm; then
        local npm_version
        npm_version=$(npm --version)
        log_info "npm 安装成功 (版本: ${npm_version}) ✓"

        # 设置中国镜像
        if [ "$IS_CHINA" = true ]; then
            npm config set registry "$NPM_MIRROR" 2>/dev/null || true
            log_info "已设置 npm 镜像: ${NPM_MIRROR}"
        fi
    fi
}

install_nodejs_debian() {
    log_info "通过 NodeSource 安装 Node.js ${NODE_MAJOR_VERSION}.x ..."

    # 安装必要依赖
    apt-get install -y -qq ca-certificates gnupg > /dev/null 2>&1

    # 添加 NodeSource 仓库
    mkdir -p /etc/apt/keyrings

    if [ "$IS_CHINA" = true ]; then
        # 使用 npmmirror 的 Node.js 二进制
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true

        # 如果无法获取 key，直接使用 nvm 方式
        if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
            install_nodejs_fallback
            return
        fi
    else
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
    fi

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
}

install_nodejs_rhel() {
    log_info "通过 NodeSource 安装 Node.js ${NODE_MAJOR_VERSION}.x ..."

    if [ "$IS_CHINA" = true ]; then
        # 尝试使用 NodeSource
        curl -fsSL https://rpm.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | bash - > /dev/null 2>&1 || {
            install_nodejs_fallback
            return
        }
    else
        curl -fsSL https://rpm.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | bash - > /dev/null 2>&1
    fi

    $PKG_MANAGER install -y -q nodejs > /dev/null 2>&1
}

install_nodejs_suse() {
    zypper install -y nodejs${NODE_MAJOR_VERSION} npm${NODE_MAJOR_VERSION} > /dev/null 2>&1 || {
        install_nodejs_fallback
    }
}

install_nodejs_fallback() {
    log_warn "使用备用方案安装 Node.js..."

    local arch
    case $(uname -m) in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7l" ;;
        *)
            log_error "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac

    local node_url
    if [ "$IS_CHINA" = true ]; then
        node_url="https://npmmirror.com/mirrors/node/v${NODE_MAJOR_VERSION}.0.0/node-v${NODE_MAJOR_VERSION}.0.0-linux-${arch}.tar.xz"
        # 获取最新的 LTS 版本
        local latest_version
        latest_version=$(curl -s "https://registry.npmmirror.com/-/binary/node/latest-v${NODE_MAJOR_VERSION}.x/" 2>/dev/null | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "v${NODE_MAJOR_VERSION}.0.0")
        node_url="https://npmmirror.com/mirrors/node/${latest_version}/node-${latest_version}-linux-${arch}.tar.xz"
    else
        local latest_version
        latest_version=$(curl -s "https://nodejs.org/dist/latest-v${NODE_MAJOR_VERSION}.x/" 2>/dev/null | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "v${NODE_MAJOR_VERSION}.0.0")
        node_url="https://nodejs.org/dist/${latest_version}/node-${latest_version}-linux-${arch}.tar.xz"
    fi

    log_info "下载 Node.js: ${node_url}"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    if curl -fsSL "$node_url" -o "${tmp_dir}/node.tar.xz"; then
        tar -xJf "${tmp_dir}/node.tar.xz" -C "${tmp_dir}"
        local node_dir
        node_dir=$(ls -d ${tmp_dir}/node-v* 2>/dev/null | head -1)

        if [ -n "$node_dir" ]; then
            cp -r "${node_dir}/bin/"* /usr/local/bin/ 2>/dev/null || true
            cp -r "${node_dir}/lib/"* /usr/local/lib/ 2>/dev/null || true
            cp -r "${node_dir}/include/"* /usr/local/include/ 2>/dev/null || true
            cp -r "${node_dir}/share/"* /usr/local/share/ 2>/dev/null || true
            log_info "Node.js 二进制安装完成"
        fi
    else
        log_error "Node.js 下载失败"
        exit 1
    fi

    rm -rf "$tmp_dir"
}

# ======================== SillyTavern 克隆 ========================

clone_sillytavern() {
    log_step "克隆 SillyTavern"

    # 询问安装目录
    local custom_dir
    custom_dir=$(read_input "请输入安装目录" "$INSTALL_DIR")
    INSTALL_DIR="$custom_dir"

    # 检查目录是否已存在
    if [ -d "$INSTALL_DIR" ]; then
        if [ -f "$INSTALL_DIR/server.js" ] || [ -f "$INSTALL_DIR/start.sh" ]; then
            log_warn "检测到 ${INSTALL_DIR} 已存在 SillyTavern"
            if confirm "是否删除并重新安装？" "N"; then
                rm -rf "$INSTALL_DIR"
            else
                log_info "跳过克隆，使用现有安装"
                return 0
            fi
        fi
    fi

    # 选择分支
    echo ""
    echo -e "${WHITE}请选择 SillyTavern 分支:${NC}"
    echo -e "  ${CYAN}1)${NC} release  (稳定版，推荐)"
    echo -e "  ${CYAN}2)${NC} staging  (开发版，最新功能)"
    echo ""
    local branch_choice
    branch_choice=$(read_input "请选择" "1")

    case "$branch_choice" in
        2) BRANCH="staging" ;;
        *) BRANCH="release" ;;
    esac

    log_info "选择分支: ${BRANCH}"

    # 构建 clone URL
    local repo_url="https://github.com/SillyTavern/SillyTavern.git"

    if [ "$IS_CHINA" = true ] && [ -n "$GITHUB_PROXY" ]; then
        repo_url="${GITHUB_PROXY}/https://github.com/SillyTavern/SillyTavern.git"
        log_info "使用加速代理克隆..."
    fi

    log_info "正在克隆仓库: ${repo_url}"
    log_info "分支: ${BRANCH}"
    log_info "目标目录: ${INSTALL_DIR}"
    echo ""

    # 创建父目录
    mkdir -p "$(dirname "$INSTALL_DIR")"

    # 尝试克隆
    local clone_success=false
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ] && [ "$clone_success" = false ]; do
        retry=$((retry + 1))
        log_info "克隆尝试 ${retry}/${max_retries}..."

        if git clone --branch "$BRANCH" --single-branch --depth 1 "$repo_url" "$INSTALL_DIR" 2>&1; then
            clone_success=true
        else
            if [ $retry -lt $max_retries ]; then
                log_warn "克隆失败，5秒后重试..."

                # 如果使用了代理失败，尝试切换代理
                if [ "$IS_CHINA" = true ]; then
                    local proxies=(
                        "https://ghproxy.cn"
                        "https://mirror.ghproxy.com"
                        "https://gh-proxy.com"
                        "https://github.moeyy.xyz"
                    )
                    local next_proxy="${proxies[$retry]:-}"
                    if [ -n "$next_proxy" ]; then
                        repo_url="${next_proxy}/https://github.com/SillyTavern/SillyTavern.git"
                        log_info "切换代理: ${next_proxy}"
                    fi
                fi

                rm -rf "$INSTALL_DIR" 2>/dev/null || true
                sleep 5
            fi
        fi
    done

    if [ "$clone_success" = false ]; then
        log_error "SillyTavern 克隆失败"
        log_error "请检查网络连接后重试"

        if [ "$IS_CHINA" = true ]; then
            echo ""
            log_info "您也可以手动下载并解压到 ${INSTALL_DIR}"
            log_info "下载地址: https://github.com/SillyTavern/SillyTavern/archive/refs/heads/${BRANCH}.zip"
        fi
        exit 1
    fi

    log_info "SillyTavern 克隆成功 ✓"

    # 设置目录权限
    chown -R "${ACTUAL_USER}:${ACTUAL_USER}" "$INSTALL_DIR" 2>/dev/null || true
}

# ======================== 安装依赖 ========================

install_npm_deps() {
    log_step "安装 SillyTavern 依赖"

    cd "$INSTALL_DIR"

    if [ ! -f "package.json" ]; then
        log_error "未找到 package.json，SillyTavern 目录可能不完整"
        exit 1
    fi

    log_info "正在安装 npm 依赖（可能需要几分钟）..."

    # 设置 npm 缓存目录
    local npm_cache_dir="${ACTUAL_HOME}/.npm-cache-ksilly"
    mkdir -p "$npm_cache_dir"

    local npm_opts="--no-audit --no-fund --cache=${npm_cache_dir}"

    if [ "$IS_CHINA" = true ]; then
        npm_opts="${npm_opts} --registry=${NPM_MIRROR}"
    fi

    # 以实际用户身份运行 npm install
    if sudo -u "$ACTUAL_USER" bash -c "cd '$INSTALL_DIR' && npm install ${npm_opts}" 2>&1 | tail -5; then
        log_info "npm 依赖安装成功 ✓"
    else
        log_warn "npm install 可能有警告，尝试继续..."
        # 即使有警告也继续，因为某些 optional 依赖可能失败
    fi

    # 清理缓存
    rm -rf "$npm_cache_dir" 2>/dev/null || true
}

# ======================== 交互配置 ========================

interactive_config() {
    log_step "配置 SillyTavern"

    echo -e "${WHITE}接下来将引导您完成 SillyTavern 的基本配置${NC}"
    echo ""

    # ---- 监听地址 ----
    echo -e "${PURPLE}─── 网络监听配置 ───${NC}"
    echo ""
    echo -e "  监听地址决定了哪些设备可以访问 SillyTavern:"
    echo -e "  ${CYAN}127.0.0.1${NC} - 仅本机可以访问（更安全）"
    echo -e "  ${CYAN}0.0.0.0${NC}   - 允许局域网/外网设备访问"
    echo ""

    if confirm "是否允许外部设备访问（监听 0.0.0.0）？" "N"; then
        LISTEN_ADDRESS="0.0.0.0"
        log_info "监听地址设置为: 0.0.0.0 (所有接口)"
    else
        LISTEN_ADDRESS="127.0.0.1"
        log_info "监听地址设置为: 127.0.0.1 (仅本机)"
    fi

    # 端口
    echo ""
    LISTEN_PORT=$(read_input "请设置监听端口" "8000")
    log_info "监听端口设置为: ${LISTEN_PORT}"

    # ---- 白名单模式 ----
    echo ""
    echo -e "${PURPLE}─── 白名单模式 (whitelistMode) ───${NC}"
    echo ""
    echo -e "  白名单模式启用后，只有白名单中的 IP 才能访问"
    echo -e "  默认白名单包含: 127.0.0.1, ::1"
    echo -e "  ${YELLOW}如果需要从其他设备访问，建议关闭白名单模式${NC}"
    echo ""

    if [ "$LISTEN_ADDRESS" = "0.0.0.0" ]; then
        if confirm "是否关闭白名单模式（推荐，因为您开启了外部访问）？" "Y"; then
            WHITELIST_MODE=false
            log_info "白名单模式: 已关闭"
        else
            WHITELIST_MODE=true
            log_info "白名单模式: 已开启"

            echo ""
            log_warn "白名单模式开启时，外部设备将无法访问"
            log_info "您可以稍后在 config.yaml 中添加白名单 IP"
        fi
    else
        if confirm "是否关闭白名单模式？" "N"; then
            WHITELIST_MODE=false
            log_info "白名单模式: 已关闭"
        else
            WHITELIST_MODE=true
            log_info "白名单模式: 已开启（默认）"
        fi
    fi

    # ---- 基本认证 ----
    echo ""
    echo -e "${PURPLE}─── 基本认证 (basicAuthMode) ───${NC}"
    echo ""
    echo -e "  启用基本认证后，访问 SillyTavern 需要输入用户名和密码"
    echo -e "  ${YELLOW}如果开放了外部访问，强烈建议启用认证${NC}"
    echo ""

    local auth_recommend="N"
    if [ "$LISTEN_ADDRESS" = "0.0.0.0" ]; then
        auth_recommend="Y"
    fi

    if confirm "是否启用基本认证 (basicAuth)？" "$auth_recommend"; then
        BASIC_AUTH_MODE=true

        echo ""
        while true; do
            AUTH_USERNAME=$(read_input "请设置用户名" "")
            if [ -z "$AUTH_USERNAME" ]; then
                log_warn "用户名不能为空"
                continue
            fi
            break
        done

        while true; do
            AUTH_PASSWORD=$(read_password "请设置密码")
            if [ -z "$AUTH_PASSWORD" ]; then
                log_warn "密码不能为空"
                continue
            fi
            if [ ${#AUTH_PASSWORD} -lt 6 ]; then
                log_warn "密码长度至少为 6 位"
                continue
            fi

            local confirm_pass
            confirm_pass=$(read_password "请再次确认密码")
            if [ "$AUTH_PASSWORD" != "$confirm_pass" ]; then
                log_warn "两次密码不一致，请重新输入"
                continue
            fi
            break
        done

        log_info "基本认证: 已启用"
        log_info "用户名: ${AUTH_USERNAME}"
        log_info "密码: ******"
    else
        BASIC_AUTH_MODE=false
        log_info "基本认证: 未启用"
    fi

    # ---- 后台运行 & 开机自启动 ----
    echo ""
    echo -e "${PURPLE}─── 后台运行 & 开机自启动 ───${NC}"
    echo ""

    if confirm "是否设置 SillyTavern 后台运行（使用 systemd 服务）？" "Y"; then
        ENABLE_SERVICE=true
        log_info "后台运行: 已启用"

        echo ""
        if confirm "是否设置开机自启动？" "Y"; then
            ENABLE_AUTOSTART=true
            log_info "开机自启动: 已启用"
        else
            ENABLE_AUTOSTART=false
            log_info "开机自启动: 未启用"
        fi
    else
        ENABLE_SERVICE=false
        ENABLE_AUTOSTART=false
        log_info "后台运行: 未启用（将以前台方式运行）"
    fi
}

# ======================== 生成配置文件 ========================

generate_config() {
    log_step "生成配置文件"

    local config_file="${INSTALL_DIR}/config.yaml"
    local default_config="${INSTALL_DIR}/default/config.yaml"

    # 如果存在默认配置，先复制
    if [ -f "$default_config" ] && [ ! -f "$config_file" ]; then
        cp "$default_config" "$config_file"
        log_info "已从默认模板创建 config.yaml"
    fi

    # 如果 config.yaml 存在，使用 sed 修改
    if [ -f "$config_file" ]; then
        # 修改监听地址
        sed -i "s/^listen: .*/listen: ${LISTEN_ADDRESS}/" "$config_file" 2>/dev/null || true

        # 修改端口
        sed -i "s/^port: .*/port: ${LISTEN_PORT}/" "$config_file" 2>/dev/null || true

        # 修改白名单模式
        if [ "$WHITELIST_MODE" = true ]; then
            sed -i "s/^whitelistMode: .*/whitelistMode: true/" "$config_file" 2>/dev/null || true
        else
            sed -i "s/^whitelistMode: .*/whitelistMode: false/" "$config_file" 2>/dev/null || true
        fi

        # 修改基本认证
        if [ "$BASIC_AUTH_MODE" = true ]; then
            sed -i "s/^basicAuthMode: .*/basicAuthMode: true/" "$config_file" 2>/dev/null || true

            # 处理用户认证信息
            # 检查是否有 basicAuthUser 部分
            if grep -q "basicAuthUser:" "$config_file"; then
                sed -i "s/^  username: .*/  username: ${AUTH_USERNAME}/" "$config_file" 2>/dev/null || true
                sed -i "s/^  password: .*/  password: ${AUTH_PASSWORD}/" "$config_file" 2>/dev/null || true
            else
                # 在 basicAuthMode 后面添加
                sed -i "/^basicAuthMode: true/a\\
basicAuthUser:\\
  username: ${AUTH_USERNAME}\\
  password: ${AUTH_PASSWORD}" "$config_file" 2>/dev/null || true
            fi
        else
            sed -i "s/^basicAuthMode: .*/basicAuthMode: false/" "$config_file" 2>/dev/null || true
        fi

        log_info "config.yaml 已更新 ✓"
    else
        # 如果没有 config.yaml，直接创建
        log_info "创建新的 config.yaml..."

        local whitelist_str="true"
        if [ "$WHITELIST_MODE" = false ]; then
            whitelist_str="false"
        fi

        local auth_str="false"
        if [ "$BASIC_AUTH_MODE" = true ]; then
            auth_str="true"
        fi

        cat > "$config_file" << YAML
# SillyTavern 配置文件
# 由 Ksilly 自动生成

# 数据根目录
dataRoot: ./data

# 监听地址
listen: ${LISTEN_ADDRESS}

# 监听端口
port: ${LISTEN_PORT}

# 白名单模式
whitelistMode: ${whitelist_str}

# 白名单列表（仅 whitelistMode 为 true 时生效）
whitelist:
  - 127.0.0.1
  - ::1

# 基本认证
basicAuthMode: ${auth_str}
YAML

        if [ "$BASIC_AUTH_MODE" = true ]; then
            cat >> "$config_file" << YAML

# 认证用户
basicAuthUser:
  username: ${AUTH_USERNAME}
  password: ${AUTH_PASSWORD}
YAML
        fi

        cat >> "$config_file" << YAML

# 是否自动打开浏览器
autorun: false

# 自动更新
enableExtensionsAutoUpdate: true

# 安全设置
securityOverride: false
YAML

        log_info "config.yaml 已创建 ✓"
    fi

    # 设置文件权限
    chown "${ACTUAL_USER}:${ACTUAL_USER}" "$config_file" 2>/dev/null || true
    chmod 600 "$config_file"
    log_info "配置文件权限已设置 (600)"
}

# ======================== Systemd 服务 ========================

setup_systemd_service() {
    if [ "$ENABLE_SERVICE" = false ]; then
        return 0
    fi

    log_step "配置 Systemd 服务"

    # 检查 systemd 是否可用
    if ! command_exists systemctl; then
        log_warn "systemd 不可用，将跳过服务配置"
        log_info "您可以使用以下命令手动启动:"
        log_info "  cd ${INSTALL_DIR} && node server.js"
        ENABLE_SERVICE=false
        return 0
    fi

    local node_path
    node_path=$(which node)

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    cat > "$service_file" << EOF
[Unit]
Description=SillyTavern Server
Documentation=https://docs.sillytavern.app
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${ACTUAL_USER}
Group=${ACTUAL_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${node_path} server.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# 安全设置
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=false
ReadWritePaths=${INSTALL_DIR}

# 环境变量
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    log_info "Systemd 服务文件已创建: ${service_file}"

    # 重新加载 systemd
    systemctl daemon-reload

    # 启用开机自启动
    if [ "$ENABLE_AUTOSTART" = true ]; then
        systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
        log_info "开机自启动已启用 ✓"
    fi

    # 启动服务
    log_info "正在启动 SillyTavern 服务..."
    systemctl start "$SERVICE_NAME"

    sleep 3

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "SillyTavern 服务启动成功 ✓"
    else
        log_warn "服务启动可能失败，查看日志:"
        journalctl -u "$SERVICE_NAME" --no-pager -n 20
    fi
}

# ======================== 创建管理脚本 ========================

create_management_script() {
    log_step "创建管理脚本"

    local mgmt_script="/usr/local/bin/ksilly"

    cat > "$mgmt_script" << 'MGMT_EOF'
#!/bin/bash

# Ksilly - SillyTavern 管理脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MGMT_EOF

    cat >> "$mgmt_script" << EOF
SERVICE_NAME="${SERVICE_NAME}"
INSTALL_DIR="${INSTALL_DIR}"
EOF

    cat >> "$mgmt_script" << 'MGMT_EOF'

show_help() {
    echo -e "${CYAN}Ksilly - SillyTavern 管理工具${NC}"
    echo ""
    echo "用法: ksilly <命令>"
    echo ""
    echo "命令:"
    echo "  start       启动 SillyTavern"
    echo "  stop        停止 SillyTavern"
    echo "  restart     重启 SillyTavern"
    echo "  status      查看运行状态"
    echo "  log         查看实时日志"
    echo "  update      更新 SillyTavern"
    echo "  config      编辑配置文件"
    echo "  uninstall   卸载 SillyTavern"
    echo "  help        显示帮助"
}

do_start() {
    if command -v systemctl &> /dev/null && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        sudo systemctl start "$SERVICE_NAME"
        echo -e "${GREEN}SillyTavern 已启动${NC}"
        sleep 2
        do_status
    else
        echo -e "${YELLOW}以前台模式启动...${NC}"
        cd "$INSTALL_DIR"
        node server.js
    fi
}

do_stop() {
    if command -v systemctl &> /dev/null && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        sudo systemctl stop "$SERVICE_NAME"
        echo -e "${GREEN}SillyTavern 已停止${NC}"
    else
        echo -e "${YELLOW}尝试停止进程...${NC}"
        pkill -f "node.*server.js" 2>/dev/null || echo -e "${RED}未找到运行中的进程${NC}"
    fi
}

do_restart() {
    if command -v systemctl &> /dev/null && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        sudo systemctl restart "$SERVICE_NAME"
        echo -e "${GREEN}SillyTavern 已重启${NC}"
        sleep 2
        do_status
    else
        do_stop
        sleep 2
        do_start
    fi
}

do_status() {
    if command -v systemctl &> /dev/null && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        systemctl status "$SERVICE_NAME" --no-pager
    else
        if pgrep -f "node.*server.js" > /dev/null; then
            echo -e "${GREEN}SillyTavern 正在运行${NC}"
            pgrep -af "node.*server.js"
        else
            echo -e "${RED}SillyTavern 未运行${NC}"
        fi
    fi
}

do_log() {
    if command -v journalctl &> /dev/null && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        journalctl -u "$SERVICE_NAME" -f --no-pager
    else
        echo -e "${YELLOW}Systemd 日志不可用${NC}"
    fi
}

do_update() {
    echo -e "${CYAN}正在更新 SillyTavern...${NC}"

    # 停止服务
    do_stop 2>/dev/null || true

    cd "$INSTALL_DIR"

    # Git pull
    if git pull; then
        echo -e "${GREEN}代码更新成功${NC}"
    else
        echo -e "${RED}代码更新失败${NC}"
        return 1
    fi

    # 更新依赖
    echo -e "${CYAN}更新依赖...${NC}"
    npm install --no-audit --no-fund

    # 重新启动
    do_start

    echo -e "${GREEN}更新完成！${NC}"
}

do_config() {
    local config_file="${INSTALL_DIR}/config.yaml"
    if [ -f "$config_file" ]; then
        if command -v nano &> /dev/null; then
            nano "$config_file"
        elif command -v vim &> /dev/null; then
            vim "$config_file"
        elif command -v vi &> /dev/null; then
            vi "$config_file"
        else
            echo -e "${RED}未找到文本编辑器${NC}"
            echo "配置文件路径: $config_file"
        fi
    else
        echo -e "${RED}配置文件不存在: $config_file${NC}"
    fi
}

do_uninstall() {
    echo -e "${RED}⚠ 警告：这将完全删除 SillyTavern 及其所有数据！${NC}"
    echo -ne "${YELLOW}确认卸载？输入 'YES' 确认: ${NC}"
    read -r confirm
    if [ "$confirm" != "YES" ]; then
        echo "已取消"
        return
    fi

    echo -e "${CYAN}正在卸载...${NC}"

    # 停止并禁用服务
    if command -v systemctl &> /dev/null; then
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        sudo systemctl daemon-reload
    fi

    # 删除安装目录
    sudo rm -rf "$INSTALL_DIR"

    # 删除管理脚本
    sudo rm -f /usr/local/bin/ksilly

    echo -e "${GREEN}SillyTavern 已完全卸载${NC}"
}

case "${1:-help}" in
    start)     do_start ;;
    stop)      do_stop ;;
    restart)   do_restart ;;
    status)    do_status ;;
    log|logs)  do_log ;;
    update)    do_update ;;
    config)    do_config ;;
    uninstall) do_uninstall ;;
    help|*)    show_help ;;
esac
MGMT_EOF

    chmod +x "$mgmt_script"
    log_info "管理脚本已创建: ${mgmt_script}"
    log_info "使用 'ksilly help' 查看可用命令"
}

# ======================== 防火墙配置 ========================

configure_firewall() {
    if [ "$LISTEN_ADDRESS" != "0.0.0.0" ]; then
        return 0
    fi

    log_step "配置防火墙"

    # UFW
    if command_exists ufw; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            log_info "检测到 UFW 防火墙"
            if confirm "是否开放端口 ${LISTEN_PORT}？" "Y"; then
                ufw allow "${LISTEN_PORT}/tcp" > /dev/null 2>&1
                log_info "UFW 已开放端口 ${LISTEN_PORT} ✓"
            fi
        fi
        return 0
    fi

    # firewalld
    if command_exists firewall-cmd; then
        local fw_status
        fw_status=$(firewall-cmd --state 2>/dev/null || echo "not running")
        if [ "$fw_status" = "running" ]; then
            log_info "检测到 firewalld 防火墙"
            if confirm "是否开放端口 ${LISTEN_PORT}？" "Y"; then
                firewall-cmd --permanent --add-port="${LISTEN_PORT}/tcp" > /dev/null 2>&1
                firewall-cmd --reload > /dev/null 2>&1
                log_info "firewalld 已开放端口 ${LISTEN_PORT} ✓"
            fi
        fi
        return 0
    fi

    # iptables
    if command_exists iptables; then
        log_info "检测到 iptables"
        if confirm "是否添加 iptables 规则开放端口 ${LISTEN_PORT}？" "Y"; then
            iptables -I INPUT -p tcp --dport "${LISTEN_PORT}" -j ACCEPT 2>/dev/null || true
            # 保存规则
            if command_exists iptables-save; then
                iptables-save > /etc/iptables.rules 2>/dev/null || true
            fi
            log_info "iptables 已开放端口 ${LISTEN_PORT} ✓"
        fi
        return 0
    fi

    log_info "未检测到活动防火墙，跳过配置"
}

# ======================== 部署摘要 ========================

show_summary() {
    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "未知")

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ SillyTavern 部署完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}  📁 安装目录:${NC}   ${INSTALL_DIR}"
    echo -e "${WHITE}  🌿 分支:${NC}       ${BRANCH}"
    echo -e "${WHITE}  🔌 监听地址:${NC}   ${LISTEN_ADDRESS}:${LISTEN_PORT}"
    echo ""

    # 访问地址
    echo -e "${WHITE}  🌐 访问地址:${NC}"
    echo -e "     本机访问:   ${CYAN}http://127.0.0.1:${LISTEN_PORT}${NC}"
    if [ "$LISTEN_ADDRESS" = "0.0.0.0" ]; then
        echo -e "     局域网:     ${CYAN}http://${local_ip}:${LISTEN_PORT}${NC}"
    fi
    echo ""

    # 安全配置
    echo -e "${WHITE}  🔒 安全配置:${NC}"
    if [ "$WHITELIST_MODE" = true ]; then
        echo -e "     白名单模式:  ${GREEN}已开启${NC}"
    else
        echo -e "     白名单模式:  ${YELLOW}已关闭${NC}"
    fi

    if [ "$BASIC_AUTH_MODE" = true ]; then
        echo -e "     基本认证:    ${GREEN}已开启${NC}"
        echo -e "     用户名:      ${AUTH_USERNAME}"
    else
        echo -e "     基本认证:    ${YELLOW}未启用${NC}"
    fi
    echo ""

    # 服务状态
    echo -e "${WHITE}  ⚙ 服务配置:${NC}"
    if [ "$ENABLE_SERVICE" = true ]; then
        echo -e "     后台运行:    ${GREEN}已启用 (systemd)${NC}"
        if [ "$ENABLE_AUTOSTART" = true ]; then
            echo -e "     开机自启:    ${GREEN}已启用${NC}"
        else
            echo -e "     开机自启:    ${YELLOW}未启用${NC}"
        fi
    else
        echo -e "     后台运行:    ${YELLOW}未启用${NC}"
    fi
    echo ""

    # 常用命令
    echo -e "${WHITE}  📌 常用命令:${NC}"
    if [ "$ENABLE_SERVICE" = true ]; then
        echo -e "     启动服务:    ${CYAN}ksilly start${NC}"
        echo -e "     停止服务:    ${CYAN}ksilly stop${NC}"
        echo -e "     重启服务:    ${CYAN}ksilly restart${NC}"
        echo -e "     查看状态:    ${CYAN}ksilly status${NC}"
        echo -e "     查看日志:    ${CYAN}ksilly log${NC}"
        echo -e "     更新版本:    ${CYAN}ksilly update${NC}"
        echo -e "     编辑配置:    ${CYAN}ksilly config${NC}"
    else
        echo -e "     启动:        ${CYAN}cd ${INSTALL_DIR} && node server.js${NC}"
    fi
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 如果不是后台运行模式，询问是否立即启动
    if [ "$ENABLE_SERVICE" = false ]; then
        if confirm "是否立即启动 SillyTavern？" "Y"; then
            log_info "正在启动 SillyTavern..."
            echo -e "${YELLOW}按 Ctrl+C 停止${NC}"
            echo ""
            cd "$INSTALL_DIR"
            sudo -u "$ACTUAL_USER" node server.js
        fi
    fi
}

# ======================== 错误处理 ========================

cleanup_on_error() {
    echo ""
    log_error "安装过程中发生错误"
    log_info "请检查以上错误信息"

    if [ -d "$INSTALL_DIR" ]; then
        log_info "安装目录: ${INSTALL_DIR}"
        if confirm "是否清理安装目录？" "N"; then
            rm -rf "$INSTALL_DIR"
            log_info "已清理安装目录"
        fi
    fi

    exit 1
}

trap cleanup_on_error ERR

# ======================== 主流程 ========================

main() {
    print_banner

    # 检查权限
    check_root

    # 检测操作系统
    detect_os

    # 检测网络环境
    detect_network

    # 更新包管理器
    update_package_manager

    # 安装基础依赖
    install_basic_deps

    # 安装 Git
    install_git

    # 安装 Node.js
    install_nodejs

    # 交互式配置
    interactive_config

    # 克隆 SillyTavern
    clone_sillytavern

    # 安装 npm 依赖
    install_npm_deps

    # 生成配置文件
    generate_config

    # 配置防火墙
    configure_firewall

    # 设置 systemd 服务
    setup_systemd_service

    # 创建管理脚本
    create_management_script

    # 显示部署摘要
    show_summary
}

# 运行主流程
main "$@"
