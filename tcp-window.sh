#!/bin/bash
# 优化 TCP 网络栈和系统资源限制
# 适用于大多数高并发网络服务器

if [[ $EUID -ne 0 ]]; then
    echo "错误：请以 root 用户身份运行本脚本。"
    exit 1
fi

echo "[1/4] 写入 limits.conf..."
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

echo "[2/4] 修改 PAM 设置..."
grep -q "pam_limits.so" /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session
grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

echo "[3/4] 修改 systemd 文件描述符限制..."
sed -i '/^#*DefaultLimitNOFILE/c\DefaultLimitNOFILE=655360' /etc/systemd/system.conf

echo "[4/4] 写入 sysctl 优化参数..."

cat >/etc/sysctl.d/99-tcp-optimization.conf <<EOF
fs.file-max = 2097152

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
EOF

# 应用 sysctl 参数
sysctl --system

# 应用 ulimit（当前 shell 会话）
ulimit -n 655360
ulimit -u 655360

# 自动删除自身（可选）
# rm -f "$0"

echo "✅ TCP 优化完成。建议手动重启服务器以确保全部生效。"
read -p "现在是否立即重启？(y/n): " ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    reboot
fi
