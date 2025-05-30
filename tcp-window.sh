#!/bin/bash
# 优化 TCP 参数并提升系统连接数上限
# 原始来源：https://1024.day，优化自定义

# 1. 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    clear
    echo "错误：该脚本必须以 root 用户运行！"
    exit 1
fi

# 2. 配置 limits.conf 提高文件句柄数和进程数
cat >/etc/security/limits.conf <<EOF
* soft     nproc          655360
* hard     nproc          655360
* soft     nofile         655360
* hard     nofile         655360
root soft  nproc          655360
root hard  nproc          655360
root soft  nofile         655360
root hard  nofile         655360
EOF

# 3. 确保 pam_limits.so 被启用
grep -q "pam_limits.so" /etc/pam.d/common-session || echo "session required pam_limits.so" >> /etc/pam.d/common-session
grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive || echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

# 4. 设置 systemd 默认 NOFILE 限制
sed -i '/^#*DefaultLimitNOFILE/c\DefaultLimitNOFILE=655360' /etc/systemd/system.conf

# 5. sysctl 内核参数优化
cat >/etc/sysctl.d/99-sysctl-tcp.conf <<EOF
fs.file-max = 2097152
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 250000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 8192 262144 167772160
net.ipv4.tcp_wmem = 8192 262144 167772160
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_fin_timeout = 10
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl --system

# 6. 可选：立即应用 limits 限制（需重启才完全生效）
ulimit -n 655360
ulimit -u 655360

# 7. 清理自身
rm -f "$0"

# 8. 重启提示（建议手动确认）
echo "优化完成，建议重启系统以确保所有设置生效。"
read -p "现在是否立即重启？(y/n): " ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    reboot
fi
