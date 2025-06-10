#!/bin/bash
###########################################
# 多服务器端口转发配置脚本（交互输入版，提示格式优化）
###########################################

SOURCE_IP="0.0.0.0"
declare -A SERVER_CONFIGS
declare -A USED_PORTS

# 检查端口是否已被使用
check_port_duplicate() {
    local port=$1
    if [[ -n "${USED_PORTS[$port]}" ]]; then
        echo "❌ 端口 $port 已被使用，请重新输入。"
        return 1
    fi
    return 0
}

# 添加服务器配置（优化：增加IP格式校验）
add_server_config() {
    while true; do
        read -rp "是否添加新服务器？[yes/no] (default: yes): " add_more
        add_more=${add_more:-yes}
        [[ "$add_more" =~ ^[Nn] ]] && break

        read -rp "输入目标服务器 IP (e.g. 12.22.222.22): " server_ip
        # 简单正则验证IP格式
        if [[ ! "$server_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "⚠️ IP 格式不正确，请重新输入。"
            continue
        fi

        # TCP 源端口
        while true; do
            read -rp "输入 TCP 源端口 (e.g. 9090): " tcp_src
            [[ "$tcp_src" =~ ^[0-9]+$ ]] && check_port_duplicate "$tcp_src" && break
            echo "⚠️ 格式错误或端口重复，请输入正确的 TCP 源端口。"
        done
        read -rp "输入 TCP 目标端口 (e.g. 8080): " tcp_dst

        # UDP 源端口
        while true; do
            read -rp "输入 UDP 源端口 (e.g. 9090): " udp_src
            [[ "$udp_src" =~ ^[0-9]+$ ]] && check_port_duplicate "$udp_src" && break
            echo "⚠️ 格式错误或端口重复，请输入正确的 UDP 源端口。"
        done
        read -rp "输入 UDP 目标端口 (e.g. 8080): " udp_dst

        SERVER_CONFIGS["$server_ip"]="$tcp_src:$tcp_dst $udp_src:$udp_dst"
        USED_PORTS["$tcp_src"]=1
        USED_PORTS["$udp_src"]=1
        echo "✅ 添加: $server_ip → TCP $tcp_src->$tcp_dst, UDP $udp_src->$udp_dst"
    done
}

install_required_packages() {
    echo -e "\n步骤1: 安装必要的软件包..."
    # 使用非交互模式并检查安装状态
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
}

setup_port_forward() {
    local ip="$1" proto="$2" src="$3" dst="$4"
    echo "配置 $proto 转发: $src → $ip:$dst"
    iptables -I INPUT -p "$proto" --dport "$src" -j ACCEPT
    iptables -t nat -A PREROUTING -p "$proto" --dport "$src" -j DNAT --to-destination "$ip:$dst"
    iptables -t nat -A POSTROUTING -d "$ip" -p "$proto" --dport "$dst" -j MASQUERADE
    iptables -A FORWARD -d "$ip" -p "$proto" --dport "$dst" -j ACCEPT
    iptables -A FORWARD -s "$ip" -p "$proto" --sport "$dst" -j ACCEPT
}

setup_autostart_service() {
    cat >/etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables rules
Before=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable iptables-restore.service
}

# 要求 root 权限
[[ $EUID -ne 0 ]] && { echo "请使用 root 权限运行脚本。"; exit 1; }

add_server_config
install_required_packages

echo -e "\n步骤2: 开启 IP 转发..."
# 避免重复添加
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >>/etc/sysctl.conf
fi
sysctl -p

echo -e "\n步骤3: 应用转发规则..."
for ip in "${!SERVER_CONFIGS[@]}"; do
    IFS=' ' read -r tcp_cfg udp_cfg <<<"${SERVER_CONFIGS[$ip]}"
    setup_port_forward "$ip" tcp "${tcp_cfg%%:*}" "${tcp_cfg#*:}"
    setup_port_forward "$ip" udp "${udp_cfg%%:*}" "${udp_cfg#*:}"
done

echo -e "\n步骤4: 保存规则到 /etc/iptables/rules.v4"
mkdir -p /etc/iptables
iptables-save >/etc/iptables/rules.v4

setup_autostart_service

echo -e "\n步骤5: 启动并启用持久化服务"
systemctl start netfilter-persistent && systemctl enable netfilter-persistent

# 摘要输出
cat <<EOF

✅ 当前转发配置摘要：
----------------------------------------
源服务器: $SOURCE_IP
EOF
for ip in "${!SERVER_CONFIGS[@]}"; do
    IFS=' ' read -r tcp_cfg udp_cfg <<<"${SERVER_CONFIGS[$ip]}"
    echo "目标: $ip"
    echo "  TCP: $SOURCE_IP:${tcp_cfg%%:*} -> $ip:${tcp_cfg#*:}"
    echo "  UDP: $SOURCE_IP:${udp_cfg%%:*} -> $ip:${udp_cfg#*:}"
done
echo "----------------------------------------"

cat <<'END'

🔍 验证命令示例：
 1. iptables -L -n -v
 2. iptables -t nat -L -n -v
 3. nc -vz [目标IP] [端口]
 4. systemctl status iptables-restore.service
 5. systemctl status netfilter-persistent
END


# #!/bin/bash
# ###########################################
# # 多服务器端口转发配置脚本（交互输入版）
# ###########################################

# SOURCE_IP="0.0.0.0"
# declare -A SERVER_CONFIGS
# declare -A USED_PORTS

# # 检查端口是否已被使用
# check_port_duplicate() {
#     local port=$1
#     if [[ -n "${USED_PORTS[$port]}" ]]; then
#         echo "❌ 端口 $port 已经被用于其他转发，请重新输入。"
#         return 1
#     fi
#     return 0
# }

# # 添加服务器配置
# add_server_config() {
#     while true; do
#         echo -e "\n请输入目标服务器 IP（留空结束输入）："
#         read -r server_ip
#         [[ -z "$server_ip" ]] && break

#         while true; do
#             echo "为服务器 $server_ip 输入 TCP 源端口:"
#             read -r tcp_src
#             check_port_duplicate "$tcp_src" || continue

#             echo "为服务器 $server_ip 输入 TCP 目标端口:"
#             read -r tcp_dst

#             echo "为服务器 $server_ip 输入 UDP 源端口:"
#             read -r udp_src
#             check_port_duplicate "$udp_src" || continue

#             echo "为服务器 $server_ip 输入 UDP 目标端口:"
#             read -r udp_dst

#             # 添加配置并标记已用端口
#             SERVER_CONFIGS["$server_ip"]="${tcp_src}:${tcp_dst} ${udp_src}:${udp_dst}"
#             USED_PORTS["$tcp_src"]=1
#             USED_PORTS["$udp_src"]=1
#             break
#         done
#     done
# }

# install_required_packages() {
#     echo "步骤1: 安装必要的软件包..."
#     apt-get update
#     apt-get install -y iptables-persistent netfilter-persistent
# }

# setup_port_forward() {
#     local target_ip=$1
#     local protocol=$2
#     local source_port=$3
#     local target_port=$4

#     echo "配置 ${protocol} 转发: ${source_port} -> ${target_ip}:${target_port}"
#     iptables -I INPUT -p ${protocol} --dport ${source_port} -j ACCEPT
#     iptables -t nat -A PREROUTING -p ${protocol} --dport ${source_port} \
#         -j DNAT --to-destination ${target_ip}:${target_port}
#     iptables -t nat -A POSTROUTING -d ${target_ip} -p ${protocol} \
#         --dport ${target_port} -j MASQUERADE
#     iptables -A FORWARD -d ${target_ip} -p ${protocol} --dport ${target_port} -j ACCEPT
#     iptables -A FORWARD -s ${target_ip} -p ${protocol} --sport ${target_port} -j ACCEPT
# }

# setup_autostart_service() {
#     echo "配置自启动服务..."
#     cat > /etc/systemd/system/iptables-restore.service << EOF
# [Unit]
# Description=Restore iptables rules
# Before=network-pre.target

# [Service]
# Type=oneshot
# ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
# RemainAfterExit=yes

# [Install]
# WantedBy=multi-user.target
# EOF

#     systemctl daemon-reload
#     systemctl enable iptables-restore.service
# }

# # 检查是否为 root
# if [ "$EUID" -ne 0 ]; then
#     echo "错误: 请使用 root 权限运行脚本"
#     exit 1
# fi

# # 添加服务器配置
# add_server_config

# # 安装必要的软件包
# install_required_packages

# # 启用 IP 转发
# echo "步骤2: 开启 IP 转发..."
# echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
# sysctl -p

# # 配置转发规则
# echo "步骤3: 配置端口转发规则..."
# for target_ip in "${!SERVER_CONFIGS[@]}"; do
#     config="${SERVER_CONFIGS[$target_ip]}"
#     tcp_ports=(${config%% *})
#     tcp_source_port="${tcp_ports%%:*}"
#     tcp_target_port="${tcp_ports#*:}"

#     udp_ports=(${config##* })
#     udp_source_port="${udp_ports%%:*}"
#     udp_target_port="${udp_ports#*:}"

#     setup_port_forward "$target_ip" "tcp" "$tcp_source_port" "$tcp_target_port"
#     setup_port_forward "$target_ip" "udp" "$udp_source_port" "$udp_target_port"
# done

# # 保存规则
# echo "步骤4: 保存 iptables 规则..."
# mkdir -p /etc/iptables
# iptables-save > /etc/iptables/rules.v4

# # 设置自启动服务
# setup_autostart_service

# # 启动服务
# echo "步骤5: 启动持久化服务..."
# systemctl start netfilter-persistent
# systemctl enable netfilter-persistent

# # 显示摘要
# echo -e "\n✅ 当前转发配置："
# echo "----------------------------------------"
# echo "源服务器: ${SOURCE_IP}"
# for target_ip in "${!SERVER_CONFIGS[@]}"; do
#     config="${SERVER_CONFIGS[$target_ip]}"
#     tcp_ports=(${config%% *})
#     udp_ports=(${config##* })
#     echo -e "\n目标服务器: ${target_ip}"
#     echo "TCP转发: ${SOURCE_IP}:${tcp_ports%%:*} -> ${target_ip}:${tcp_ports#*:}"
#     echo "UDP转发: ${SOURCE_IP}:${udp_ports%%:*} -> ${target_ip}:${udp_ports#*:}"
# done
# echo "----------------------------------------"

# echo -e "\n🔍 验证建议："
# echo "1. iptables -L -n -v"
# echo "2. iptables -t nat -L -n -v"
# echo "3. nc -vz [目标IP] [目标端口]"
# echo "4. systemctl status iptables-restore.service"
# echo "5. systemctl status netfilter-persistent"
