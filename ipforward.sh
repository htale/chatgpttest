#!/bin/bash

echo "=== TinyPortMapper 安装与配置脚本（支持公网转发）==="

# 安装依赖
echo "[1/6] 安装依赖..."
apt-get update && apt-get install -y git build-essential curl || yum install -y git gcc make curl

# 克隆项目
echo "[2/6] 下载并编译 tinyPortMapper..."
cd /opt || exit
if [ ! -d "tinyPortMapper" ]; then
    git clone https://github.com/wangyu-/tinyPortMapper.git
fi
cd tinyPortMapper || exit
make

# 获取公网 IP
PUBLIC_IP=$(curl -s https://api.ipify.org)
echo "[提示] 当前服务器公网 IP：$PUBLIC_IP"

# 设置 TCP 转发
echo "[3/6] 设置 TCP 转发"
read -rp "请输入本地监听IP（默认 0.0.0.0 监听所有网卡）: " LOCAL_IP
LOCAL_IP=${LOCAL_IP:-0.0.0.0}
read -rp "请输入本地TCP监听端口（如 20101）: " LOCAL_TCP_PORT
read -rp "请输入目标服务器IP（如 38.49.57.71）: " TARGET_TCP_IP
read -rp "请输入目标TCP端口（如 11478）: " TARGET_TCP_PORT

# 设置 UDP 转发
echo "[4/6] 设置 UDP 转发"
read -rp "请输入本地UDP监听端口（如 20102）: " LOCAL_UDP_PORT
read -rp "请输入目标服务器IP（如 38.49.57.71）: " TARGET_UDP_IP
read -rp "请输入目标UDP端口（如 10535）: " TARGET_UDP_PORT

# 启动 TCP
echo "[5/6] 启动 TCP 转发服务..."
nohup ./tinyPortMapper -l${LOCAL_IP}:${LOCAL_TCP_PORT} -r${TARGET_TCP_IP}:${TARGET_TCP_PORT} > /var/log/tpm_tcp_${LOCAL_TCP_PORT}.log 2>&1 &

# 启动 UDP
echo "[6/6] 启动 UDP 转发服务..."
nohup ./tinyPortMapper -u -l${LOCAL_IP}:${LOCAL_UDP_PORT} -r${TARGET_UDP_IP}:${TARGET_UDP_PORT} > /var/log/tpm_udp_${LOCAL_UDP_PORT}.log 2>&1 &

# 提示信息
echo ""
echo "✅ 转发配置完成："
echo "  [TCP] ${LOCAL_IP}:${LOCAL_TCP_PORT} → ${TARGET_TCP_IP}:${TARGET_TCP_PORT}"
echo "  [UDP] ${LOCAL_IP}:${LOCAL_UDP_PORT} → ${TARGET_UDP_IP}:${TARGET_UDP_PORT}"
echo ""
echo "🌐 你现在可以通过公网访问："
echo "  TCP: http://${PUBLIC_IP}:${LOCAL_TCP_PORT}"
echo "  UDP: ${PUBLIC_IP}:${LOCAL_UDP_PORT}（需目标服务响应）"
echo ""
echo "📄 日志文件："
echo "  TCP: /var/log/tpm_tcp_${LOCAL_TCP_PORT}.log"
echo "  UDP: /var/log/tpm_udp_${LOCAL_UDP_PORT}.log"
echo ""
echo "📌 查看运行状态："
echo "  ps -ef | grep tinyPortMapper"
echo "  ss -tuln | grep -E '${LOCAL_TCP_PORT}|${LOCAL_UDP_PORT}'"
