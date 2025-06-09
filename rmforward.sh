#!/bin/bash

echo "==== 端口转发规则删除工具 ===="

# 获取协议类型
while true; do
    read -rp "请输入协议类型 [tcp/udp]: " proto
    if [[ "$proto" == "tcp" || "$proto" == "udp" ]]; then
        break
    else
        echo "⚠️ 请输入 tcp 或 udp"
    fi
done

# 获取本地源端口
while true; do
    read -rp "请输入本地源端口 (如: 50102): " local_port
    [[ "$local_port" =~ ^[0-9]+$ ]] && break
    echo "⚠️ 请输入有效的端口号"
done

# 获取目标服务器 IP
read -rp "请输入目标服务器 IP (如: 38.49.57.71): " target_ip

# 获取目标端口
while true; do
    read -rp "请输入目标端口 (如: 10535): " target_port
    [[ "$target_port" =~ ^[0-9]+$ ]] && break
    echo "⚠️ 请输入有效的端口号"
done

echo -e "\n⏳ 正在删除以下规则："
echo "- PREROUTING DNAT: $proto dpt:$local_port → $target_ip:$target_port"
echo "- POSTROUTING MASQUERADE: $proto dpt:$target_port → $target_ip"
echo "- INPUT & FORWARD 相关规则"

# 执行删除命令
iptables -t nat -D PREROUTING -p "$proto" --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null
iptables -t nat -D POSTROUTING -d "$target_ip" -p "$proto" --dport "$target_port" -j MASQUERADE 2>/dev/null
iptables -D FORWARD -d "$target_ip" -p "$proto" --dport "$target_port" -j ACCEPT 2>/dev/null
iptables -D FORWARD -s "$target_ip" -p "$proto" --sport "$target_port" -j ACCEPT 2>/dev/null
iptables -D INPUT -p "$proto" --dport "$local_port" -j ACCEPT 2>/dev/null

# 保存配置
iptables-save > /etc/iptables/rules.v4

echo -e "\n✅ 删除完成，规则已保存到 /etc/iptables/rules.v4"
