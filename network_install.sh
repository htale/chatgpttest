#!/bin/bash
# ============================================================
#  Sing-Box 全协议一站式管理脚本 v2.0
#  支持: Reality | Hysteria2 | VLESS+WS | Trojan+WS | TUIC | ShadowTLS
#  快捷命令: network
# ============================================================

# -------------------- 颜色与输出 --------------------
red="\033[31m\033[01m"
green="\033[32m\033[01m"
yellow="\033[33m\033[01m"
blue="\033[34m\033[01m"
cyan="\033[36m\033[01m"
reset="\033[0m"
bold="\e[1m"

warning() { echo -e "${red}$*${reset}"; }
error()   { echo -e "${red}$*${reset}"; exit 1; }
info()    { echo -e "${green}$*${reset}"; }
hint()    { echo -e "${yellow}$*${reset}"; }
note()    { echo -e "${cyan}$*${reset}"; }

show_banner() {
    clear
    echo -e "${cyan}${bold}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║    Sing-Box 全协议一站式管理脚本 v2.0       ║"
    echo "║    Reality│Hysteria2│WS+TLS│TUIC│ShadowTLS  ║"
    echo "║    快捷命令: network                         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${reset}"
}

show_notice() {
    local message="$1"
    local terminal_width
    terminal_width=$(tput cols 2>/dev/null || echo 60)
    local line
    line=$(printf "%*s" "$terminal_width" | tr ' ' '=')
    local padding=$(( (terminal_width - ${#message}) / 2 ))
    local padded_message
    padded_message="$(printf "%*s%s" $padding '' "$message")"
    warning "${bold}${line}${reset}"
    echo ""
    warning "${bold}${padded_message}${reset}"
    echo ""
    warning "${bold}${line}${reset}"
}

separator() {
    echo -e "${yellow}$(printf '%.0s─' {1..50})${reset}"
}

# -------------------- 全局变量 --------------------
SBOX_DIR="/root/sbox"
CONFIG_FILE="${SBOX_DIR}/config"
SERVER_CONFIG="${SBOX_DIR}/sbconfig_server.json"
CERT_DIR="${SBOX_DIR}/certs"
SELF_CERT_DIR="${SBOX_DIR}/self-cert"
SINGBOX_BIN="${SBOX_DIR}/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SHORTCUT_NAME="network"

# -------------------- 系统检测 --------------------
check_root() {
    [ "$(id -u)" -ne 0 ] && error "请使用 root 用户运行此脚本"
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        error "无法检测操作系统"
    fi
}

get_arch() {
    local arch
    arch=$(uname -m)
    case ${arch} in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       error "不支持的架构: ${arch}" ;;
    esac
}

get_server_ip() {
    local ipv4 ipv6
    ipv4=$(curl -s4m8 ip.sb -k 2>/dev/null)
    ipv6=$(curl -s6m8 ip.sb -k 2>/dev/null)
    if [ -n "$ipv4" ]; then
        SERVER_IP="$ipv4"
        SERVER_IP_TYPE="v4"
    elif [ -n "$ipv6" ]; then
        SERVER_IP="$ipv6"
        SERVER_IP_TYPE="v6"
    else
        error "无法获取服务器 IP"
    fi
}

check_ip_blocked() {
    local ipv4
    ipv4=$(curl -s4m8 ip.sb -k 2>/dev/null)
    if [ -z "$ipv4" ]; then
        echo "noipv4"
        return
    fi
    # 简单检测: 从国内测试点 ping
    if ! curl -s --max-time 5 "https://api.live.bilibili.com/ip_service/v1/ip_service/getIpAddr" >/dev/null 2>&1; then
        echo "unknown"
        return
    fi
    echo "ok"
}

# -------------------- 包管理 --------------------
install_pkgs() {
    local pkgs=("qrencode" "jq" "iptables" "openssl" "curl" "wget")
    for pkg in "${pkgs[@]}"; do
        if command -v "$pkg" &>/dev/null; then
            continue
        fi
        hint "安装 $pkg..."
        if command -v apt &>/dev/null; then
            apt update -qq >/dev/null 2>&1 && apt install -y -qq "$pkg" >/dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q "$pkg" >/dev/null 2>&1
        elif command -v dnf &>/dev/null; then
            dnf install -y -q "$pkg" >/dev/null 2>&1
        else
            error "无法安装 $pkg，请手动安装后重试"
        fi
    done
    info "依赖检查完成"
}

# -------------------- sing-box 安装 --------------------
install_singbox() {
    echo ""
    hint "请选择 sing-box 版本:"
    echo "  1. 正式版 (推荐)"
    echo "  2. 测试版 (Pre-release)"
    read -rp "选择 [1-2, 默认1]: " version_choice
    version_choice=${version_choice:-1}

    local api_url="https://api.github.com/repos/SagerNet/sing-box/releases"
    if [ "$version_choice" -eq 2 ]; then
        info "获取测试版..."
        latest_version_tag=$(curl -s "$api_url" | jq -r '[.[] | select(.prerelease==true)][0].tag_name')
    else
        info "获取正式版..."
        latest_version_tag=$(curl -s "$api_url" | jq -r '[.[] | select(.prerelease==false)][0].tag_name')
    fi

    [ -z "$latest_version_tag" ] || [ "$latest_version_tag" = "null" ] && error "获取版本失败"

    local latest_version=${latest_version_tag#v}
    local arch
    arch=$(get_arch)
    local package_name="sing-box-${latest_version}-linux-${arch}"
    local url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"

    info "下载 sing-box ${latest_version} (${arch})..."
    curl -sLo "/tmp/${package_name}.tar.gz" "$url" || error "下载失败"
    tar -xzf "/tmp/${package_name}.tar.gz" -C /tmp
    mkdir -p "${SBOX_DIR}"
    mv "/tmp/${package_name}/sing-box" "${SINGBOX_BIN}"
    rm -rf "/tmp/${package_name}.tar.gz" "/tmp/${package_name}"
    chown root:root "${SINGBOX_BIN}"
    chmod +x "${SINGBOX_BIN}"
    info "sing-box ${latest_version} 安装完成"
}

# -------------------- 快捷命令 --------------------
install_shortcut() {
    cat > "${SBOX_DIR}/${SHORTCUT_NAME}.sh" << 'SHORTCUT_EOF'
#!/usr/bin/env bash
bash <(cat /root/sbox/install_local.sh) "$1"
SHORTCUT_EOF
    # 同时支持远程和本地
    cp "$0" "${SBOX_DIR}/install_local.sh" 2>/dev/null
    chmod +x "${SBOX_DIR}/${SHORTCUT_NAME}.sh"
    ln -sf "${SBOX_DIR}/${SHORTCUT_NAME}.sh" "/usr/bin/${SHORTCUT_NAME}"
}

# -------------------- systemd 服务 --------------------
create_service() {
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${SBOX_DIR}
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SINGBOX_BIN} run -c ${SERVER_CONFIG}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1
}

reload_singbox() {
    if ${SINGBOX_BIN} check -c ${SERVER_CONFIG}; then
        info "配置校验通过，重启服务..."
        systemctl restart sing-box && info "服务启动成功" || error "服务启动失败"
    else
        error "配置校验失败，请检查配置文件"
    fi
}

# -------------------- 端口管理 --------------------
generate_port() {
    local protocol="$1"
    local port
    while :; do
        port=$((RANDOM % 10001 + 10000))
        read -rp "请为 ${protocol} 输入端口 [默认随机 ${port}]: " user_input
        port=${user_input:-$port}
        if ss -tuln | grep -q ":${port}\b"; then
            warning "端口 ${port} 已占用，请重新输入"
        else
            echo "$port"
            return
        fi
    done
}

modify_port() {
    local current_port="$1"
    local protocol="$2"
    while :; do
        read -rp "${protocol} 端口 [当前: ${current_port}, 回车不改]: " modified_port
        modified_port=${modified_port:-$current_port}
        if [ "$modified_port" -eq "$current_port" ] || ! ss -tuln | grep -q ":${modified_port}\b"; then
            echo "$modified_port"
            return
        fi
        warning "端口 ${modified_port} 已占用"
    done
}

# -------------------- 证书管理 --------------------
generate_self_signed_cert() {
    local domain="${1:-bing.com}"
    mkdir -p "${SELF_CERT_DIR}"
    openssl ecparam -genkey -name prime256v1 -out "${SELF_CERT_DIR}/private.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "${SELF_CERT_DIR}/private.key" \
        -out "${SELF_CERT_DIR}/cert.pem" -subj "/CN=${domain}" 2>/dev/null
    info "自签证书生成完成: ${SELF_CERT_DIR}/"
}

apply_acme_cert() {
    local domain="$1"
    [ -z "$domain" ] && error "域名不能为空"

    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        hint "安装 acme.sh..."
        curl -s https://get.acme.sh | sh -s email=admin@${domain} >/dev/null 2>&1
    fi

    mkdir -p "${CERT_DIR}"
    info "申请证书 (${domain})..."
    ~/.acme.sh/acme.sh --issue -d "${domain}" --standalone --keylength ec-256 --force || error "证书申请失败"
    ~/.acme.sh/acme.sh --install-cert -d "${domain}" --ecc \
        --key-file "${CERT_DIR}/private.key" \
        --fullchain-file "${CERT_DIR}/cert.pem" \
        --reloadcmd "systemctl restart sing-box" || error "证书安装失败"
    info "ACME 证书安装完成: ${CERT_DIR}/"
}

apply_cf_origin_cert() {
    echo ""
    hint "请在 Cloudflare Dashboard 生成 Origin Certificate"
    hint "SSL/TLS → Origin Server → Create Certificate"
    echo ""
    read -rp "请粘贴证书内容文件路径 (cert.pem): " cf_cert_path
    read -rp "请粘贴私钥内容文件路径 (private.key): " cf_key_path
    mkdir -p "${CERT_DIR}"
    if [ -f "$cf_cert_path" ] && [ -f "$cf_key_path" ]; then
        cp "$cf_cert_path" "${CERT_DIR}/cert.pem"
        cp "$cf_key_path" "${CERT_DIR}/private.key"
        info "Cloudflare Origin 证书已安装: ${CERT_DIR}/"
    else
        error "证书文件不存在"
    fi
}

select_cert_method() {
    local need_real_cert="$1"  # "yes" if CDN protocols selected
    echo ""
    hint "选择证书方式:"
    echo "  1. 自签证书 (无需域名，用于 Hysteria2/TUIC)"
    if [ "$need_real_cert" = "yes" ]; then
        echo "  2. Let's Encrypt (自动申请，需要域名)"
        echo "  3. Cloudflare Origin Certificate (推荐CDN用户)"
    fi
    read -rp "选择 [默认1]: " cert_choice
    cert_choice=${cert_choice:-1}

    case $cert_choice in
        1)
            read -rp "自签证书域名 [默认 bing.com]: " self_domain
            self_domain=${self_domain:-bing.com}
            generate_self_signed_cert "$self_domain"
            CERT_PATH="${SELF_CERT_DIR}/cert.pem"
            KEY_PATH="${SELF_CERT_DIR}/private.key"
            HY_SERVER_NAME="$self_domain"
            ;;
        2)
            read -rp "请输入你的域名: " acme_domain
            [ -z "$acme_domain" ] && error "域名不能为空"
            apply_acme_cert "$acme_domain"
            CERT_PATH="${CERT_DIR}/cert.pem"
            KEY_PATH="${CERT_DIR}/private.key"
            CDN_DOMAIN="$acme_domain"
            HY_SERVER_NAME="$acme_domain"
            ;;
        3)
            apply_cf_origin_cert
            read -rp "请输入你的域名: " cf_domain
            [ -z "$cf_domain" ] && error "域名不能为空"
            CERT_PATH="${CERT_DIR}/cert.pem"
            KEY_PATH="${CERT_DIR}/private.key"
            CDN_DOMAIN="$cf_domain"
            HY_SERVER_NAME="$cf_domain"
            ;;
    esac
}

# -------------------- 协议选择 --------------------
select_protocols() {
    echo ""
    show_notice "选择要启用的协议 (输入数字，空格分隔)"
    echo ""
    note "  === 直连协议 (需要IP未被墙) ==="
    echo "  1. VLESS + Reality        (TCP直连，强伪装)"
    echo "  2. Hysteria2              (UDP高速，抗丢包)"
    echo ""
    note "  === CDN协议 (IP被墙可用) ==="
    echo "  3. VLESS + WebSocket + TLS  (过Cloudflare CDN)"
    echo "  4. Trojan + WebSocket + TLS (过Cloudflare CDN)"
    echo ""
    note "  === 其他协议 ==="
    echo "  5. TUIC v5                (UDP高速，类Hysteria)"
    echo "  6. ShadowTLS v3 + SS      (强伪装TCP)"
    echo ""
    hint "  推荐组合: 被墙选 3  |  未被墙选 1+2  |  全能选 1+2+3"
    echo ""
    read -rp "请输入选择 (例: 1 2 3): " -a protocol_choices

    # 初始化协议开关
    ENABLE_REALITY=false
    ENABLE_HY2=false
    ENABLE_VLESS_WS=false
    ENABLE_TROJAN_WS=false
    ENABLE_TUIC=false
    ENABLE_SHADOWTLS=false
    NEED_REAL_CERT="no"

    for choice in "${protocol_choices[@]}"; do
        case $choice in
            1) ENABLE_REALITY=true ;;
            2) ENABLE_HY2=true ;;
            3) ENABLE_VLESS_WS=true; NEED_REAL_CERT="yes" ;;
            4) ENABLE_TROJAN_WS=true; NEED_REAL_CERT="yes" ;;
            5) ENABLE_TUIC=true ;;
            6) ENABLE_SHADOWTLS=true ;;
            *) warning "忽略无效选项: $choice" ;;
        esac
    done

    # 至少选一个
    if ! $ENABLE_REALITY && ! $ENABLE_HY2 && ! $ENABLE_VLESS_WS && \
       ! $ENABLE_TROJAN_WS && ! $ENABLE_TUIC && ! $ENABLE_SHADOWTLS; then
        error "至少选择一个协议"
    fi

    echo ""
    info "已选协议:"
    $ENABLE_REALITY   && info "  ✓ VLESS Reality"
    $ENABLE_HY2       && info "  ✓ Hysteria2"
    $ENABLE_VLESS_WS  && info "  ✓ VLESS + WS + TLS"
    $ENABLE_TROJAN_WS && info "  ✓ Trojan + WS + TLS"
    $ENABLE_TUIC      && info "  ✓ TUIC v5"
    $ENABLE_SHADOWTLS && info "  ✓ ShadowTLS v3"
    echo ""
}

# -------------------- 各协议参数生成 --------------------
configure_reality() {
    echo ""
    warning "配置 VLESS Reality..."
    local key_pair
    key_pair=$(${SINGBOX_BIN} generate reality-keypair)
    REALITY_PRIVATE_KEY=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    REALITY_PUBLIC_KEY=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
    REALITY_UUID=$(${SINGBOX_BIN} generate uuid)
    REALITY_SHORT_ID=$(${SINGBOX_BIN} generate rand --hex 8)
    REALITY_PORT=$(generate_port "Reality")

    REALITY_SERVER_NAME="itunes.apple.com"
    while :; do
        read -rp "偷取证书域名 (需支持TLS1.3+H2) [默认: ${REALITY_SERVER_NAME}]: " input_sni
        REALITY_SERVER_NAME=${input_sni:-$REALITY_SERVER_NAME}
        if curl --tlsv1.3 --http2 -sI "https://${REALITY_SERVER_NAME}" | grep -q "HTTP/2"; then
            break
        fi
        warning "域名不支持 TLS 1.3 / HTTP/2，请重新输入"
    done
    info "Reality 配置完成: 端口=${REALITY_PORT} SNI=${REALITY_SERVER_NAME}"
}

configure_hy2() {
    echo ""
    warning "配置 Hysteria2..."
    HY2_PASSWORD=$(${SINGBOX_BIN} generate rand --hex 8)
    HY2_PORT=$(generate_port "Hysteria2")
    info "Hysteria2 配置完成: 端口=${HY2_PORT}"
}

configure_vless_ws() {
    echo ""
    warning "配置 VLESS + WebSocket + TLS..."
    VLESS_WS_UUID=$(${SINGBOX_BIN} generate uuid)
    VLESS_WS_PORT=443
    read -rp "监听端口 [默认 443]: " input_port
    VLESS_WS_PORT=${input_port:-443}
    VLESS_WS_PATH="/$(${SINGBOX_BIN} generate rand --hex 6)"
    read -rp "WebSocket 路径 [默认 ${VLESS_WS_PATH}]: " input_path
    VLESS_WS_PATH=${input_path:-$VLESS_WS_PATH}
    if [ -z "$CDN_DOMAIN" ]; then
        read -rp "请输入你的 Cloudflare 域名: " CDN_DOMAIN
        [ -z "$CDN_DOMAIN" ] && error "CDN协议必须提供域名"
    fi
    info "VLESS+WS 配置完成: 域名=${CDN_DOMAIN} 端口=${VLESS_WS_PORT} 路径=${VLESS_WS_PATH}"
}

configure_trojan_ws() {
    echo ""
    warning "配置 Trojan + WebSocket + TLS..."
    TROJAN_WS_PASSWORD=$(${SINGBOX_BIN} generate rand --hex 8)
    TROJAN_WS_PORT=${VLESS_WS_PORT:-443}
    if $ENABLE_VLESS_WS && [ "$TROJAN_WS_PORT" -eq "$VLESS_WS_PORT" ]; then
        hint "VLESS+WS 已占用 ${VLESS_WS_PORT}，Trojan+WS 将复用同端口不同路径"
        TROJAN_WS_SHARE_PORT=true
    else
        read -rp "监听端口 [默认 ${TROJAN_WS_PORT}]: " input_port
        TROJAN_WS_PORT=${input_port:-$TROJAN_WS_PORT}
        TROJAN_WS_SHARE_PORT=false
    fi
    TROJAN_WS_PATH="/$(${SINGBOX_BIN} generate rand --hex 6)"
    read -rp "WebSocket 路径 [默认 ${TROJAN_WS_PATH}]: " input_path
    TROJAN_WS_PATH=${input_path:-$TROJAN_WS_PATH}
    if [ -z "$CDN_DOMAIN" ]; then
        read -rp "请输入你的 Cloudflare 域名: " CDN_DOMAIN
        [ -z "$CDN_DOMAIN" ] && error "CDN协议必须提供域名"
    fi
    info "Trojan+WS 配置完成: 域名=${CDN_DOMAIN} 端口=${TROJAN_WS_PORT} 路径=${TROJAN_WS_PATH}"
}

configure_tuic() {
    echo ""
    warning "配置 TUIC v5..."
    TUIC_UUID=$(${SINGBOX_BIN} generate uuid)
    TUIC_PASSWORD=$(${SINGBOX_BIN} generate rand --hex 8)
    TUIC_PORT=$(generate_port "TUIC")
    info "TUIC 配置完成: 端口=${TUIC_PORT}"
}

configure_shadowtls() {
    echo ""
    warning "配置 ShadowTLS v3 + Shadowsocks..."
    SHADOWTLS_PASSWORD=$(${SINGBOX_BIN} generate rand --base64 16)
    SS_PASSWORD=$(${SINGBOX_BIN} generate rand --base64 16)
    SHADOWTLS_PORT=$(generate_port "ShadowTLS")
    SHADOWTLS_SNI="addons.mozilla.org"
    read -rp "ShadowTLS 握手域名 [默认 ${SHADOWTLS_SNI}]: " input_sni
    SHADOWTLS_SNI=${input_sni:-$SHADOWTLS_SNI}
    info "ShadowTLS 配置完成: 端口=${SHADOWTLS_PORT} SNI=${SHADOWTLS_SNI}"
}

# -------------------- 生成服务端配置 --------------------
generate_server_config() {
    info "生成服务端配置..."

    # 构建 inbounds 数组
    local inbounds="["
    local first=true

    # --- Reality ---
    if $ENABLE_REALITY; then
        $first || inbounds+=","
        first=false
        inbounds+='
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": '"${REALITY_PORT}"',
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"uuid": "'"${REALITY_UUID}"'", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "'"${REALITY_SERVER_NAME}"'",
        "reality": {
          "enabled": true,
          "handshake": {"server": "'"${REALITY_SERVER_NAME}"'", "server_port": 443},
          "private_key": "'"${REALITY_PRIVATE_KEY}"'",
          "short_id": ["'"${REALITY_SHORT_ID}"'"]
        }
      }
    }'
    fi

    # --- Hysteria2 ---
    if $ENABLE_HY2; then
        $first || inbounds+=","
        first=false
        inbounds+='
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": '"${HY2_PORT}"',
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"password": "'"${HY2_PASSWORD}"'"}],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "'"${CERT_PATH}"'",
        "key_path": "'"${KEY_PATH}"'"
      }
    }'
    fi

    # --- VLESS + WS + TLS ---
    if $ENABLE_VLESS_WS; then
        $first || inbounds+=","
        first=false
        inbounds+='
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "::",
      "listen_port": '"${VLESS_WS_PORT}"',
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"uuid": "'"${VLESS_WS_UUID}"'", "flow": ""}],
      "transport": {
        "type": "ws",
        "path": "'"${VLESS_WS_PATH}"'",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "'"${CERT_PATH}"'",
        "key_path": "'"${KEY_PATH}"'"
      }
    }'
    fi

    # --- Trojan + WS + TLS ---
    if $ENABLE_TROJAN_WS; then
        # 如果和VLESS+WS共享端口，使用multiplex监听方式（不同path路由）
        # 这里简化处理：如果端口不同则独立监听
        if [ "${TROJAN_WS_SHARE_PORT}" = "true" ]; then
            hint "Trojan+WS 与 VLESS+WS 共享端口 ${VLESS_WS_PORT}，使用不同路径区分"
            # 修改VLESS+WS为不带TLS，外层统一用TLS（需要用multiplex）
            # 简化方案：Trojan使用不同端口
            TROJAN_WS_PORT=$((VLESS_WS_PORT + 1))
            hint "自动分配 Trojan+WS 端口: ${TROJAN_WS_PORT}"
        fi
        $first || inbounds+=","
        first=false
        inbounds+='
    {
      "type": "trojan",
      "tag": "trojan-ws-in",
      "listen": "::",
      "listen_port": '"${TROJAN_WS_PORT}"',
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"password": "'"${TROJAN_WS_PASSWORD}"'"}],
      "transport": {
        "type": "ws",
        "path": "'"${TROJAN_WS_PATH}"'"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "'"${CERT_PATH}"'",
        "key_path": "'"${KEY_PATH}"'"
      }
    }'
    fi

    # --- TUIC v5 ---
    if $ENABLE_TUIC; then
        $first || inbounds+=","
        first=false
        inbounds+='
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": '"${TUIC_PORT}"',
      "sniff": true,
      "sniff_override_destination": true,
      "users": [{"uuid": "'"${TUIC_UUID}"'", "password": "'"${TUIC_PASSWORD}"'"}],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "'"${CERT_PATH}"'",
        "key_path": "'"${KEY_PATH}"'"
      }
    }'
    fi

    # --- ShadowTLS v3 + SS ---
    if $ENABLE_SHADOWTLS; then
        $first || inbounds+=","
        first=false
        # ShadowTLS 外层
        inbounds+='
    {
      "type": "shadowtls",
      "tag": "shadowtls-in",
      "listen": "::",
      "listen_port": '"${SHADOWTLS_PORT}"',
      "version": 3,
      "users": [{"password": "'"${SHADOWTLS_PASSWORD}"'"}],
      "handshake": {"server": "'"${SHADOWTLS_SNI}"'", "server_port": 443},
      "strict_mode": true,
      "detour": "shadowsocks-in"
    },
    {
      "type": "shadowsocks",
      "tag": "shadowsocks-in",
      "listen": "127.0.0.1",
      "listen_port": 0,
      "sniff": true,
      "sniff_override_destination": true,
      "method": "2022-blake3-aes-128-gcm",
      "password": "'"${SS_PASSWORD}"'"
    }'
    fi

    inbounds+="
  ]"

    # 完整配置
    cat > "${SERVER_CONFIG}" <<CONFIGEOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": ${inbounds},
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ]
}
CONFIGEOF

    # 验证 JSON
    if ! jq . "${SERVER_CONFIG}" >/dev/null 2>&1; then
        error "配置文件 JSON 格式错误"
    fi
    info "服务端配置生成完成"
}

# -------------------- 保存安装信息 --------------------
save_install_config() {
    cat > "${CONFIG_FILE}" <<EOF
# ===== Sing-Box 全协议管理配置 =====
SERVER_IP='${SERVER_IP}'
# 协议开关
ENABLE_REALITY=${ENABLE_REALITY}
ENABLE_HY2=${ENABLE_HY2}
ENABLE_VLESS_WS=${ENABLE_VLESS_WS}
ENABLE_TROJAN_WS=${ENABLE_TROJAN_WS}
ENABLE_TUIC=${ENABLE_TUIC}
ENABLE_SHADOWTLS=${ENABLE_SHADOWTLS}
# Reality
REALITY_PORT='${REALITY_PORT:-}'
REALITY_UUID='${REALITY_UUID:-}'
REALITY_PUBLIC_KEY='${REALITY_PUBLIC_KEY:-}'
REALITY_SHORT_ID='${REALITY_SHORT_ID:-}'
REALITY_SERVER_NAME='${REALITY_SERVER_NAME:-}'
# Hysteria2
HY2_PORT='${HY2_PORT:-}'
HY2_PASSWORD='${HY2_PASSWORD:-}'
HY_SERVER_NAME='${HY_SERVER_NAME:-}'
HY_HOPPING=FALSE
# VLESS+WS
VLESS_WS_PORT='${VLESS_WS_PORT:-}'
VLESS_WS_UUID='${VLESS_WS_UUID:-}'
VLESS_WS_PATH='${VLESS_WS_PATH:-}'
CDN_DOMAIN='${CDN_DOMAIN:-}'
# Trojan+WS
TROJAN_WS_PORT='${TROJAN_WS_PORT:-}'
TROJAN_WS_PASSWORD='${TROJAN_WS_PASSWORD:-}'
TROJAN_WS_PATH='${TROJAN_WS_PATH:-}'
# TUIC
TUIC_PORT='${TUIC_PORT:-}'
TUIC_UUID='${TUIC_UUID:-}'
TUIC_PASSWORD='${TUIC_PASSWORD:-}'
# ShadowTLS
SHADOWTLS_PORT='${SHADOWTLS_PORT:-}'
SHADOWTLS_PASSWORD='${SHADOWTLS_PASSWORD:-}'
SHADOWTLS_SNI='${SHADOWTLS_SNI:-}'
SS_PASSWORD='${SS_PASSWORD:-}'
# 证书
CERT_PATH='${CERT_PATH:-}'
KEY_PATH='${KEY_PATH:-}'
# WARP
WARP_ENABLE=FALSE
WARP_MODE=0
WARP_OPTION=0
EOF
    info "安装配置已保存"
}

# -------------------- 加载已有配置 --------------------
load_config() {
    [ -f "${CONFIG_FILE}" ] && source "${CONFIG_FILE}"
}

# -------------------- 客户端配置输出 --------------------
show_client_configuration() {
    load_config
    local server_ip="${SERVER_IP}"

    echo ""
    echo ""

    # === Reality ===
    if [ "${ENABLE_REALITY}" = "true" ]; then
        local reality_port reality_uuid public_key short_id reality_sni
        reality_port=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen_port' "${SERVER_CONFIG}")
        reality_uuid=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .users[0].uuid' "${SERVER_CONFIG}")
        public_key="${REALITY_PUBLIC_KEY}"
        short_id=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.reality.short_id[0]' "${SERVER_CONFIG}")
        reality_sni=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.server_name' "${SERVER_CONFIG}")

        local reality_link="vless://${reality_uuid}@${server_ip}:${reality_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Reality"

        show_notice "VLESS Reality"
        echo ""
        info "通用链接:"
        echo "${reality_link}"
        echo ""
        info "二维码:"
        qrencode -t UTF8 "${reality_link}" 2>/dev/null
        echo ""
        info "参数:"
        separator
        echo "  地址: ${server_ip}"
        echo "  端口: ${reality_port}"
        echo "  UUID: ${reality_uuid}"
        echo "  流控: xtls-rprx-vision"
        echo "  SNI:  ${reality_sni}"
        echo "  PublicKey: ${public_key}"
        echo "  ShortID:   ${short_id}"
        echo "  指纹: chrome"
        separator
        echo ""
    fi

    # === Hysteria2 ===
    if [ "${ENABLE_HY2}" = "true" ]; then
        local hy_port hy_password hy_sni
        hy_port=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "${SERVER_CONFIG}")
        hy_password=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' "${SERVER_CONFIG}")
        hy_sni="${HY_SERVER_NAME}"

        local ishopping="${HY_HOPPING}"
        local hy2_link
        if [ "$ishopping" = "TRUE" ]; then
            local hopping_range
            hopping_range=$(iptables -t nat -L -n -v 2>/dev/null | grep "udp" | grep -oP 'dpts:\K\d+:\d+')
            [ -z "$hopping_range" ] && hopping_range=$(ip6tables -t nat -L -n -v 2>/dev/null | grep "udp" | grep -oP 'dpts:\K\d+:\d+')
            if [ -n "$hopping_range" ]; then
                local formatted_range
                formatted_range=$(echo "$hopping_range" | sed 's/:/-/')
                hy2_link="hysteria2://${hy_password}@${server_ip}:${hy_port}?insecure=1&sni=${hy_sni}&mport=${hy_port},${formatted_range}#Hysteria2"
            else
                hy2_link="hysteria2://${hy_password}@${server_ip}:${hy_port}?insecure=1&sni=${hy_sni}#Hysteria2"
            fi
        else
            hy2_link="hysteria2://${hy_password}@${server_ip}:${hy_port}?insecure=1&sni=${hy_sni}#Hysteria2"
        fi

        show_notice "Hysteria2"
        echo ""
        info "通用链接:"
        echo "${hy2_link}"
        echo ""
        info "二维码:"
        qrencode -t UTF8 "${hy2_link}" 2>/dev/null
        echo ""
        info "参数:"
        separator
        echo "  地址: ${server_ip}"
        echo "  端口: ${hy_port}"
        echo "  密码: ${hy_password}"
        echo "  SNI:  ${hy_sni}"
        echo "  跳过证书验证: true"
        if [ "$ishopping" = "TRUE" ] && [ -n "$hopping_range" ]; then
            echo "  端口跳跃: ${formatted_range}"
        fi
        separator
        echo ""
    fi

    # === VLESS + WS + TLS ===
    if [ "${ENABLE_VLESS_WS}" = "true" ]; then
        local vws_port vws_uuid vws_path cdn_domain
        vws_port=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .listen_port' "${SERVER_CONFIG}")
        vws_uuid=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .users[0].uuid' "${SERVER_CONFIG}")
        vws_path=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .transport.path' "${SERVER_CONFIG}")
        cdn_domain="${CDN_DOMAIN}"

        local vless_ws_link="vless://${vws_uuid}@${cdn_domain}:${vws_port}?encryption=none&security=tls&sni=${cdn_domain}&type=ws&host=${cdn_domain}&path=${vws_path}#VLESS-WS-CDN"

        show_notice "VLESS + WebSocket + TLS (CDN)"
        echo ""
        info "通用链接:"
        echo "${vless_ws_link}"
        echo ""
        info "二维码:"
        qrencode -t UTF8 "${vless_ws_link}" 2>/dev/null
        echo ""
        info "参数:"
        separator
        echo "  地址: ${cdn_domain} (Cloudflare CDN)"
        echo "  端口: ${vws_port}"
        echo "  UUID: ${vws_uuid}"
        echo "  传输: WebSocket"
        echo "  路径: ${vws_path}"
        echo "  TLS:  开启"
        echo "  SNI:  ${cdn_domain}"
        separator
        echo ""
    fi

    # === Trojan + WS + TLS ===
    if [ "${ENABLE_TROJAN_WS}" = "true" ]; then
        local tws_port tws_password tws_path cdn_domain
        tws_port=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .listen_port' "${SERVER_CONFIG}")
        tws_password=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .users[0].password' "${SERVER_CONFIG}")
        tws_path=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .transport.path' "${SERVER_CONFIG}")
        cdn_domain="${CDN_DOMAIN}"

        local trojan_ws_link="trojan://${tws_password}@${cdn_domain}:${tws_port}?security=tls&sni=${cdn_domain}&type=ws&host=${cdn_domain}&path=${tws_path}#Trojan-WS-CDN"

        show_notice "Trojan + WebSocket + TLS (CDN)"
        echo ""
        info "通用链接:"
        echo "${trojan_ws_link}"
        echo ""
        info "二维码:"
        qrencode -t UTF8 "${trojan_ws_link}" 2>/dev/null
        echo ""
        info "参数:"
        separator
        echo "  地址: ${cdn_domain} (Cloudflare CDN)"
        echo "  端口: ${tws_port}"
        echo "  密码: ${tws_password}"
        echo "  传输: WebSocket"
        echo "  路径: ${tws_path}"
        echo "  TLS:  开启"
        echo "  SNI:  ${cdn_domain}"
        separator
        echo ""
    fi

    # === TUIC v5 ===
    if [ "${ENABLE_TUIC}" = "true" ]; then
        local tuic_port tuic_uuid tuic_password tuic_sni
        tuic_port=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .listen_port' "${SERVER_CONFIG}")
        tuic_uuid=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].uuid' "${SERVER_CONFIG}")
        tuic_password=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].password' "${SERVER_CONFIG}")
        tuic_sni="${HY_SERVER_NAME}"

        local tuic_link="tuic://${tuic_uuid}:${tuic_password}@${server_ip}:${tuic_port}?alpn=h3&congestion_control=bbr&udp_relay_mode=native&sni=${tuic_sni}&allow_insecure=1#TUIC-v5"

        show_notice "TUIC v5"
        echo ""
        info "通用链接:"
        echo "${tuic_link}"
        echo ""
        info "二维码:"
        qrencode -t UTF8 "${tuic_link}" 2>/dev/null
        echo ""
        info "参数:"
        separator
        echo "  地址: ${server_ip}"
        echo "  端口: ${tuic_port}"
        echo "  UUID: ${tuic_uuid}"
        echo "  密码: ${tuic_password}"
        echo "  拥塞控制: bbr"
        echo "  ALPN: h3"
        echo "  SNI:  ${tuic_sni}"
        echo "  跳过证书验证: true"
        separator
        echo ""
    fi

    # === ShadowTLS ===
    if [ "${ENABLE_SHADOWTLS}" = "true" ]; then
        local stls_port stls_password stls_sni ss_password
        stls_port=$(jq -r '.inbounds[] | select(.tag=="shadowtls-in") | .listen_port' "${SERVER_CONFIG}")
        stls_password="${SHADOWTLS_PASSWORD}"
        stls_sni="${SHADOWTLS_SNI}"
        ss_password="${SS_PASSWORD}"

        show_notice "ShadowTLS v3 + Shadowsocks"
        echo ""
        warning "此协议无标准通用链接，请手动配置客户端"
        echo ""
        info "参数:"
        separator
        echo "  地址: ${server_ip}"
        echo "  端口: ${stls_port}"
        echo "  --- ShadowTLS ---"
        echo "  版本: 3"
        echo "  密码: ${stls_password}"
        echo "  SNI:  ${stls_sni}"
        echo "  --- Shadowsocks ---"
        echo "  加密: 2022-blake3-aes-128-gcm"
        echo "  密码: ${ss_password}"
        separator
        echo ""
    fi

    # === 聚合 Clash Meta 配置 ===
    show_clash_meta_config

    # === 聚合 Sing-Box 客户端配置 ===
    show_singbox_client_config
}

# -------------------- Clash Meta 聚合配置 --------------------
show_clash_meta_config() {
    load_config
    show_notice "Clash Meta 客户端配置"

    local proxies=""
    local proxy_names=""

    if [ "${ENABLE_REALITY}" = "true" ]; then
        local rp ru rsn rpk rsi
        rp=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen_port' "${SERVER_CONFIG}")
        ru=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .users[0].uuid' "${SERVER_CONFIG}")
        rsn=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.server_name' "${SERVER_CONFIG}")
        rpk="${REALITY_PUBLIC_KEY}"
        rsi=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.reality.short_id[0]' "${SERVER_CONFIG}")
        proxies+="
  - name: Reality
    type: vless
    server: ${SERVER_IP}
    port: ${rp}
    uuid: ${ru}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: ${rsn}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${rpk}
      short-id: ${rsi}
"
        proxy_names+="      - Reality\n"
    fi

    if [ "${ENABLE_HY2}" = "true" ]; then
        local hp hpw hsn
        hp=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "${SERVER_CONFIG}")
        hpw=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' "${SERVER_CONFIG}")
        hsn="${HY_SERVER_NAME}"
        proxies+="
  - name: Hysteria2
    type: hysteria2
    server: ${SERVER_IP}
    port: ${hp}
    password: ${hpw}
    sni: ${hsn}
    skip-cert-verify: true
    alpn:
      - h3
"
        proxy_names+="      - Hysteria2\n"
    fi

    if [ "${ENABLE_VLESS_WS}" = "true" ]; then
        local vp vu vpath
        vp=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .listen_port' "${SERVER_CONFIG}")
        vu=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .users[0].uuid' "${SERVER_CONFIG}")
        vpath=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .transport.path' "${SERVER_CONFIG}")
        proxies+="
  - name: VLESS-CDN
    type: vless
    server: ${CDN_DOMAIN}
    port: ${vp}
    uuid: ${vu}
    network: ws
    tls: true
    udp: false
    servername: ${CDN_DOMAIN}
    ws-opts:
      path: ${vpath}
      headers:
        Host: ${CDN_DOMAIN}
"
        proxy_names+="      - VLESS-CDN\n"
    fi

    if [ "${ENABLE_TROJAN_WS}" = "true" ]; then
        local tp tpw tpath
        tp=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .listen_port' "${SERVER_CONFIG}")
        tpw=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .users[0].password' "${SERVER_CONFIG}")
        tpath=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .transport.path' "${SERVER_CONFIG}")
        proxies+="
  - name: Trojan-CDN
    type: trojan
    server: ${CDN_DOMAIN}
    port: ${tp}
    password: ${tpw}
    network: ws
    sni: ${CDN_DOMAIN}
    udp: false
    skip-cert-verify: false
    ws-opts:
      path: ${tpath}
      headers:
        Host: ${CDN_DOMAIN}
"
        proxy_names+="      - Trojan-CDN\n"
    fi

    if [ "${ENABLE_TUIC}" = "true" ]; then
        local tup tuu tupw tusn
        tup=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .listen_port' "${SERVER_CONFIG}")
        tuu=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].uuid' "${SERVER_CONFIG}")
        tupw=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].password' "${SERVER_CONFIG}")
        tusn="${HY_SERVER_NAME}"
        proxies+="
  - name: TUIC
    type: tuic
    server: ${SERVER_IP}
    port: ${tup}
    uuid: ${tuu}
    password: ${tupw}
    alpn:
      - h3
    congestion-controller: bbr
    udp-relay-mode: native
    reduce-rtt: true
    sni: ${tusn}
    skip-cert-verify: true
"
        proxy_names+="      - TUIC\n"
    fi

    cat <<EOF

port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
ipv6: true

dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:${proxies}
proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - 自动选择
$(echo -e "${proxy_names}")      - DIRECT

  - name: 自动选择
    type: url-test
    proxies:
$(echo -e "${proxy_names}")    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50

rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
EOF
    echo ""
}

# -------------------- Sing-Box 客户端聚合配置 --------------------
show_singbox_client_config() {
    load_config
    show_notice "Sing-Box 客户端配置"

    local outbounds_json="["
    local proxy_tags=""
    local first=true

    # Reality
    if [ "${ENABLE_REALITY}" = "true" ]; then
        local rp ru rsn rpk rsi
        rp=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen_port' "${SERVER_CONFIG}")
        ru=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .users[0].uuid' "${SERVER_CONFIG}")
        rsn=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.server_name' "${SERVER_CONFIG}")
        rpk="${REALITY_PUBLIC_KEY}"
        rsi=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.reality.short_id[0]' "${SERVER_CONFIG}")
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "vless", "tag": "reality",
      "server": "'"${SERVER_IP}"'", "server_port": '"${rp}"',
      "uuid": "'"${ru}"'", "flow": "xtls-rprx-vision",
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true, "server_name": "'"${rsn}"'",
        "utls": {"enabled": true, "fingerprint": "chrome"},
        "reality": {"enabled": true, "public_key": "'"${rpk}"'", "short_id": "'"${rsi}"'"}
      }
    }'
        proxy_tags+='"reality",'
    fi

    # Hysteria2
    if [ "${ENABLE_HY2}" = "true" ]; then
        local hp hpw hsn
        hp=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "${SERVER_CONFIG}")
        hpw=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' "${SERVER_CONFIG}")
        hsn="${HY_SERVER_NAME}"
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "hysteria2", "tag": "hysteria2",
      "server": "'"${SERVER_IP}"'", "server_port": '"${hp}"',
      "password": "'"${hpw}"'",
      "tls": {"enabled": true, "server_name": "'"${hsn}"'", "insecure": true, "alpn": ["h3"]}
    }'
        proxy_tags+='"hysteria2",'
    fi

    # VLESS+WS
    if [ "${ENABLE_VLESS_WS}" = "true" ]; then
        local vp vu vpath
        vp=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .listen_port' "${SERVER_CONFIG}")
        vu=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .users[0].uuid' "${SERVER_CONFIG}")
        vpath=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .transport.path' "${SERVER_CONFIG}")
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "vless", "tag": "vless-cdn",
      "server": "'"${CDN_DOMAIN}"'", "server_port": '"${vp}"',
      "uuid": "'"${vu}"'", "flow": "",
      "transport": {"type": "ws", "path": "'"${vpath}"'", "headers": {"Host": "'"${CDN_DOMAIN}"'"}},
      "tls": {"enabled": true, "server_name": "'"${CDN_DOMAIN}"'"}
    }'
        proxy_tags+='"vless-cdn",'
    fi

    # Trojan+WS
    if [ "${ENABLE_TROJAN_WS}" = "true" ]; then
        local tp tpw tpath
        tp=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .listen_port' "${SERVER_CONFIG}")
        tpw=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .users[0].password' "${SERVER_CONFIG}")
        tpath=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .transport.path' "${SERVER_CONFIG}")
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "trojan", "tag": "trojan-cdn",
      "server": "'"${CDN_DOMAIN}"'", "server_port": '"${tp}"',
      "password": "'"${tpw}"'",
      "transport": {"type": "ws", "path": "'"${tpath}"'", "headers": {"Host": "'"${CDN_DOMAIN}"'"}},
      "tls": {"enabled": true, "server_name": "'"${CDN_DOMAIN}"'"}
    }'
        proxy_tags+='"trojan-cdn",'
    fi

    # TUIC
    if [ "${ENABLE_TUIC}" = "true" ]; then
        local tup tuu tupw tusn
        tup=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .listen_port' "${SERVER_CONFIG}")
        tuu=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].uuid' "${SERVER_CONFIG}")
        tupw=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].password' "${SERVER_CONFIG}")
        tusn="${HY_SERVER_NAME}"
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "tuic", "tag": "tuic",
      "server": "'"${SERVER_IP}"'", "server_port": '"${tup}"',
      "uuid": "'"${tuu}"'", "password": "'"${tupw}"'",
      "congestion_control": "bbr",
      "tls": {"enabled": true, "server_name": "'"${tusn}"'", "insecure": true, "alpn": ["h3"]}
    }'
        proxy_tags+='"tuic",'
    fi

    # ShadowTLS
    if [ "${ENABLE_SHADOWTLS}" = "true" ]; then
        local sp
        sp=$(jq -r '.inbounds[] | select(.tag=="shadowtls-in") | .listen_port' "${SERVER_CONFIG}")
        $first || outbounds_json+=","
        first=false
        outbounds_json+='
    {
      "type": "shadowsocks", "tag": "shadowtls-ss",
      "method": "2022-blake3-aes-128-gcm", "password": "'"${SS_PASSWORD}"'",
      "detour": "shadowtls-out", "udp_over_tcp": false
    },
    {
      "type": "shadowtls", "tag": "shadowtls-out",
      "server": "'"${SERVER_IP}"'", "server_port": '"${sp}"',
      "version": 3, "password": "'"${SHADOWTLS_PASSWORD}"'",
      "tls": {"enabled": true, "server_name": "'"${SHADOWTLS_SNI}"'"}
    }'
        proxy_tags+='"shadowtls-ss",'
    fi

    # 移除末尾逗号
    proxy_tags=${proxy_tags%,}

    outbounds_json+=',
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"},
    {"type": "dns", "tag": "dns-out"},
    {
      "type": "selector", "tag": "proxy",
      "outbounds": ["auto", "direct", '"${proxy_tags}"']
    },
    {
      "type": "urltest", "tag": "auto",
      "outbounds": ['"${proxy_tags}"'],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "1m", "tolerance": 50
    }
  ]'

    cat <<CLIENTEOF
{
  "log": {"level": "info", "timestamp": true},
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "default_mode": "rule"
    },
    "cache_file": {"enabled": true}
  },
  "dns": {
    "servers": [
      {"tag": "proxyDns", "address": "https://8.8.8.8/dns-query", "detour": "proxy"},
      {"tag": "localDns", "address": "https://223.5.5.5/dns-query", "detour": "direct"},
      {"tag": "block", "address": "rcode://success"},
      {"tag": "remote", "address": "fakeip"}
    ],
    "rules": [
      {"outbound": "any", "server": "localDns", "disable_cache": true},
      {"rule_set": "geosite-cn", "server": "localDns"},
      {"clash_mode": "direct", "server": "localDns"},
      {"clash_mode": "global", "server": "proxyDns"},
      {"rule_set": "geosite-geolocation-!cn", "server": "proxyDns"},
      {"query_type": ["A", "AAAA"], "server": "remote"}
    ],
    "fakeip": {"enabled": true, "inet4_range": "198.18.0.0/15", "inet6_range": "fc00::/18"},
    "independent_cache": true,
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun", "inet4_address": "172.19.0.1/30",
      "mtu": 9000, "auto_route": true, "strict_route": true, "sniff": true,
      "stack": "system",
      "platform": {"http_proxy": {"enabled": true, "server": "127.0.0.1", "server_port": 2080}}
    },
    {"type": "mixed", "listen": "127.0.0.1", "listen_port": 2080, "sniff": true}
  ],
  "outbounds": ${outbounds_json},
  "route": {
    "auto_detect_interface": true,
    "final": "proxy",
    "rules": [
      {"protocol": "dns", "outbound": "dns-out"},
      {"network": "udp", "port": 443, "outbound": "block"},
      {"clash_mode": "direct", "outbound": "direct"},
      {"clash_mode": "global", "outbound": "proxy"},
      {"rule_set": "geosite-geolocation-!cn", "outbound": "proxy"},
      {"ip_is_private": true, "outbound": "direct"},
      {"rule_set": "geoip-cn", "outbound": "direct"},
      {"rule_set": "geosite-cn", "outbound": "direct"}
    ],
    "rule_set": [
      {"tag": "geoip-cn", "type": "remote", "format": "binary", "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs", "download_detour": "direct"},
      {"tag": "geosite-cn", "type": "remote", "format": "binary", "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/cn.srs", "download_detour": "direct"},
      {"tag": "geosite-geolocation-!cn", "type": "remote", "format": "binary", "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs", "download_detour": "direct"}
    ]
  }
}
CLIENTEOF
    echo ""
}

# -------------------- 订阅链接生成 --------------------
generate_subscription() {
    load_config
    local links=""

    if [ "${ENABLE_REALITY}" = "true" ]; then
        local rp ru rsn rpk rsi
        rp=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .listen_port' "${SERVER_CONFIG}")
        ru=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .users[0].uuid' "${SERVER_CONFIG}")
        rsn=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.server_name' "${SERVER_CONFIG}")
        rpk="${REALITY_PUBLIC_KEY}"
        rsi=$(jq -r '.inbounds[] | select(.tag=="vless-reality-in") | .tls.reality.short_id[0]' "${SERVER_CONFIG}")
        links+="vless://${ru}@${SERVER_IP}:${rp}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${rsn}&fp=chrome&pbk=${rpk}&sid=${rsi}&type=tcp&headerType=none#Reality"$'\n'
    fi
    if [ "${ENABLE_HY2}" = "true" ]; then
        local hp hpw hsn
        hp=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "${SERVER_CONFIG}")
        hpw=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .users[0].password' "${SERVER_CONFIG}")
        hsn="${HY_SERVER_NAME}"
        links+="hysteria2://${hpw}@${SERVER_IP}:${hp}?insecure=1&sni=${hsn}#Hysteria2"$'\n'
    fi
    if [ "${ENABLE_VLESS_WS}" = "true" ]; then
        local vp vu vpath
        vp=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .listen_port' "${SERVER_CONFIG}")
        vu=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .users[0].uuid' "${SERVER_CONFIG}")
        vpath=$(jq -r '.inbounds[] | select(.tag=="vless-ws-in") | .transport.path' "${SERVER_CONFIG}")
        links+="vless://${vu}@${CDN_DOMAIN}:${vp}?encryption=none&security=tls&sni=${CDN_DOMAIN}&type=ws&host=${CDN_DOMAIN}&path=${vpath}#VLESS-CDN"$'\n'
    fi
    if [ "${ENABLE_TROJAN_WS}" = "true" ]; then
        local tp tpw tpath
        tp=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .listen_port' "${SERVER_CONFIG}")
        tpw=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .users[0].password' "${SERVER_CONFIG}")
        tpath=$(jq -r '.inbounds[] | select(.tag=="trojan-ws-in") | .transport.path' "${SERVER_CONFIG}")
        links+="trojan://${tpw}@${CDN_DOMAIN}:${tp}?security=tls&sni=${CDN_DOMAIN}&type=ws&host=${CDN_DOMAIN}&path=${tpath}#Trojan-CDN"$'\n'
    fi
    if [ "${ENABLE_TUIC}" = "true" ]; then
        local tup tuu tupw tusn
        tup=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .listen_port' "${SERVER_CONFIG}")
        tuu=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].uuid' "${SERVER_CONFIG}")
        tupw=$(jq -r '.inbounds[] | select(.tag=="tuic-in") | .users[0].password' "${SERVER_CONFIG}")
        tusn="${HY_SERVER_NAME}"
        links+="tuic://${tuu}:${tupw}@${SERVER_IP}:${tup}?alpn=h3&congestion_control=bbr&sni=${tusn}&allow_insecure=1#TUIC"$'\n'
    fi

    echo ""
    show_notice "Base64 订阅内容"
    echo ""
    echo "$links" | base64
    echo ""
    hint "将以上 Base64 内容托管到任意 URL 即可作为订阅链接使用"
    echo ""
}

# -------------------- 状态显示 --------------------
show_status() {
    local pid status
    pid=$(pgrep sing-box)
    status=$(systemctl is-active sing-box 2>/dev/null)

    if [ "$status" = "active" ]; then
        local cpu mem current_ver
        cpu=$(ps -p "$pid" -o %cpu 2>/dev/null | tail -n 1 | tr -d ' ')
        mem=$(( $(ps -p "$pid" -o rss 2>/dev/null | tail -n 1) / 1024 ))
        current_ver=$(${SINGBOX_BIN} version 2>/dev/null | awk '/version/{print $NF}')

        echo ""
        info "  状态: 运行中"
        info "  版本: ${current_ver}"
        info "  CPU:  ${cpu}%"
        info "  内存: ${mem}MB"
        echo ""

        load_config
        info "  已启用协议:"
        [ "${ENABLE_REALITY}" = "true" ]   && echo "    ✓ Reality     :${REALITY_PORT}"
        [ "${ENABLE_HY2}" = "true" ]       && echo "    ✓ Hysteria2   :${HY2_PORT}"
        [ "${ENABLE_VLESS_WS}" = "true" ]  && echo "    ✓ VLESS+WS    :${VLESS_WS_PORT} → ${CDN_DOMAIN}"
        [ "${ENABLE_TROJAN_WS}" = "true" ] && echo "    ✓ Trojan+WS   :${TROJAN_WS_PORT} → ${CDN_DOMAIN}"
        [ "${ENABLE_TUIC}" = "true" ]      && echo "    ✓ TUIC        :${TUIC_PORT}"
        [ "${ENABLE_SHADOWTLS}" = "true" ] && echo "    ✓ ShadowTLS   :${SHADOWTLS_PORT}"
    else
        warning "  sing-box 未运行"
    fi
    echo ""
}

# -------------------- WARP 管理 --------------------
enable_warp() {
    while :; do
        hint "选择 WARP 节点来源:"
        echo "  1. 内置节点 (默认)"
        echo "  2. 手动注册新节点"
        echo "  0. 退出"
        read -rp "选择 [默认1]: " warp_src
        warp_src=${warp_src:-1}
        case $warp_src in
            1)
                local v6="2606:4700:110:87ad:b400:91:eadb:887f"
                local private_key="wIC19yRRSJkhVJcE09Qo9bE3P3PIwS3yyqyUnjwNO34="
                local reserved="XiBe"
                break ;;
            2)
                hint "注册 WARP..."
                local output
                output=$(bash -c "$(curl -L warp-reg.vercel.app)")
                v6=$(echo "$output" | grep -oP '"v6": "\K[^"]+' | awk 'NR==2')
                private_key=$(echo "$output" | grep -oP '"private_key": "\K[^"]+')
                reserved=$(echo "$output" | grep -oP '"reserved_str": "\K[^"]+')
                break ;;
            0) return ;;
            *) warning "无效输入" ;;
        esac
    done

    local warp_out="warp-IPv6-prefer-out"
    while :; do
        hint "选择 WARP 策略:"
        echo "  1. IPv6优先 (默认)"
        echo "  2. IPv4优先"
        echo "  3. 仅IPv6"
        echo "  4. 仅IPv4"
        echo "  0. 退出"
        read -rp "选择 [默认1]: " warp_mode
        warp_mode=${warp_mode:-1}
        case $warp_mode in
            1) warp_out="warp-IPv6-prefer-out"; sed -i "s/WARP_MODE=.*/WARP_MODE=0/" "${CONFIG_FILE}"; break ;;
            2) warp_out="warp-IPv4-prefer-out"; sed -i "s/WARP_MODE=.*/WARP_MODE=1/" "${CONFIG_FILE}"; break ;;
            3) warp_out="warp-IPv6-out";        sed -i "s/WARP_MODE=.*/WARP_MODE=2/" "${CONFIG_FILE}"; break ;;
            4) warp_out="warp-IPv4-out";        sed -i "s/WARP_MODE=.*/WARP_MODE=3/" "${CONFIG_FILE}"; break ;;
            0) return ;;
            *) warning "无效输入" ;;
        esac
    done

    jq --arg pk "$private_key" --arg v6 "$v6" --arg rsv "$reserved" --arg wo "$warp_out" '
    .route = {
      "final": "direct",
      "rules": [
        {"rule_set": ["geosite-openai","geosite-netflix"], "outbound": $wo},
        {"domain_keyword": ["ipaddress"], "outbound": $wo}
      ],
      "rule_set": [
        {"tag":"geosite-openai","type":"remote","format":"binary","url":"https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/openai.srs","download_detour":"direct"},
        {"tag":"geosite-netflix","type":"remote","format":"binary","url":"https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/netflix.srs","download_detour":"direct"}
      ]
    } | .outbounds += [
      {"type":"direct","tag":"warp-IPv4-out","detour":"wireguard-out","domain_strategy":"ipv4_only"},
      {"type":"direct","tag":"warp-IPv6-out","detour":"wireguard-out","domain_strategy":"ipv6_only"},
      {"type":"direct","tag":"warp-IPv6-prefer-out","detour":"wireguard-out","domain_strategy":"prefer_ipv6"},
      {"type":"direct","tag":"warp-IPv4-prefer-out","detour":"wireguard-out","domain_strategy":"prefer_ipv4"},
      {"type":"wireguard","tag":"wireguard-out","server":"162.159.192.1","server_port":2408,
       "local_address":["172.16.0.2/32",$v6+"/128"],"private_key":$pk,
       "peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=","reserved":$rsv,"mtu":1280}
    ]' "${SERVER_CONFIG}" > "${SERVER_CONFIG}.tmp" && mv "${SERVER_CONFIG}.tmp" "${SERVER_CONFIG}"

    sed -i "s/WARP_ENABLE=FALSE/WARP_ENABLE=TRUE/" "${CONFIG_FILE}"
    sed -i "s/WARP_OPTION=.*/WARP_OPTION=0/" "${CONFIG_FILE}"
    reload_singbox
    info "WARP 已启用"
}

disable_warp() {
    jq 'del(.route) | del(.outbounds[] | select(.tag | test("warp-|wireguard-")))' \
        "${SERVER_CONFIG}" > "${SERVER_CONFIG}.tmp" && mv "${SERVER_CONFIG}.tmp" "${SERVER_CONFIG}"
    sed -i "s/WARP_ENABLE=TRUE/WARP_ENABLE=FALSE/" "${CONFIG_FILE}"
    reload_singbox
    info "WARP 已关闭"
}

process_warp() {
    load_config
    local iswarp="${WARP_ENABLE}"
    if [ "$iswarp" = "FALSE" ]; then
        read -rp "WARP 未开启，是否启用? [y/n, 默认y]: " confirm
        confirm=${confirm:-y}
        [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && enable_warp
    else
        warning "WARP 已开启"
        echo "  1. 关闭 WARP"
        echo "  0. 返回"
        read -rp "选择: " choice
        case $choice in
            1) disable_warp ;;
            *) return ;;
        esac
    fi
}

# -------------------- 端口跳跃 --------------------
enable_hy2hopping() {
    local hy_port
    hy_port=$(jq -r '.inbounds[] | select(.tag=="hy2-in") | .listen_port' "${SERVER_CONFIG}")
    warning "注意: 端口范围不要覆盖已占用端口"
    read -rp "起始端口 [默认50000]: " start_port
    start_port=${start_port:-50000}
    read -rp "结束端口 [默认51000]: " end_port
    end_port=${end_port:-51000}
    iptables -t nat -A PREROUTING -i eth0 -p udp --dport "${start_port}:${end_port}" -j DNAT --to-destination ":${hy_port}" 2>/dev/null
    ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport "${start_port}:${end_port}" -j DNAT --to-destination ":${hy_port}" 2>/dev/null
    sed -i "s/HY_HOPPING=FALSE/HY_HOPPING=TRUE/" "${CONFIG_FILE}"
    info "端口跳跃已开启: ${start_port}-${end_port} → ${hy_port}"
}

disable_hy2hopping() {
    iptables -t nat -F PREROUTING 2>/dev/null
    ip6tables -t nat -F PREROUTING 2>/dev/null
    sed -i "s/HY_HOPPING=.*/HY_HOPPING=FALSE/" "${CONFIG_FILE}"
    info "端口跳跃已关闭"
}

process_hy2hopping() {
    load_config
    if [ "${HY_HOPPING}" = "FALSE" ]; then
        enable_hy2hopping
    else
        warning "端口跳跃已开启"
        echo "  1. 关闭"
        echo "  2. 重新设置"
        echo "  3. 查看规则"
        echo "  0. 返回"
        read -rp "选择: " choice
        case $choice in
            1) disable_hy2hopping ;;
            2) disable_hy2hopping; enable_hy2hopping ;;
            3) iptables -t nat -L -n -v 2>/dev/null | grep "udp"
               ip6tables -t nat -L -n -v 2>/dev/null | grep "udp" ;;
            *) return ;;
        esac
    fi
}

# -------------------- sing-box 管理 --------------------
change_singbox() {
    local current_ver
    current_ver=$(${SINGBOX_BIN} version | awk '/version/{print $3}')
    local latest_stable latest_alpha
    latest_stable=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==false)][0].tag_name')
    latest_alpha=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==true)][0].tag_name')

    local new_tag
    if [[ $current_ver == *"-alpha"* || $current_ver == *"-rc"* || $current_ver == *"-beta"* ]]; then
        info "当前测试版 → 切换到正式版 ${latest_stable}"
        new_tag=$latest_stable
    else
        info "当前正式版 → 切换到测试版 ${latest_alpha}"
        new_tag=$latest_alpha
    fi

    systemctl stop sing-box
    local arch new_ver pkg url
    arch=$(get_arch)
    new_ver=${new_tag#v}
    pkg="sing-box-${new_ver}-linux-${arch}"
    url="https://github.com/SagerNet/sing-box/releases/download/${new_tag}/${pkg}.tar.gz"
    curl -sLo "/tmp/${pkg}.tar.gz" "$url"
    tar -xzf "/tmp/${pkg}.tar.gz" -C /tmp
    mv "/tmp/${pkg}/sing-box" "${SINGBOX_BIN}"
    rm -rf "/tmp/${pkg}.tar.gz" "/tmp/${pkg}"
    chown root:root "${SINGBOX_BIN}"
    chmod +x "${SINGBOX_BIN}"
    systemctl daemon-reload
    systemctl start sing-box
    info "已切换到 ${new_ver}"
}

process_singbox() {
    while :; do
        echo ""
        hint "sing-box 管理:"
        echo "  1. 重启"
        echo "  2. 更新内核"
        echo "  3. 查看状态"
        echo "  4. 实时日志"
        echo "  5. 查看服务端配置"
        echo "  6. 切换版本"
        echo "  0. 返回"
        read -rp "选择 [0-6]: " choice
        case $choice in
            1) reload_singbox; break ;;
            2) install_singbox; reload_singbox; break ;;
            3) systemctl status sing-box; break ;;
            4) journalctl -u sing-box -o cat -f; break ;;
            5) jq . "${SERVER_CONFIG}"; break ;;
            6) change_singbox; break ;;
            0) break ;;
            *) warning "无效选项" ;;
        esac
    done
}

# -------------------- 卸载 --------------------
uninstall_singbox() {
    warning "确认卸载 sing-box? 所有配置将被删除"
    read -rp "[y/n]: " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return

    disable_hy2hopping 2>/dev/null
    systemctl disable --now sing-box >/dev/null 2>&1
    rm -f "${SERVICE_FILE}"
    rm -rf "${SBOX_DIR}"
    rm -f "/usr/bin/${SHORTCUT_NAME}"
    info "卸载完成"
}

# -------------------- BBR --------------------
enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        info "BBR 已经开启"
        return
    fi
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        info "BBR 开启成功"
    else
        warning "BBR 开启失败，尝试使用脚本开启..."
        bash <(curl -L -s https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    fi
}

# ============================================================
#                        主流程
# ============================================================

# 检查是否已安装 → 显示管理菜单
if [ -f "${SERVER_CONFIG}" ] && [ -f "${CONFIG_FILE}" ] && [ -f "${SINGBOX_BIN}" ] && [ -f "${SERVICE_FILE}" ]; then
    show_banner
    show_status
    load_config

    separator
    note "  协议管理"
    separator
    echo "  1.  重新安装"
    echo "  2.  显示客户端配置"
    echo "  3.  生成订阅链接"
    separator
    note "  功能管理"
    separator
    echo "  4.  sing-box 内核管理"
    echo "  5.  WARP 流媒体解锁"
    echo "  6.  Hysteria2 端口跳跃"
    echo "  7.  一键开启 BBR"
    separator
    note "  其他"
    separator
    echo "  0.  卸载"
    echo ""
    read -rp "请选择 [0-7]: " choice

    case $choice in
        1) uninstall_singbox ;;
        2) show_client_configuration; exit 0 ;;
        3) generate_subscription; exit 0 ;;
        4) process_singbox; exit 0 ;;
        5) process_warp; exit 0 ;;
        6) process_hy2hopping; exit 0 ;;
        7) enable_bbr; exit 0 ;;
        0) uninstall_singbox; exit 0 ;;
        *) error "无效选项" ;;
    esac
fi

# ============================================================
#                      全新安装流程
# ============================================================
show_banner
check_root
check_os
info "系统: ${OS} | 架构: $(uname -m)"

echo ""
install_pkgs

echo ""
get_server_ip
info "服务器 IP: ${SERVER_IP} (${SERVER_IP_TYPE})"

# 安装 sing-box
install_singbox

# 选择协议
select_protocols

# 配置各协议参数
$ENABLE_REALITY   && configure_reality
$ENABLE_HY2       && configure_hy2
$ENABLE_VLESS_WS  && configure_vless_ws
$ENABLE_TROJAN_WS && configure_trojan_ws
$ENABLE_TUIC      && configure_tuic
$ENABLE_SHADOWTLS && configure_shadowtls

# 证书
if $ENABLE_HY2 || $ENABLE_VLESS_WS || $ENABLE_TROJAN_WS || $ENABLE_TUIC; then
    select_cert_method "${NEED_REAL_CERT}"
else
    # Reality 和 ShadowTLS 不需要证书文件（或自带）
    CERT_PATH=""
    KEY_PATH=""
    HY_SERVER_NAME=""
fi

# 如果只有 ShadowTLS 没选其他需要证书的协议
if $ENABLE_SHADOWTLS && [ -z "${CERT_PATH}" ]; then
    CERT_PATH=""
    KEY_PATH=""
fi

# 生成配置
generate_server_config
save_install_config
create_service

# 启动
if ${SINGBOX_BIN} check -c "${SERVER_CONFIG}"; then
    info "配置校验通过"
    systemctl start sing-box
    install_shortcut
    echo ""
    show_client_configuration
    echo ""
    separator
    info "安装完成! 输入 ${bold}network${reset}${green} 打开管理菜单"
    separator
else
    error "配置校验失败!"
fi
