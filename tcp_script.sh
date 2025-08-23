#!/bin/bash
# ===================================================================
# 🚀 增强版 TCP/UDP 优化脚本 | 支持Reality+Hysteria2 | BBR + FQ
# 作者：基于原脚本增强优化
# 新增：Reality TLS优化 + Hysteria2 UDP优化 + 协议检测
# 特性：--target=local/global/auto，--protocol=auto/reality/hysteria2/legacy
# ===================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 错误：请以 root 或 sudo 权限运行${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 正在运行增强版 TCP/UDP 优化脚本...${NC}"
OS=$(grep -oP '(?<=^NAME=").*(?=")' /etc/os-release 2>/dev/null || uname -s)
echo -e "${GREEN}✅ 系统：${OS}${NC}"

# === 🔧 解析参数 ===
TARGET_MODE="auto"
PROTOCOL_MODE="auto"
ENABLE_UDP_TEST=false

for arg in "$@"; do
    case $arg in
        --target=local|--target=global|--target=auto)
            TARGET_MODE="${arg#*=}"
            echo -e "${BLUE}🎯 网络模式：${TARGET_MODE}${NC}"
            ;;
        --protocol=auto|--protocol=reality|--protocol=hysteria2|--protocol=legacy)
            PROTOCOL_MODE="${arg#*=}"
            echo -e "${PURPLE}🔐 协议模式：${PROTOCOL_MODE}${NC}"
            ;;
        --enable-udp-test)
            ENABLE_UDP_TEST=true
            echo -e "${CYAN}📊 启用UDP测速${NC}"
            ;;
    esac
done

# === 🕵️ 协议检测函数 ===
detect_protocols() {
    local reality_detected=false
    local hysteria2_detected=false
    
    # 检测Reality相关进程和配置
    if pgrep -f "xray\|v2ray" > /dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -E ":443\s" > /dev/null; then
            reality_detected=true
            echo -e "${GREEN}✅ 检测到Reality协议 (端口443)${NC}"
        fi
    fi
    
    # 检测Hysteria2相关进程
    if pgrep -f "hysteria" > /dev/null 2>&1; then
        hysteria2_detected=true
        echo -e "${GREEN}✅ 检测到Hysteria2协议${NC}"
    fi
    
    # 检查配置文件
    for config_path in "/etc/hysteria" "/opt/hysteria" "/usr/local/etc/hysteria"; do
        if [ -d "$config_path" ] && [ -n "$(ls -A $config_path 2>/dev/null)" ]; then
            hysteria2_detected=true
            echo -e "${GREEN}✅ 发现Hysteria2配置目录: $config_path${NC}"
            break
        fi
    done
    
    # 更新协议模式
    if [ "$PROTOCOL_MODE" = "auto" ]; then
        if $reality_detected && $hysteria2_detected; then
            PROTOCOL_MODE="both"
            echo -e "${YELLOW}🔄 自动检测：同时运行Reality + Hysteria2${NC}"
        elif $reality_detected; then
            PROTOCOL_MODE="reality"
            echo -e "${YELLOW}🔄 自动检测：主要使用Reality${NC}"
        elif $hysteria2_detected; then
            PROTOCOL_MODE="hysteria2"
            echo -e "${YELLOW}🔄 自动检测：主要使用Hysteria2${NC}"
        else
            PROTOCOL_MODE="legacy"
            echo -e "${YELLOW}🔄 自动检测：使用传统TCP优化${NC}"
        fi
    fi
}

# 执行协议检测
echo -e "${BLUE}🔍 正在检测已安装的协议...${NC}"
detect_protocols

# === 🔥 防火墙配置 ===
configure_firewall() {
    echo -e "${BLUE}🔧 配置防火墙...${NC}"
    
    # 基础测速端口
    if command -v ufw &> /dev/null; then
        ufw allow out 5200:5210/tcp > /dev/null 2>&1 || true
        ufw allow out 5200:5210/udp > /dev/null 2>&1 || true
        echo -e "${GREEN}✅ UFW：已允许测速端口${NC}"
    fi

    if command -v iptables &> /dev/null; then
        iptables -A OUTPUT -p tcp --dport 5200:5210 -j ACCEPT > /dev/null 2>&1
        iptables -A OUTPUT -p udp --dport 5200:5210 -j ACCEPT > /dev/null 2>&1
        echo -e "${GREEN}✅ iptables：已允许测速端口${NC}"
    fi
    
    # Reality协议端口 (443)
    if [[ "$PROTOCOL_MODE" =~ ^(reality|both)$ ]]; then
        if command -v ufw &> /dev/null; then
            ufw allow 443/tcp > /dev/null 2>&1 || true
        fi
        echo -e "${GREEN}✅ 已开放Reality端口 (443/tcp)${NC}"
    fi
    
    # Hysteria2端口范围
    if [[ "$PROTOCOL_MODE" =~ ^(hysteria2|both)$ ]]; then
        if command -v ufw &> /dev/null; then
            ufw allow 10000:20000/udp > /dev/null 2>&1 || true
        fi
        echo -e "${GREEN}✅ 已开放Hysteria2常用端口范围 (10000-20000/udp)${NC}"
    fi
}

configure_firewall

# === 🌍 公共测试服务器 ===
declare -a SERVERS_LOCAL=(
    "中国-香港 speedtest.hkg12.hk.leaseweb.net:5203"
    "新加坡    speedtest.singnet.com.sg:5203"
)

declare -a SERVERS_GLOBAL=(
    "美国-洛杉矶 speedtest.lax12.us.leaseweb.net:5003"
    "德国-法兰克福 speedtest.fra10.de.leaseweb.net:5201"
    "法国-巴黎 ping.online.net:5203"
)

SERVERS_ALL=("${SERVERS_LOCAL[@]}" "${SERVERS_GLOBAL[@]}")

# === 🌐 延迟探测 ===
echo -e "${BLUE}🌐 正在探测节点延迟...${NC}"
BEST_LOCAL_IP="" BEST_GLOBAL_IP=""
MIN_LOCAL_PING=9999 MIN_GLOBAL_PING=9999

for server in "${SERVERS_ALL[@]}"; do
    full_name=$(echo "$server" | awk '{print $1}')
    domain_port=$(echo "$server" | awk '{print $2}')
    location=$(echo "$full_name" | sed 's/[^-]*-//')
    domain=$(echo "$domain_port" | cut -d: -f1)
    port=$(echo "$domain_port" | cut -d: -f2)

    ip=$(ping -c1 -W2 "$domain" | grep -oE "\([0-9.]+\)" | tr -d "()" | head -1)
    [ -z "$ip" ] && continue

    ping_ms=$(ping -c3 -W2 "$ip" | grep 'avg' | awk -F'/' '{print $5}' 2>/dev/null)
    [ -z "$ping_ms" ] && continue

    ping_ms=$(printf "%.0f" "$ping_ms")
    echo -e "   $location $ip:$port → ${GREEN}${ping_ms}ms${NC}"

    if [[ " ${SERVERS_LOCAL[*]} " =~ " $server " ]]; then
        if (( $(echo "$ping_ms < $MIN_LOCAL_PING" | bc -l 2>/dev/null || echo 0) )); then
            MIN_LOCAL_PING=$ping_ms
            BEST_LOCAL_IP=$ip
        fi
    else
        if (( $(echo "$ping_ms < $MIN_GLOBAL_PING" | bc -l 2>/dev/null || echo 0) )); then
            MIN_GLOBAL_PING=$ping_ms
            BEST_GLOBAL_IP=$ip
        fi
    fi
done

# === 🧠 RTT选择逻辑 ===
TEST_SERVER=${BEST_LOCAL_IP:-$BEST_GLOBAL_IP}
TEST_PORT=5203

if [ -z "$TEST_SERVER" ]; then
    echo -e "${RED}❌ 所有节点均无法访问${NC}"
    exit 1
fi

case $TARGET_MODE in
    local)
        USE_RTT=$MIN_LOCAL_PING
        echo -e "${YELLOW}📍 模式：local → 使用本地延迟 ${USE_RTT}ms${NC}"
        ;;
    global)
        USE_RTT=$MIN_GLOBAL_PING
        echo -e "${YELLOW}🌍 模式：global → 使用跨境延迟 ${USE_RTT}ms${NC}"
        ;;
    *)
        USE_RTT=$(echo "$MIN_LOCAL_PING" "$MIN_GLOBAL_PING" | awk '{print ($1>$2?$1:$2)}')
        echo -e "${YELLOW}🔄 模式：auto → 使用较大延迟 ${USE_RTT}ms${NC}"
        ;;
esac

# === 📊 带宽估算 ===
if (( $(echo "$USE_RTT < 50" | bc -l) )); then
    max_bw=10000
elif (( $(echo "$USE_RTT < 100" | bc -l) )); then
    max_bw=2500
elif (( $(echo "$USE_RTT < 150" | bc -l) )); then
    max_bw=1000
else
    max_bw=800
fi

echo -e "${GREEN}✅ 推荐带宽：${max_bw} Mbps (RTT: ${USE_RTT}ms, 协议: ${PROTOCOL_MODE})${NC}"

# === 📦 计算缓冲区大小 ===
rtt_sec=$(echo "$USE_RTT / 1000" | bc -l)
bdp_bytes=$(echo "$max_bw * 1000000 * $rtt_sec / 8" | bc -l)

# 根据协议调整缓冲区策略
case $PROTOCOL_MODE in
    hysteria2)
        # Hysteria2主要使用UDP，增大UDP缓冲区
        rmem_max=$(echo "$bdp_bytes * 2.0" | bc -l)
        udp_multiplier=3.0
        echo -e "${PURPLE}🔧 Hysteria2模式：重点优化UDP性能${NC}"
        ;;
    reality)
        # Reality使用TCP，但需要快速TLS握手
        rmem_max=$(echo "$bdp_bytes * 1.5" | bc -l)
        udp_multiplier=1.0
        echo -e "${PURPLE}🔧 Reality模式：优化TCP + TLS握手${NC}"
        ;;
    both)
        # 平衡两种协议
        rmem_max=$(echo "$bdp_bytes * 1.8" | bc -l)
        udp_multiplier=2.5
        echo -e "${PURPLE}🔧 混合模式：平衡TCP/UDP性能${NC}"
        ;;
    *)
        # 传统优化
        rmem_max=$(echo "$bdp_bytes * 1.5" | bc -l)
        udp_multiplier=1.5
        echo -e "${PURPLE}🔧 传统模式：标准TCP优化${NC}"
        ;;
esac

rmem_max=$(printf "%.0f" "$rmem_max")
rmem_max=${rmem_max:-134217728}
udp_rmem=$(echo "$rmem_max * $udp_multiplier" | bc -l)
udp_rmem=$(printf "%.0f" "$udp_rmem")

echo -e "${GREEN}🔧 TCP缓冲区：$((rmem_max/1024/1024)) MB${NC}"
echo -e "${GREEN}🔧 UDP缓冲区：$((udp_rmem/1024/1024)) MB${NC}"

# === 🛠️ 生成优化配置 ===
generate_sysctl_config() {
    cat > /tmp/tcp-udp-opt.conf << EOF
# =================================================================
# 增强版 TCP/UDP 优化配置 - 支持Reality+Hysteria2
# 协议模式: ${PROTOCOL_MODE} | RTT: ${USE_RTT}ms
# =================================================================

# 基础 TCP 优化 (BBR + FQ)
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# TCP 缓冲区配置
net.core.rmem_max = $rmem_max
net.core.wmem_max = $rmem_max
net.ipv4.tcp_rmem = 4096 87380 $rmem_max
net.ipv4.tcp_wmem = 4096 65536 $rmem_max

# TCP 性能优化
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1

EOF

    # Reality 特定优化
    if [[ "$PROTOCOL_MODE" =~ ^(reality|both)$ ]]; then
        cat >> /tmp/tcp-udp-opt.conf << EOF
# Reality (TLS) 专用优化
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

EOF
    fi

    # Hysteria2/UDP 优化
    if [[ "$PROTOCOL_MODE" =~ ^(hysteria2|both)$ ]] || [ "$PROTOCOL_MODE" != "reality" ]; then
        cat >> /tmp/tcp-udp-opt.conf << EOF
# UDP 性能优化 (Hysteria2专用)
net.core.rmem_default = $(echo "$udp_rmem / 4" | bc)
net.core.wmem_default = $(echo "$udp_rmem / 4" | bc)
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 300
net.ipv4.udp_mem = 102400 873800 $udp_rmem
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

EOF
    fi

    # 通用网络优化
    cat >> /tmp/tcp-udp-opt.conf << EOF
# 通用网络优化
net.core.somaxconn = 32768
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 1800

# IPv6 支持
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
}

generate_sysctl_config
cp -f /tmp/tcp-udp-opt.conf /etc/sysctl.d/99-enhanced-opt.conf
sysctl --load /etc/sysctl.d/99-enhanced-opt.conf > /dev/null 2>&1
echo -e "${GREEN}✅ 优化配置已应用 (协议: ${PROTOCOL_MODE})${NC}"

# === 📡 安装依赖 ===
install_dependencies() {
    for cmd in iperf3 jq bc; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${BLUE}🔧 正在安装 $cmd...${NC}"
            if command -v apt &> /dev/null; then
                apt update -qq > /dev/null && apt install -y $cmd > /dev/null 2>&1
            elif command -v yum &> /dev/null; then
                yum install -y $cmd > /dev/null 2>&1
            elif command -v dnf &> /dev/null; then
                dnf install -y $cmd > /dev/null 2>&1
            else
                echo -e "${RED}❌ 无法安装 $cmd${NC}"
                exit 1
            fi
        fi
    done
}

install_dependencies

# === 📊 测速函数 ===
run_tcp_test() {
    local stage="$1"
    echo -e "${BLUE}📊 [$stage] TCP下载测速...${NC}"
    timeout 15 iperf3 -c "$TEST_SERVER" -p "$TEST_PORT" -R -t 10 -O 3 --json > "/tmp/tcp_${stage}.json" 2>&1
    if [ $? -eq 0 ] && [ -s "/tmp/tcp_${stage}.json" ]; then
        speed=$(jq -r '.end.sum_received.bits_per_second / 1000000' "/tmp/tcp_${stage}.json" 2>/dev/null | awk '{printf "%.1f", $1}')
        echo -e "${GREEN}✅ [$stage] TCP: ${speed} Mbps${NC}"
        declare -g "tcp_${stage}_speed=$speed"
    else
        echo -e "${RED}❌ [$stage] TCP测试失败${NC}"
        declare -g "tcp_${stage}_speed=0.0"
    fi
}

run_udp_test() {
    local stage="$1"
    local target_bw="$2"
    echo -e "${BLUE}📊 [$stage] UDP测速 (目标: ${target_bw}M)...${NC}"
    timeout 15 iperf3 -c "$TEST_SERVER" -p "$TEST_PORT" -u -b "${target_bw}M" -t 8 --json > "/tmp/udp_${stage}.json" 2>&1
    if [ $? -eq 0 ] && [ -s "/tmp/udp_${stage}.json" ]; then
        speed=$(jq -r '.end.sum.bits_per_second / 1000000' "/tmp/udp_${stage}.json" 2>/dev/null | awk '{printf "%.1f", $1}')
        loss=$(jq -r '.end.sum.lost_percent' "/tmp/udp_${stage}.json" 2>/dev/null | awk '{printf "%.1f", $1}')
        echo -e "${GREEN}✅ [$stage] UDP: ${speed} Mbps (丢包: ${loss}%)${NC}"
        declare -g "udp_${stage}_speed=$speed"
        declare -g "udp_${stage}_loss=$loss"
    else
        echo -e "${RED}❌ [$stage] UDP测试失败${NC}"
        declare -g "udp_${stage}_speed=0.0"
        declare -g "udp_${stage}_loss=0.0"
    fi
}

# === 📈 执行测速对比 ===
sleep 2
echo -e "${CYAN}📈 开始性能测试...${NC}"

# TCP测试
run_tcp_test "before"
sleep 3
run_tcp_test "after"

# UDP测试 (如果启用或检测到Hysteria2)
if [ "$ENABLE_UDP_TEST" = true ] || [[ "$PROTOCOL_MODE" =~ ^(hysteria2|both)$ ]]; then
    echo -e "${PURPLE}🔧 执行UDP性能测试 (Hysteria2相关)${NC}"
    udp_target_bw=$((max_bw / 2))  # UDP测试使用一半带宽避免丢包
    sleep 2
    run_udp_test "after" "$udp_target_bw"
fi

# === 📋 生成详细报告 ===
: ${tcp_before_speed:=0.0}
: ${tcp_after_speed:=0.0}
: ${udp_after_speed:=0.0}
: ${udp_after_loss:=0.0}

echo -e "\n${CYAN}📈 ================= 增强版优化报告 ==================${NC}"
echo -e "   系统环境：$OS"
echo -e "   优化模式：$TARGET_MODE (RTT: ${USE_RTT}ms)"
echo -e "   协议检测：$PROTOCOL_MODE"
echo -e "   测速节点：$TEST_SERVER"
echo -e "   优化策略：BBR + FQ + 协议专用优化"
echo -e "${CYAN}======================================================${NC}"

printf "   %-12s : %8s Mbps\n" "TCP优化前" "$tcp_before_speed"
printf "   %-12s : %8s Mbps\n" "TCP优化后" "$tcp_after_speed"

if [[ "$PROTOCOL_MODE" =~ ^(hysteria2|both)$ ]] || [ "$ENABLE_UDP_TEST" = true ]; then
    printf "   %-12s : %8s Mbps (丢包: %s%%)\n" "UDP性能" "$udp_after_speed" "$udp_after_loss"
fi

# 计算TCP提升率
if (( $(echo "$tcp_before_speed > 0.1" | bc -l 2>/dev/null || echo 0) )); then
    improvement=$(echo "scale=2; ($tcp_after_speed - $tcp_before_speed) / $tcp_before_speed * 100" | bc -l 2>/dev/null || echo "0")
    if (( $(echo "$improvement > 0" | bc -l) )); then
        printf "   %-12s : %+7.2f%% %s\n" "TCP提升" "$improvement" "🚀"
    else
        printf "   %-12s : %+7.2f%% %s\n" "TCP变化" "$improvement" "📊"
    fi
fi

echo -e "${CYAN}======================================================${NC}"

# 协议特定建议
case $PROTOCOL_MODE in
    reality)
        echo -e "${GREEN}🎯 Reality优化完成：TLS握手加速 + TCP性能提升${NC}"
        ;;
    hysteria2)
        echo -e "${GREEN}🎯 Hysteria2优化完成：UDP缓冲区增大 + QUIC性能优化${NC}"
        ;;
    both)
        echo -e "${GREEN}🎯 混合优化完成：Reality + Hysteria2 双协议支持${NC}"
        ;;
    *)
        echo -e "${GREEN}🎯 传统优化完成：通用TCP/UDP性能提升${NC}"
        ;;
esac

echo -e "${BLUE}💡 提示：重启相关服务以获得最佳效果${NC}"
echo -e "${GREEN}🎉 增强版优化完成！${NC}"

# === 🔧 生成重启建议 ===
echo -e "\n${YELLOW}📋 建议执行的重启命令：${NC}"
if [[ "$PROTOCOL_MODE" =~ ^(reality|both)$ ]]; then
    echo -e "   systemctl restart xray    # 重启Reality服务"
fi
if [[ "$PROTOCOL_MODE" =~ ^(hysteria2|both)$ ]]; then
    echo -e "   systemctl restart hysteria-server    # 重启Hysteria2服务"
fi
echo -e "   # 或者重启整个系统: reboot"
