#!/bin/bash
# 一体化 TCP/UDP 优化脚本，适配 Reality 和 Hysteria2，适合高并发/转发型服务器

if [[ $EUID -ne 0 ]]; then
    echo "错误：请以 root 用户身份运行本脚本。"
    exit 1
fi

echo "[1/6] 清理旧的 sysctl 配置项..."
for file in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
    sed -i '/tcp_rmem/d' "$file"
    sed -i '/tcp_wmem/d' "$file"
    sed -i '/net.core.rmem_max/d' "$file"
    sed -i '/net.core.wmem_max/d' "$file"
    sed -i '/udp_rmem_min/d' "$file"
    sed -i '/udp_wmem_min/d' "$file"
done

echo "[2/6] 写入 limits.conf..."
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

echo "[3/6] 修改 PAM 设置..."
grep -q "pam_limits.so" /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session
grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

echo "[4/6] 修改 systemd 文件描述符限制..."
sed -i '/^#*DefaultLimitNOFILE/c\DefaultLimitNOFILE=655360' /etc/systemd/system.conf

echo "[5/6] 写入新的 TCP+UDP 优化参数..."
cat >/etc/sysctl.d/99-tcp-optimization.conf <<EOF
fs.file-max = 2097152

# TCP 优化参数（Reality适用）
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_rmem = 8192 262144 67108864
net.ipv4.tcp_wmem = 8192 262144 67108864
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_notsent_lowat = 131072
net.core.default_qdisc = fq

# UDP 优化参数（Hysteria2适用）
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF

# 应用 sysctl 参数
echo "[6/6] 应用内核参数..."
sysctl --system

# 当前 shell 的 ulimit 提高（临时，需重启或 loginctl 启用全局）
ulimit -n 655360
ulimit -u 655360

# 删除自身脚本（可注释掉）
# rm -f "$0"

# 重启提示
echo "✅ Reality & Hysteria2 网络栈优化已完成。建议立即重启以完全生效。"
read -p "是否立即重启系统？(y/n): " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    reboot
fi
