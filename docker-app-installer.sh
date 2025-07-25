#!/bin/bash

# Docker + Docker Compose + 应用一键安装脚本 v1.0
# 作者: Cheny
# 支持系统: Debian 10/11/12, Ubuntu 18.04/20.04/22.04

# 移除 set -e 以防止脚本意外退出
# set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
INSTALL_PORTAINER=false
PORTAINER_PORT=9000

# 应用配置
declare -A APPS_CONFIG=(
    ["portainer"]="Portainer - Docker 管理界面"
    ["qbittorrent"]="qBittorrent - BT 下载工具"
    ["vertex"]="Vertex - 文件管理下载工具"
    ["nginx-proxy-manager"]="Nginx Proxy Manager - 反向代理管理"
    ["transmission"]="Transmission - BT 下载工具"
    ["filebrowser"]="File Browser - 文件浏览器"
)

declare -A APPS_PORTS=(
    ["portainer"]=9000
    ["qbittorrent"]=8080
    ["vertex"]=3000
    ["nginx-proxy-manager"]=81
    ["transmission"]=9091
    ["filebrowser"]=8081
)

# 应用版本配置（默认使用最新稳定版）
declare -A APPS_VERSIONS=(
    ["portainer"]="latest"
    ["qbittorrent"]="4.5.5"
    ["vertex"]="stable"
    ["nginx-proxy-manager"]="latest"
    ["transmission"]="latest"
    ["filebrowser"]="latest"
)

# 应用镜像配置
declare -A APPS_IMAGES=(
    ["portainer"]="portainer/portainer-ce"
    ["qbittorrent"]="lscr.io/linuxserver/qbittorrent"
    ["vertex"]="lswl/vertex"
    ["nginx-proxy-manager"]="chishin/nginx-proxy-manager-zh"
    ["transmission"]="lscr.io/linuxserver/transmission"
    ["filebrowser"]="filebrowser/filebrowser"
)

declare -A APPS_SELECTED=(
    ["portainer"]=false
    ["qbittorrent"]=false
    ["vertex"]=false
    ["nginx-proxy-manager"]=false
    ["transmission"]=false
    ["filebrowser"]=false
)

# 基础目录
DOCKER_BASE_DIR="/home/docker"

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_menu() { echo -e "${CYAN}$1${NC}"; }

# 检查函数 - 修复：移到函数调用之前
check_docker_installed() {
    if command -v docker > /dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            log_success "Docker 已安装: $docker_version"
            return 0
        fi
    fi
    return 1
}

check_docker_compose_installed() {
    if command -v docker-compose > /dev/null 2>&1; then
        local compose_version=$(docker-compose --version 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            log_success "Docker Compose 已安装: $compose_version"
            return 0
        fi
    fi
    return 1
}

check_docker_service_running() {
    if systemctl is-active docker > /dev/null 2>&1; then
        log_success "Docker 服务正在运行"
        return 0
    else
        log_warning "Docker 服务未运行，尝试启动..."
        systemctl start docker 2>/dev/null || {
            log_error "无法启动 Docker 服务"
            return 1
        }
        log_success "Docker 服务已启动"
        return 0
    fi
}

check_app_installed() {
    local app="$1"
    log_info "检查应用 $app 的安装状态..."
    
    # 检查 Docker 服务是否可用
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker 服务不可用，无法检查应用状态"
        return 1
    fi
    
    # 检查容器是否存在
    if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
        local status=$(docker ps -a --filter "name=${app}" --format "{{.Status}}" 2>/dev/null || echo "状态获取失败")
        # 检查容器是否正在运行
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
            log_success "$app 已安装并运行中: $status"
            return 0
        else
            log_warning "$app 已安装但未运行: $status"
            return 2
        fi
    else
        log_info "$app 未安装"
        return 1
    fi
}

check_port_in_use() {
    local port="$1"
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    return 1
}

check_app_port_conflict() {
    local app="$1"
    local port="${APPS_PORTS[$app]}"
    
    if check_port_in_use "$port"; then
        local container_using_port=$(docker ps --format "{{.Names}}" --filter "publish=${port}" 2>/dev/null)
        if [[ "$container_using_port" == "$app" ]]; then
            log_info "$app 正在使用端口 $port（正常）"
            return 0
        else
            log_error "端口 $port 被其他服务占用: $container_using_port"
            return 1
        fi
    fi
    return 0
}

# 系统检查函数
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

check_system() {
    log_info "检查系统信息..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        log_info "检测到系统: $OS $VER"
        
        case $ID in
            debian|ubuntu)
                log_success "支持的系统版本"
                ;;
            *)
                log_error "不支持的系统版本: $OS"
                exit 1
                ;;
        esac
    else
        log_error "无法检测系统版本"
        exit 1
    fi
}

# BBR 管理函数
check_bbr_status() {
    log_info "检查当前BBR状态..."
    
    # 检查内核参数
    local bbr_enabled=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local bbr_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    
    if [[ "$bbr_enabled" == "fq" && "$bbr_congestion" == "bbr" ]]; then
        log_success "BBR 已启用"
        log_info "默认队列规则: $bbr_enabled"
        log_info "拥塞控制算法: $bbr_congestion"
        return 0
    else
        log_warning "BBR 未启用"
        log_info "当前队列规则: $bbr_enabled"
        log_info "当前拥塞控制: $bbr_congestion"
        return 1
    fi
}

enable_bbr() {
    log_info "启用 BBR 拥塞控制算法..."
    
    # 检查内核版本
    local kernel_version=$(uname -r | cut -d. -f1,2)
    if [[ $(echo "$kernel_version >= 4.9" | bc -l 2>/dev/null) -eq 0 ]]; then
        log_error "内核版本过低，需要 4.9 或更高版本才能使用 BBR"
        log_info "当前内核版本: $(uname -r)"
        return 1
    fi
    
    # 设置内核参数
    cat >> /etc/sysctl.conf << EOF

# BBR 拥塞控制算法
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    
    # 立即应用设置
    sysctl -p /etc/sysctl.conf
    
    # 验证设置
    if check_bbr_status; then
        log_success "BBR 启用成功"
        return 0
    else
        log_error "BBR 启用失败"
        return 1
    fi
}

disable_bbr() {
    log_info "禁用 BBR 拥塞控制算法..."
    
    # 备份原配置
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 移除BBR相关配置
    sed -i '/# BBR 拥塞控制算法/,+2d' /etc/sysctl.conf
    
    # 恢复默认设置
    sysctl -w net.core.default_qdisc=pfifo_fast
    sysctl -w net.ipv4.tcp_congestion_control=cubic
    
    # 应用设置
    sysctl -p /etc/sysctl.conf
    
    log_success "BBR 已禁用，恢复默认设置"
    log_info "当前队列规则: $(sysctl -n net.core.default_qdisc)"
    log_info "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
}

check_bbrx_status() {
    log_info "检查当前BBRx状态..."
    
    # 检查是否安装了BBRx内核模块
    if lsmod | grep -q bbrx; then
        log_success "BBRx 内核模块已加载"
        return 0
    else
        log_warning "BBRx 内核模块未加载"
        return 1
    fi
}

install_bbrx() {
    log_info "安装 BBRx 内核模块..."
    
    # 检查系统架构
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_error "BBRx 目前仅支持 x86_64 架构"
        log_info "当前架构: $arch"
        return 1
    fi
    
    # 安装依赖
    apt-get update -qq
    apt-get install -y build-essential linux-headers-$(uname -r) git
    
    # 下载并编译BBRx
    local bbrx_dir="/tmp/bbrx"
    rm -rf "$bbrx_dir"
    git clone https://github.com/google/bbr.git "$bbrx_dir"
    cd "$bbrx_dir"
    
    # 编译内核模块
    make -C /lib/modules/$(uname -r)/build M=$PWD modules
    
    # 安装模块
    make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
    
    # 加载模块
    modprobe bbrx
    
    # 验证安装
    if check_bbrx_status; then
        log_success "BBRx 安装成功"
        return 0
    else
        log_error "BBRx 安装失败"
        return 1
    fi
}

uninstall_bbrx() {
    log_info "卸载 BBRx 内核模块..."
    
    # 卸载模块
    modprobe -r bbrx 2>/dev/null || true
    
    # 清理编译文件
    rm -rf /tmp/bbrx
    
    log_success "BBRx 已卸载"
}

# 安装函数
update_system() {
    log_info "更新系统包列表..."
    apt-get update -qq
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common wget
    log_success "系统更新完成"
}

remove_old_docker() {
    log_info "检查并卸载旧版本的Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    log_success "旧版本Docker清理完成"
}

install_docker() {
    log_info "开始安装Docker..."
    curl -fsSL https://download.docker.com/linux/$(lsb_release -si | tr '[:upper:]' '[:lower:]')/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(lsb_release -si | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl start docker
    systemctl enable docker
    
    if docker --version > /dev/null 2>&1; then
        log_success "Docker安装成功: $(docker --version)"
    else
        log_error "Docker安装失败"
        exit 1
    fi
}

install_docker_compose() {
    log_info "开始安装Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if [[ -z "$COMPOSE_VERSION" ]]; then
        COMPOSE_VERSION="v2.24.1"
    fi
    
    curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    if docker-compose --version > /dev/null 2>&1; then
        log_success "Docker Compose安装成功: $(docker-compose --version)"
    else
        log_error "Docker Compose安装失败"
        exit 1
    fi
}

configure_docker_group() {
    log_info "配置Docker用户组..."
    groupadd -f docker
    REAL_USER=${SUDO_USER:-$USER}
    if [[ "$REAL_USER" != "root" ]]; then
        usermod -aG docker $REAL_USER
        log_success "用户 $REAL_USER 已添加到docker组"
    fi
}

# 应用安装函数
create_docker_directories() {
    log_info "创建Docker应用目录结构..."
    mkdir -p "$DOCKER_BASE_DIR"
    
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            case $app in
                "portainer")
                    mkdir -p "$DOCKER_BASE_DIR/portainer/data"
                    ;;
                "qbittorrent")
                    mkdir -p "$DOCKER_BASE_DIR/qbittorrent/"{config,downloads,watch}
                    ;;
                "vertex")
                    mkdir -p "$DOCKER_BASE_DIR/vertex/"{config,downloads,media}
                    ;;
                "nginx-proxy-manager")
                    mkdir -p "$DOCKER_BASE_DIR/nginx-proxy-manager/"{data,letsencrypt}
                    ;;
                "transmission")
                    mkdir -p "$DOCKER_BASE_DIR/transmission/"{config,downloads,watch}
                    ;;
                "filebrowser")
                    mkdir -p "$DOCKER_BASE_DIR/filebrowser/"{config,files}
                    ;;
            esac
        fi
    done
    
    chown -R 1000:1000 "$DOCKER_BASE_DIR" 2>/dev/null || true
    chmod -R 755 "$DOCKER_BASE_DIR"
    log_success "目录结构创建完成"
}

install_portainer_app() {
    log_info "检查 Portainer 安装状态..."
    local app_status
    check_app_installed "portainer"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "Portainer 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "Portainer 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start portainer 2>/dev/null && log_success "Portainer 已重新启动" && return 0
        else
            log_info "跳过 Portainer 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 Portainer..."
    local port="${APPS_PORTS[portainer]}"
    local version="${APPS_VERSIONS[portainer]}"
    local image="${APPS_IMAGES[portainer]}"
    
    if ! check_app_port_conflict "portainer"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop portainer 2>/dev/null || true
    docker rm portainer 2>/dev/null || true
    
    docker run -d \
        --name portainer \
        --restart=always \
        -p "$port:9000" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$DOCKER_BASE_DIR/portainer/data:/data" \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^portainer$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "Portainer 安装成功 (端口: $port)"
    else
        log_error "Portainer 安装失败，容器状态: $status"
        log_info "Portainer 日志："
        docker logs portainer 2>&1 | tail -n 20
        return 1
    fi
}

install_qbittorrent_app() {
    log_info "检查 qBittorrent 安装状态..."
    local app_status
    check_app_installed "qbittorrent"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "qBittorrent 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "qBittorrent 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start qbittorrent 2>/dev/null && log_success "qBittorrent 已重新启动" && return 0
        else
            log_info "跳过 qBittorrent 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 qBittorrent..."
    local port="${APPS_PORTS[qbittorrent]}"
    local version="${APPS_VERSIONS[qbittorrent]}"
    local image="${APPS_IMAGES[qbittorrent]}"
    
    if ! check_app_port_conflict "qbittorrent"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop qbittorrent 2>/dev/null || true
    docker rm qbittorrent 2>/dev/null || true
    
    # 创建共享下载目录
    mkdir -p "$DOCKER_BASE_DIR/shared/downloads"
    
    docker run -d \
        --name qbittorrent \
        --restart=always \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai -e WEBUI_PORT="$port" \
        -p "$port:$port" -p 6881:6881 -p 6881:6881/udp \
        -v "$DOCKER_BASE_DIR/qbittorrent/config:/config" \
        -v "$DOCKER_BASE_DIR/shared/downloads:/downloads" \
        -v "$DOCKER_BASE_DIR/qbittorrent/watch:/watch" \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^qbittorrent$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "qBittorrent 安装成功 (端口: $port)"
        log_info "下载目录已映射到共享目录: $DOCKER_BASE_DIR/shared/downloads"
        log_info "默认用户名: admin，查看密码: docker logs qbittorrent"
    else
        log_error "qBittorrent 安装失败，容器状态: $status"
        log_info "qBittorrent 日志："
        docker logs qbittorrent 2>&1 | tail -n 20
        return 1
    fi
}

install_vertex_app() {
    log_info "检查 Vertex 安装状态..."
    local app_status
    check_app_installed "vertex"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "Vertex 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "Vertex 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start vertex 2>/dev/null && log_success "Vertex 已重新启动" && return 0
        else
            log_info "跳过 Vertex 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 Vertex..."
    local port="${APPS_PORTS[vertex]}"
    local version="${APPS_VERSIONS[vertex]}"
    local image="${APPS_IMAGES[vertex]}"
    
    if ! check_app_port_conflict "vertex"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop vertex 2>/dev/null || true
    docker rm vertex 2>/dev/null || true

    docker run -d \
        --name vertex \
        -v "$DOCKER_BASE_DIR/vertex:/vertex" \
        -p "$port:3000" \
        -e TZ=Asia/Shanghai \
        --restart unless-stopped \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^vertex$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "Vertex 安装成功 (端口: $port)"
    else
        log_error "Vertex 安装失败，容器状态: $status"
        log_info "Vertex 日志："
        docker logs vertex 2>&1 | tail -n 20
        return 1
    fi
}

install_nginx_proxy_manager_app() {
    log_info "检查 Nginx Proxy Manager 安装状态..."
    local app_status
    check_app_installed "nginx-proxy-manager"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "Nginx Proxy Manager 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "Nginx Proxy Manager 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start nginx-proxy-manager 2>/dev/null && log_success "Nginx Proxy Manager 已重新启动" && return 0
        else
            log_info "跳过 Nginx Proxy Manager 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 Nginx Proxy Manager..."
    local port="${APPS_PORTS[nginx-proxy-manager]}"
    local version="${APPS_VERSIONS[nginx-proxy-manager]}"
    local image="${APPS_IMAGES[nginx-proxy-manager]}"
    
    if ! check_app_port_conflict "nginx-proxy-manager"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop nginx-proxy-manager 2>/dev/null || true
    docker rm nginx-proxy-manager 2>/dev/null || true
    
    docker run -d \
        --name nginx-proxy-manager \
        --restart=always \
        -p "$port:81" -p 80:80 -p 443:443 \
        -v "$DOCKER_BASE_DIR/nginx-proxy-manager/data:/data" \
        -v "$DOCKER_BASE_DIR/nginx-proxy-manager/letsencrypt:/etc/letsencrypt" \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^nginx-proxy-manager$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "Nginx Proxy Manager 安装成功 (端口: $port)"
        log_info "默认登录: admin@example.com / changeme"
    else
        log_error "Nginx Proxy Manager 安装失败，容器状态: $status"
        log_info "Nginx Proxy Manager 日志："
        docker logs nginx-proxy-manager 2>&1 | tail -n 20
        return 1
    fi
}

install_transmission_app() {
    log_info "检查 Transmission 安装状态..."
    local app_status
    check_app_installed "transmission"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "Transmission 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "Transmission 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start transmission 2>/dev/null && log_success "Transmission 已重新启动" && return 0
        else
            log_info "跳过 Transmission 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 Transmission..."
    local port="${APPS_PORTS[transmission]}"
    local version="${APPS_VERSIONS[transmission]}"
    local image="${APPS_IMAGES[transmission]}"
    
    if ! check_app_port_conflict "transmission"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop transmission 2>/dev/null || true
    docker rm transmission 2>/dev/null || true
    
    # 创建共享下载目录
    mkdir -p "$DOCKER_BASE_DIR/shared/downloads"
    
    docker run -d \
        --name transmission \
        --restart=always \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai -e USER=admin -e PASS=changeme \
        -p "$port:9091" -p 51413:51413 -p 51413:51413/udp \
        -v "$DOCKER_BASE_DIR/transmission/config:/config" \
        -v "$DOCKER_BASE_DIR/shared/downloads:/downloads" \
        -v "$DOCKER_BASE_DIR/transmission/watch:/watch" \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^transmission$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "Transmission 安装成功 (端口: $port)"
        log_info "下载目录已映射到共享目录: $DOCKER_BASE_DIR/shared/downloads"
        log_info "默认登录: admin / changeme"
    else
        log_error "Transmission 安装失败，容器状态: $status"
        log_info "Transmission 日志："
        docker logs transmission 2>&1 | tail -n 20
        return 1
    fi
}

install_filebrowser_app() {
    log_info "检查 File Browser 安装状态..."
    local app_status
    check_app_installed "filebrowser"
    app_status=$?
    
    if [ $app_status -eq 0 ]; then
        log_info "File Browser 已安装并运行中，跳过安装"
        return 0
    elif [ $app_status -eq 2 ]; then
        read -p "File Browser 已安装但未运行，是否重新启动? (y/N): " restart_choice
        if [[ $restart_choice =~ ^[Yy]$ ]]; then
            docker start filebrowser 2>/dev/null && log_success "File Browser 已重新启动" && return 0
        else
            log_info "跳过 File Browser 安装"
            return 0
        fi
    fi
    
    log_info "开始安装 File Browser..."
    local port="${APPS_PORTS[filebrowser]}"
    local version="${APPS_VERSIONS[filebrowser]}"
    local image="${APPS_IMAGES[filebrowser]}"
    
    if ! check_app_port_conflict "filebrowser"; then
        log_warning "端口冲突，跳过安装"
        return 1
    fi
    
    docker stop filebrowser 2>/dev/null || true
    docker rm filebrowser 2>/dev/null || true
    
    # 创建共享下载目录
    mkdir -p "$DOCKER_BASE_DIR/shared/downloads"
    
    docker run -d \
        --name filebrowser \
        --restart=always \
        -p "$port:8081" \
        -v "$DOCKER_BASE_DIR/filebrowser/config:/config" \
        -v "$DOCKER_BASE_DIR/shared/downloads:/srv" \
        "$image:$version"
    
    local status=$(docker ps -a --filter "name=^filebrowser$" --format "{{.Status}}")
    if [[ $status == Up* ]]; then
        log_success "File Browser 安装成功 (端口: $port)"
        log_info "文件浏览器已映射到共享下载目录: $DOCKER_BASE_DIR/shared/downloads"
        log_info "默认登录: admin / admin"
    else
        log_error "File Browser 安装失败，容器状态: $status"
        log_info "File Browser 日志："
        docker logs filebrowser 2>&1 | tail -n 20
        return 1
    fi
}

# 主要安装流程
install_selected_apps() {
    log_info "开始安装选择的应用..."
    local installed_count=0
    local total_count=0
    
    # 统计选择的应用数量
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            ((total_count++))
        fi
    done
    
    log_info "共选择了 $total_count 个应用进行安装"
    
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            log_info "正在处理应用: $app (${APPS_CONFIG[$app]})"
            case $app in
                "portainer") 
                    if install_portainer_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                "qbittorrent") 
                    if install_qbittorrent_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                "vertex") 
                    if install_vertex_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                "nginx-proxy-manager") 
                    if install_nginx_proxy_manager_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                "transmission") 
                    if install_transmission_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                "filebrowser")
                    if install_filebrowser_app; then
                        ((installed_count++))
                        log_success "$app 处理完成"
                    else
                        log_warning "$app 处理失败或跳过"
                    fi
                    ;;
                *)
                    log_error "未知应用: $app"
                    ;;
            esac
        fi
    done
    
    log_info "应用安装处理完成: 成功/跳过 $installed_count/$total_count"
}

# 修复：优化安装流程，避免重复安装Docker
start_apps_installation() {
    log_info "开始应用安装过程..."
    check_root
    check_system
    
    # 智能检查和安装Docker组件
    if check_docker_installed; then
        if ! check_docker_service_running; then
            log_error "Docker 已安装但服务启动失败"
            exit 1
        fi
    else
        log_info "Docker 未安装，开始安装..."
        update_system
        remove_old_docker
        install_docker
    fi
    
    if check_docker_compose_installed; then
        log_info "Docker Compose 已安装，跳过安装"
    else
        log_info "Docker Compose 未安装，开始安装..."
        install_docker_compose
    fi
    
    configure_docker_group
    create_docker_directories
    install_selected_apps
    
    log_success "应用安装完成！"
    show_installation_summary
}

start_basic_installation() {
    log_info "开始基础安装过程..."
    check_root
    check_system
    
    if check_docker_installed; then
        if ! check_docker_service_running; then
            log_error "Docker 已安装但服务启动失败"
            exit 1
        fi
    else
        update_system
        remove_old_docker
        install_docker
    fi
    
    if check_docker_compose_installed; then
        log_info "Docker Compose 已安装，跳过安装"
    else
        install_docker_compose
    fi
    
    configure_docker_group
    create_docker_directories
    
    log_success "基础安装完成！"
    show_installation_summary
}

show_installation_summary() {
    echo
    log_success "=== 安装完成 ==="
    echo
    log_info "Docker版本: $(docker --version)"
    log_info "Docker Compose版本: $(docker-compose --version)"
    echo
    log_info "已安装的应用:"
    local host_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]] && docker ps | grep -q "$app"; then
            local port="${APPS_PORTS[$app]}"
            log_success "  ✓ $app - 访问地址: http://$host_ip:$port"
        fi
    done
    
    echo
    log_info "数据目录: $DOCKER_BASE_DIR"
    log_warning "注意: 如果您不是root用户，请注销并重新登录以使docker组权限生效"
}

# 菜单和用户交互函数
show_main_menu() {
    clear
    echo "========================================"
    echo "    Docker 应用一键安装脚本 v1.0       "
    echo "========================================"
    echo
    log_menu "请选择操作:"
    log_menu "1) 基础安装 (Docker + Docker Compose)"
    log_menu "2) 应用安装 (选择要安装的应用)"
    log_menu "3) 应用卸载 (卸载已安装的应用)"
    log_menu "4) 查看当前状态"
    log_menu "5) BBR/BBRx 管理"
    log_menu "6) 退出"
    echo
    read -p "请输入选项 (1-6): " choice
    echo
    
    case $choice in
        1) confirm_basic_installation ;;
        2) show_apps_selection_menu ;;
        3) show_uninstall_menu ;;
        4) show_status ;;
        5) show_bbr_menu ;;
        6) log_info "退出脚本"; exit 0 ;;
        *) log_error "无效选项"; sleep 2; show_main_menu ;;
    esac
}

show_apps_selection_menu() {
    while true; do
        clear
        echo "========================================"
        echo "           Docker 应用选择             "
        echo "========================================"
        echo
        log_info "可用应用列表:"
        echo
        
        local i=1
        local app_list=()
        for app in "${!APPS_CONFIG[@]}"; do
            app_list+=("$app")
            local status="未选择"
            local status_color="${RED}"
            local version="${APPS_VERSIONS[$app]}"
            local image="${APPS_IMAGES[$app]}"
            if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
                status="已选择 (端口:${APPS_PORTS[$app]}, 版本:$version)"
                status_color="${GREEN}"
            fi
            echo -e "  ${CYAN}$i.${NC} $app - ${APPS_CONFIG[$app]}"
            echo -e "     状态: ${status_color}$status${NC}"
            echo -e "     镜像: $image:$version"
            echo
            ((i++))
        done
        
        echo -e "  ${CYAN}a.${NC} 全选"
        echo -e "  ${CYAN}c.${NC} 清空选择"
        echo -e "  ${CYAN}p.${NC} 配置端口"
        echo -e "  ${CYAN}v.${NC} 配置版本"
        echo -e "  ${CYAN}n.${NC} 下一步 (确认安装)"
        echo -e "  ${CYAN}b.${NC} 返回主菜单"
        echo
        
        read -p "请输入选项: " app_choice
        
        case $app_choice in
            [1-9]*)
                if [[ $app_choice -ge 1 && $app_choice -le ${#app_list[@]} ]]; then
                    local selected_app="${app_list[$((app_choice-1))]}"
                    toggle_app_selection "$selected_app"
                else
                    log_error "无效选项"; sleep 1
                fi
                ;;
            a|A) select_all_apps ;;
            c|C) clear_all_selections ;;
            p|P) configure_apps_ports ;;
            v|V) configure_apps_versions ;;
            n|N)
                if check_apps_selected; then
                    confirm_apps_installation
                    break
                else
                    log_error "请至少选择一个应用"; sleep 2
                fi
                ;;
            b|B) show_main_menu; break ;;
            *) log_error "无效选项"; sleep 1 ;;
        esac
    done
}

toggle_app_selection() {
    local app="$1"
    if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
        APPS_SELECTED[$app]=false
        log_info "已取消选择: $app"
    else
        APPS_SELECTED[$app]=true
        log_success "已选择: $app"
    fi
    sleep 1
}

select_all_apps() {
    for app in "${!APPS_CONFIG[@]}"; do
        APPS_SELECTED[$app]=true
    done
    log_success "已选择所有应用"
    sleep 1
}

clear_all_selections() {
    for app in "${!APPS_CONFIG[@]}"; do
        APPS_SELECTED[$app]=false
    done
    log_info "已清空所有选择"
    sleep 1
}

check_apps_selected() {
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            return 0
        fi
    done
    return 1
}

configure_apps_ports() {
    clear
    echo "========================================"
    echo "           端口配置                    "
    echo "========================================"
    echo
    
    for app in "${!APPS_CONFIG[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            log_info "配置 $app 端口:"
            echo "  当前端口: ${APPS_PORTS[$app]}"
            
            while true; do
                read -p "  输入新端口 (直接回车保持当前端口): " new_port
                
                if [[ -z "$new_port" ]]; then
                    break
                elif [[ $new_port =~ ^[0-9]+$ ]] && [ $new_port -ge 1024 ] && [ $new_port -le 65535 ]; then
                    local port_conflict=false
                    for other_app in "${!APPS_PORTS[@]}"; do
                        if [[ "$other_app" != "$app" && "${APPS_PORTS[$other_app]}" == "$new_port" ]]; then
                            log_error "端口 $new_port 已被 $other_app 使用"
                            port_conflict=true
                            break
                        fi
                    done
                    
                    if [[ "$port_conflict" == "false" ]]; then
                        APPS_PORTS[$app]=$new_port
                        log_success "$app 端口已设置为: $new_port"
                        break
                    fi
                else
                    log_error "请输入有效的端口号 (1024-65535)"
                fi
            done
            echo
        fi
    done
    
    read -p "按任意键继续..." -n 1
}

configure_apps_versions() {
    while true; do
        clear
        echo "========================================"
        echo "           应用版本配置                "
        echo "========================================"
        echo
        log_info "当前应用版本配置:"
        echo
        
        local i=1
        local app_list=()
        for app in "${!APPS_CONFIG[@]}"; do
            app_list+=("$app")
            local version="${APPS_VERSIONS[$app]}"
            local image="${APPS_IMAGES[$app]}"
            echo -e "  ${CYAN}$i.${NC} $app - ${APPS_CONFIG[$app]}"
            echo -e "     版本: $image:$version"
            echo
            ((i++))
        done
        
        echo -e "  ${CYAN}b.${NC} 返回应用选择菜单"
        echo
        
        log_info "版本说明:"
        log_info "  - latest: 最新版本"
        log_info "  - stable: 稳定版本"
        log_info "  - 具体版本号: 如 4.5.5"
        echo
        
        read -p "请选择要配置版本的应用 (1-${#app_list[@]}, b返回): " version_choice
        
        case $version_choice in
            [1-9]*)
                if [[ $version_choice -ge 1 && $version_choice -le ${#app_list[@]} ]]; then
                    local selected_app="${app_list[$((version_choice-1))]}"
                    configure_single_app_version "$selected_app"
                else
                    log_error "无效选项"; sleep 1
                fi
                ;;
            b|B) 
                log_info "返回应用选择菜单"
                break
                ;;
            *) 
                log_error "无效选项"; sleep 1
                ;;
        esac
    done
}

configure_single_app_version() {
    local app="$1"
    local current_version="${APPS_VERSIONS[$app]}"
    local image="${APPS_IMAGES[$app]}"
    
    clear
    echo "========================================"
    echo "        配置 $app 版本                "
    echo "========================================"
    echo
    echo -e "应用: ${CYAN}$app${NC} (${APPS_CONFIG[$app]})"
    echo -e "当前版本: $image:$current_version"
    echo
    log_info "版本说明:"
    log_info "  - latest: 最新版本"
    log_info "  - stable: 稳定版本"
    log_info "  - 具体版本号: 如 4.5.5"
    echo
    
    read -p "新版本 (留空保持当前版本): " new_version
    
    if [[ -n "$new_version" ]]; then
        APPS_VERSIONS[$app]="$new_version"
        log_success "$app 版本已设置为: $new_version"
        echo
        read -p "版本设置完成，按任意键继续..." -n 1
    else
        log_info "保持当前版本: $current_version"
        echo
        read -p "按任意键继续..." -n 1
    fi
}

confirm_basic_installation() {
    clear
    echo "========================================"
    echo "           基础安装确认                "
    echo "========================================"
    echo
    log_info "即将安装以下组件:"
    log_info "  ✓ Docker Engine (如未安装)"
    log_info "  ✓ Docker Compose (如未安装)"
    echo
    log_info "数据目录: $DOCKER_BASE_DIR"
    echo
    log_warning "注意: 脚本会自动检查已安装的组件并跳过重复安装"
    echo
    
    read -p "确认开始安装? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        start_basic_installation
    else
        show_main_menu
    fi
}

confirm_apps_installation() {
    clear
    echo "========================================"
    echo "           应用安装确认                "
    echo "========================================"
    echo
    log_info "即将安装以下组件:"
    log_info "  ✓ Docker Engine (如未安装)"
    log_info "  ✓ Docker Compose (如未安装)"
    echo
    log_info "选择的应用:"
    
    for app in "${!APPS_SELECTED[@]}"; do
        if [[ "${APPS_SELECTED[$app]}" == "true" ]]; then
            local version="${APPS_VERSIONS[$app]}"
            local image="${APPS_IMAGES[$app]}"
            log_info "  ✓ $app - ${APPS_CONFIG[$app]}"
            log_info "    端口: ${APPS_PORTS[$app]}, 版本: $image:$version"
        fi
    done
    
    echo
    log_info "数据目录: $DOCKER_BASE_DIR"
    log_info "共享下载目录: $DOCKER_BASE_DIR/shared/downloads"
    echo
    log_warning "注意: 脚本会自动检查已安装的组件:"
    log_warning "  - 已安装的 Docker/Docker Compose 将跳过安装"
    log_warning "  - 已运行的应用将跳过安装"
    log_warning "  - 已停止的应用将询问是否重启"
    log_warning "  - qBittorrent、Transmission、File Browser 将共享下载目录"
    echo
    
    read -p "确认开始安装? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        start_apps_installation
    else
        show_apps_selection_menu
    fi
}

show_status() {
    clear
    echo "========================================"
    echo "           当前系统状态                "
    echo "========================================"
    echo
    
    # 检查Docker
    if command -v docker > /dev/null 2>&1; then
        log_success "Docker: $(docker --version)"
        if systemctl is-active docker > /dev/null 2>&1; then
            log_success "Docker 服务: 运行中"
        else
            log_error "Docker 服务: 未运行"
        fi
    else
        log_error "Docker: 未安装"
    fi
    
    # 检查Docker Compose
    if command -v docker-compose > /dev/null 2>&1; then
        log_success "Docker Compose: $(docker-compose --version)"
    else
        log_error "Docker Compose: 未安装"
    fi
    
    echo
    log_info "Docker 容器状态:"
    
    # 获取所有运行中的容器
    local running_containers=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    if [[ -n "$running_containers" ]]; then
        echo
        log_success "运行中的容器:"
        echo "$running_containers" | head -1
        echo "$running_containers" | tail -n +2 | while IFS=$'\t' read -r name image status ports; do
            if [[ -n "$name" ]]; then
                local app_type=""
                if [[ -n "${APPS_CONFIG[$name]}" ]]; then
                    app_type=" (${APPS_CONFIG[$name]})"
                fi
                
                local port_info=""
                if [[ -n "$ports" && "$ports" != "-" ]]; then
                    port_info=" - 端口: $ports"
                fi
                
                log_success "  ✓ $name$app_type$port_info"
                log_info "    镜像: $image"
                log_info "    状态: $status"
                if [[ -n "${APPS_CONFIG[$name]}" ]]; then
                    log_info "    数据目录: $DOCKER_BASE_DIR/$name/"
                fi
                echo
            fi
        done
    else
        log_warning "  没有运行中的容器"
    fi
    
    # 获取所有停止的容器
    local stopped_containers=$(docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null)
    if [[ -n "$stopped_containers" ]] && [[ $(echo "$stopped_containers" | wc -l) -gt 1 ]]; then
        echo
        log_warning "已停止的容器:"
        echo "$stopped_containers" | tail -n +2 | while IFS=$'\t' read -r name image status; do
            if [[ -n "$name" ]]; then
                local app_type=""
                if [[ -n "${APPS_CONFIG[$name]}" ]]; then
                    app_type=" (${APPS_CONFIG[$name]})"
                fi
                log_warning "  ⚠ $name$app_type"
                log_info "    镜像: $image"
                log_info "    状态: $status"
                echo
            fi
        done
    fi
    
    echo
    log_info "系统资源信息:"
    log_info "数据目录: $DOCKER_BASE_DIR"
    if [[ -d "$DOCKER_BASE_DIR" ]]; then
        log_info "目录大小: $(du -sh "$DOCKER_BASE_DIR" 2>/dev/null | cut -f1 || echo "无法获取")"
    fi
    
    echo
    read -p "按任意键返回主菜单..." -n 1
    show_main_menu
}

# BBR 管理菜单
show_bbr_menu() {
    check_root
    
    while true; do
        clear
        echo "========================================"
        echo "         BBR/BBRx 管理菜单            "
        echo "========================================"
        echo
        
        # 显示当前状态
        echo "当前状态:"
        if check_bbr_status; then
            echo -e "  ${GREEN}✓ BBR 已启用${NC}"
        else
            echo -e "  ${RED}✗ BBR 未启用${NC}"
        fi
        
        if check_bbrx_status; then
            echo -e "  ${GREEN}✓ BBRx 已安装${NC}"
        else
            echo -e "  ${RED}✗ BBRx 未安装${NC}"
        fi
        
        echo
        log_menu "请选择操作:"
        log_menu "1) 启用 BBR"
        log_menu "2) 禁用 BBR"
        log_menu "3) 安装 BBRx"
        log_menu "4) 卸载 BBRx"
        log_menu "5) 查看详细状态"
        log_menu "6) 返回主菜单"
        echo
        
        read -p "请输入选项 (1-6): " bbr_choice
        
        case $bbr_choice in
            1) enable_bbr ;;
            2) disable_bbr ;;
            3) install_bbrx ;;
            4) uninstall_bbrx ;;
            5) show_bbr_detailed_status ;;
            6) show_main_menu; break ;;
            *) log_error "无效选项"; sleep 1 ;;
        esac
        
        echo
        read -p "按任意键继续..." -n 1
    done
}

show_bbr_detailed_status() {
    clear
    echo "========================================"
    echo "         BBR/BBRx 详细状态            "
    echo "========================================"
    echo
    
    log_info "系统信息:"
    log_info "  内核版本: $(uname -r)"
    log_info "  系统架构: $(uname -m)"
    echo
    
    log_info "BBR 状态:"
    local bbr_enabled=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local bbr_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    log_info "  默认队列规则: $bbr_enabled"
    log_info "  拥塞控制算法: $bbr_congestion"
    echo
    
    log_info "BBRx 状态:"
    if lsmod | grep -q bbrx; then
        log_success "  BBRx 内核模块已加载"
        lsmod | grep bbrx
    else
        log_warning "  BBRx 内核模块未加载"
    fi
    
    echo
    log_info "网络性能测试建议:"
    log_info "  使用 speedtest-cli 测试网络速度"
    log_info "  使用 iperf3 测试网络延迟"
    echo
}

# 卸载功能函数
get_installed_apps() {
    local installed_apps=()
    for app in "${!APPS_CONFIG[@]}"; do
        if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
            installed_apps+=("$app")
        fi
    done
    echo "${installed_apps[@]}"
}

show_uninstall_menu() {
    check_root
    
    # 获取已安装的应用列表
    local installed_apps=($(get_installed_apps))
    
    if [ ${#installed_apps[@]} -eq 0 ]; then
        clear
        echo "========================================"
        echo "           应用卸载                    "
        echo "========================================"
        echo
        log_warning "未检测到已安装的应用"
        echo
        log_info "可安装的应用列表:"
        for app in "${!APPS_CONFIG[@]}"; do
            log_info "  - $app: ${APPS_CONFIG[$app]}"
        done
        echo
        read -p "按任意键返回主菜单..." -n 1
        show_main_menu
        return
    fi
    
    # 重置卸载选择状态
    declare -A APPS_UNINSTALL_SELECTED
    for app in "${!APPS_CONFIG[@]}"; do
        APPS_UNINSTALL_SELECTED[$app]=false
    done
    
    while true; do
        clear
        echo "========================================"
        echo "           应用卸载选择                "
        echo "========================================"
        echo
        log_info "已安装的应用列表:"
        echo
        
        local i=1
        local app_list=()
        for app in "${installed_apps[@]}"; do
            app_list+=("$app")
            local status="未选择"
            local status_color="${RED}"
            local app_status=""
            
            # 检查应用运行状态
            if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
                app_status=" (运行中)"
            else
                app_status=" (已停止)"
            fi
            
            if [[ "${APPS_UNINSTALL_SELECTED[$app]}" == "true" ]]; then
                status="已选择卸载"
                status_color="${YELLOW}"
            fi
            
            echo -e "  ${CYAN}$i.${NC} $app - ${APPS_CONFIG[$app]}${app_status}"
            echo -e "     状态: ${status_color}$status${NC}"
            echo
            ((i++))
        done
        
        echo -e "  ${CYAN}a.${NC} 全选"
        echo -e "  ${CYAN}c.${NC} 清空选择"
        echo -e "  ${CYAN}u.${NC} 确认卸载"
        echo -e "  ${CYAN}b.${NC} 返回主菜单"
        echo
        
        read -p "请输入选项: " uninstall_choice
        
        case $uninstall_choice in
            [1-9]*)
                if [[ $uninstall_choice -ge 1 && $uninstall_choice -le ${#app_list[@]} ]]; then
                    local selected_app="${app_list[$((uninstall_choice-1))]}"
                    toggle_uninstall_selection "$selected_app" APPS_UNINSTALL_SELECTED
                else
                    log_error "无效选项"; sleep 1
                fi
                ;;
            a|A)
                for app in "${installed_apps[@]}"; do
                    APPS_UNINSTALL_SELECTED[$app]=true
                done
                log_success "已选择所有应用进行卸载"
                sleep 1
                ;;
            c|C)
                for app in "${installed_apps[@]}"; do
                    APPS_UNINSTALL_SELECTED[$app]=false
                done
                log_info "已清空卸载选择"
                sleep 1
                ;;
            u|U)
                if check_uninstall_apps_selected APPS_UNINSTALL_SELECTED; then
                    confirm_uninstall APPS_UNINSTALL_SELECTED
                    break
                else
                    log_error "请至少选择一个应用进行卸载"; sleep 2
                fi
                ;;
            b|B) show_main_menu; break ;;
            *) log_error "无效选项"; sleep 1 ;;
        esac
    done
}

toggle_uninstall_selection() {
    local app="$1"
    local -n selection_array=$2
    
    if [[ "${selection_array[$app]}" == "true" ]]; then
        selection_array[$app]=false
        log_info "已取消卸载选择: $app"
    else
        selection_array[$app]=true
        log_warning "已选择卸载: $app"
    fi
    sleep 1
}

check_uninstall_apps_selected() {
    local -n selection_array=$1
    for app in "${!selection_array[@]}"; do
        if [[ "${selection_array[$app]}" == "true" ]]; then
            return 0
        fi
    done
    return 1
}

confirm_uninstall() {
    local -n selection_array=$1
    
    clear
    echo "========================================"
    echo "           卸载确认                    "
    echo "========================================"
    echo
    log_warning "即将卸载以下应用:"
    echo
    
    local selected_apps=()
    for app in "${!selection_array[@]}"; do
        if [[ "${selection_array[$app]}" == "true" ]]; then
            selected_apps+=("$app")
            local app_status=""
            if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
                app_status=" (运行中)"
            else
                app_status=" (已停止)"
            fi
            log_warning "  ✗ $app - ${APPS_CONFIG[$app]}${app_status}"
        fi
    done
    
    echo
    log_error "⚠️  警告: 此操作将："
    log_error "  - 停止并删除选择的容器"
    log_error "  - 删除容器相关的 Docker 镜像"
    log_error "  - 可选择是否保留应用数据目录"
    echo
    log_info "数据目录位置: $DOCKER_BASE_DIR"
    echo
    
    read -p "确认卸载这些应用吗? (输入 'YES' 确认): " confirm_uninstall
    
    if [[ "$confirm_uninstall" == "YES" ]]; then
        start_uninstall_process selected_apps
    else
        log_info "取消卸载，返回卸载菜单"
        sleep 2
        show_uninstall_menu
    fi
}

start_uninstall_process() {
    local -n apps_to_uninstall=$1
    
    log_info "开始卸载选择的应用..."
    echo
    
    for app in "${apps_to_uninstall[@]}"; do
        uninstall_single_app "$app"
    done
    
    # 清理未使用的镜像
    echo
    read -p "是否清理未使用的 Docker 镜像? (y/N): " cleanup_images
    if [[ $cleanup_images =~ ^[Yy]$ ]]; then
        log_info "清理未使用的镜像..."
        docker image prune -f 2>/dev/null || true
        log_success "镜像清理完成"
    fi
    
    echo
    log_success "应用卸载完成！"
    echo
    read -p "按任意键返回主菜单..." -n 1
    show_main_menu
}

uninstall_single_app() {
    local app="$1"
    
    log_info "正在卸载 $app..."
    
    # 停止容器
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
        log_info "  停止容器: $app"
        docker stop "$app" 2>/dev/null || true
    fi
    
    # 删除容器
    if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${app}$"; then
        log_info "  删除容器: $app"
        docker rm "$app" 2>/dev/null || true
    fi
    
    # 删除相关镜像
    case $app in
        "portainer")
            local version="${APPS_VERSIONS[portainer]}"
            local image="${APPS_IMAGES[portainer]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
        "qbittorrent")
            local version="${APPS_VERSIONS[qbittorrent]}"
            local image="${APPS_IMAGES[qbittorrent]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
        "vertex")
            local version="${APPS_VERSIONS[vertex]}"
            local image="${APPS_IMAGES[vertex]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
        "nginx-proxy-manager")
            local version="${APPS_VERSIONS[nginx-proxy-manager]}"
            local image="${APPS_IMAGES[nginx-proxy-manager]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
        "transmission")
            local version="${APPS_VERSIONS[transmission]}"
            local image="${APPS_IMAGES[transmission]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
        "filebrowser")
            local version="${APPS_VERSIONS[filebrowser]}"
            local image="${APPS_IMAGES[filebrowser]}"
            docker rmi "$image:$version" 2>/dev/null || true
            ;;
    esac
    
    # 询问是否删除数据目录
    if [[ -d "$DOCKER_BASE_DIR/$app" ]]; then
        echo
        read -p "  是否删除 $app 的数据目录? (y/N): " delete_data
        if [[ $delete_data =~ ^[Yy]$ ]]; then
            rm -rf "$DOCKER_BASE_DIR/$app"
            log_success "  ✓ $app 数据目录已删除"
        else
            log_info "  ✓ $app 数据目录已保留: $DOCKER_BASE_DIR/$app"
        fi
    fi
    
    log_success "  ✓ $app 卸载完成"
    echo
}

# 主程序入口
main() {
    if [ $# -eq 0 ]; then
        show_main_menu
    else
        case $1 in
            --install-docker-only)
                check_root
                start_basic_installation
                ;;
            --install-apps)
                shift
                check_root
                while [ $# -gt 0 ]; do
                    case $1 in
                        --app)
                            local app="$2"
                            if [[ -n "${APPS_CONFIG[$app]}" ]]; then
                                APPS_SELECTED[$app]=true
                                log_info "已选择应用: $app"
                            else
                                log_error "未知应用: $app"
                                exit 1
                            fi
                            shift 2
                            ;;
                        --port)
                            local port_config="$2"
                            if [[ $port_config =~ ^([^:]+):([0-9]+)$ ]]; then
                                local app_name="${BASH_REMATCH[1]}"
                                local port_num="${BASH_REMATCH[2]}"
                                if [[ -n "${APPS_CONFIG[$app_name]}" ]]; then
                                    APPS_PORTS[$app_name]=$port_num
                                    log_info "已设置 $app_name 端口: $port_num"
                                else
                                    log_error "未知应用: $app_name"
                                    exit 1
                                fi
                            else
                                log_error "端口格式错误，应为 应用名:端口号"
                                exit 1
                            fi
                            shift 2
                            ;;
                        --version)
                            local version_config="$2"
                            if [[ $version_config =~ ^([^:]+):(.+)$ ]]; then
                                local app_name="${BASH_REMATCH[1]}"
                                local version_num="${BASH_REMATCH[2]}"
                                if [[ -n "${APPS_CONFIG[$app_name]}" ]]; then
                                    APPS_VERSIONS[$app_name]=$version_num
                                    log_info "已设置 $app_name 版本: $version_num"
                                else
                                    log_error "未知应用: $app_name"
                                    exit 1
                                fi
                            else
                                log_error "版本格式错误，应为 应用名:版本号"
                                exit 1
                            fi
                            shift 2
                            ;;
                        *)
                            log_error "未知参数: $1"
                            exit 1
                            ;;
                    esac
                done
                
                if ! check_apps_selected; then
                    log_error "未选择任何应用"
                    exit 1
                fi
                
                start_apps_installation
                ;;
            --uninstall-apps)
                shift
                check_root
                
                # 获取已安装的应用列表
                local installed_apps=($(get_installed_apps))
                if [ ${#installed_apps[@]} -eq 0 ]; then
                    log_error "未检测到已安装的应用"
                    exit 1
                fi
                
                # 重置卸载选择状态
                declare -A APPS_UNINSTALL_SELECTED
                for app in "${!APPS_CONFIG[@]}"; do
                    APPS_UNINSTALL_SELECTED[$app]=false
                done
                
                # 解析命令行参数
                local has_selection=false
                while [ $# -gt 0 ]; do
                    case $1 in
                        --app)
                            local app="$2"
                            if [[ -n "${APPS_CONFIG[$app]}" ]]; then
                                # 检查应用是否已安装
                                if printf '%s\n' "${installed_apps[@]}" | grep -q "^${app}$"; then
                                    APPS_UNINSTALL_SELECTED[$app]=true
                                    log_info "已选择卸载应用: $app"
                                    has_selection=true
                                else
                                    log_error "应用 $app 未安装"
                                    exit 1
                                fi
                            else
                                log_error "未知应用: $app"
                                exit 1
                            fi
                            shift 2
                            ;;
                        --all)
                            for app in "${installed_apps[@]}"; do
                                APPS_UNINSTALL_SELECTED[$app]=true
                            done
                            log_info "已选择卸载所有应用"
                            has_selection=true
                            shift
                            ;;
                        *)
                            log_error "未知参数: $1"
                            exit 1
                            ;;
                    esac
                done
                
                if ! $has_selection; then
                    log_error "请指定要卸载的应用"
                    log_info "已安装的应用: ${installed_apps[*]}"
                    exit 1
                fi
                
                # 执行卸载确认
                confirm_uninstall APPS_UNINSTALL_SELECTED
                ;;
            --uninstall)
                check_root
                show_uninstall_menu
                ;;
            --status)
                show_status
                ;;
            --enable-bbr)
                check_root
                enable_bbr
                ;;
            --disable-bbr)
                check_root
                disable_bbr
                ;;
            --install-bbrx)
                check_root
                install_bbrx
                ;;
            --uninstall-bbrx)
                check_root
                uninstall_bbrx
                ;;
            --bbr-status)
                check_bbr_status
                check_bbrx_status
                ;;
            --help|-h)
                echo "Docker 应用管理脚本 v1.0"
                echo
                echo "用法: $0 [选项]"
                echo
                echo "选项:"
                echo "  --install-docker-only     仅安装 Docker + Docker Compose"
                echo "  --install-apps            安装指定应用"
                echo "  --uninstall-apps          卸载指定应用"
                echo "  --uninstall               进入交互式卸载菜单"
                echo "  --status                  显示当前状态"
                echo "  --enable-bbr              启用 BBR 拥塞控制"
                echo "  --disable-bbr             禁用 BBR 拥塞控制"
                echo "  --install-bbrx            安装 BBRx 内核模块"
                echo "  --uninstall-bbrx          卸载 BBRx 内核模块"
                echo "  --bbr-status              查看 BBR/BBRx 状态"
                echo "  --help, -h                显示此帮助信息"
                echo
                echo "应用安装示例:"
                echo "  $0 --install-apps --app portainer --app qbittorrent"
                echo "  $0 --install-apps --app portainer --port portainer:9001"
                echo "  $0 --install-apps --app portainer --version portainer:2.19.4"
                echo "  $0 --install-apps --app qbittorrent --port qbittorrent:8081 --version qbittorrent:4.6.0"
                echo
                echo "应用卸载示例:"
                echo "  $0 --uninstall-apps --app portainer"
                echo "  $0 --uninstall-apps --app portainer --app qbittorrent"
                echo "  $0 --uninstall-apps --all"
                echo
                echo "BBR 管理示例:"
                echo "  $0 --enable-bbr"
                echo "  $0 --disable-bbr"
                echo "  $0 --install-bbrx"
                echo "  $0 --bbr-status"
                echo
                echo "可用应用:"
                for app in "${!APPS_CONFIG[@]}"; do
                    local version="${APPS_VERSIONS[$app]}"
                    local image="${APPS_IMAGES[$app]}"
                    echo "  - $app: ${APPS_CONFIG[$app]} (默认端口: ${APPS_PORTS[$app]}, 默认版本: $image:$version)"
                done
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    fi
}

# 运行主函数
main "$@" 