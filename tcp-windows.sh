#!/bin/bash
# 完整增强版 BBR + TCP/UDP 优化脚本，适配 Reality / Hysteria2 / 高并发转发服务器

if [[ $EUID -ne 0 ]]; then
    echo "❌ 错误：请以 root 用户身份运行本脚本。"
    exit 1
fi

echo "[1/7] 清理旧的 sysctl 配置项..."
for file in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
    sed -i '/tcp_rmem/d;/tcp_wmem/d;/net.core.rmem_max/d;/net.core.wmem_max/d;/udp_rmem_min/d;/udp_wmem_min/d;/tcp_congestion_control/d;/default_qdisc/d' "$file"
done

echo "[2/7] 设置文件最大句柄数..."
cat >/etc/security/limits.conf <<EOF
* soft     nofile         655360
* hard     nofile         655360
* soft     nproc          655360
* hard     nproc          655360
root soft  nofile         655360
root hard  nofile         655360
root soft  nproc          655360
root hard  nproc          655360
EOF

echo "[3/7] 设置 PAM 限制..."
grep -q "pam_limits.so" /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session
grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

echo "[4/7] 修改 systemd 文件描述符限制..."
sed -i '/^#*DefaultLimitNOFILE/c\DefaultLimitNOFILE=655360' /etc/systemd/system.conf

echo "[5/7] 写入完整 TCP+UDP+BBR 优化参数..."
cat >/etc/sysctl.d/99-bbr-optimization.conf <<EOF
fs.file-max = 2097152

# TCP 网络性能增强参数
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_rmem = 8192 262144 67108864
net.ipv4.tcp_wmem = 8192 262144 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_notsent_lowat = 131072

# 启用 BBR 拥塞控制算法
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# UDP 优化（适配 Hysteria2）
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 高级 TCP 行为参数增强（兼容性优化）
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1

# 转发设置（适用于网关/NAT服务器）
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

echo "[6/7] 应用内核参数..."
sysctl --system

echo "[7/7] 设置当前 shell 文件句柄限制（临时）..."
ulimit -n 655360
ulimit -u 655360

# 改名自身备份（防止重复执行）
mv -- "$0" "${0%.sh}.sh.bak"

echo "✅ BBR + TCP/UDP 全面优化已完成。建议立即重启系统以完全生效。"
read -p "是否现在重启？(y/n): " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    reboot
fi
