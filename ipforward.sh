#!/bin/bash

echo "=== TinyPortMapper 安装与自定义端口转发配置 ==="

# 安装依赖
echo "[1/6] 安装依赖（若已安装将自动跳过）..."
apt-get update && apt-get install -y git build-essential curl || yum install -y git gcc make curl

# 克隆项目并编译
echo "[2/6] 下载 tinyPortMapper 并编译..."
cd /opt || exit
if [ ! -d "tinyPortMapper" ]; then
    git clone https://github.com/wangyu-/tinyPortMapper.git
fi
cd tinyPortMapper || exit
make

# 获取本地默认 IP
DEFAULT_LOCAL_IP=$(hostname -I | awk '{print $1}')

# 获取 TCP 参数
echo "[3/6] 设置 TCP 转发"
read -rp "请输入本地服务器IP（默认: $DEFAULT_LOCAL_IP）: " LOCAL_IP
LOCAL_IP=${LOCAL_IP:-$DEFAULT_LOCAL_IP}
read -rp "请输入本地TCP监听端口（如 1112）: " LOCAL_TCP_PORT
read -rp "请输入目标服务器IP（如 2.2.2.2）: " TARGET_TCP_IP
read -rp "请输入目标TCP端口（如 3222）: " TARGET_TCP_PORT

# 获取 UDP 参数
echo "[4/6] 设置 UDP 转发"
read -rp "请输入本地UDP监听端口（如 1113）: " LOCAL_UDP_PORT
read -rp "请输入目标服务器IP（如 2.2.2.2）: " TARGET_UDP_IP
read -rp "请输入目标UDP端口（如 3223）: " TARGET_UDP_PORT

# 启动 TCP 后台服务
echo "[5/6] 启动 TCP 转发服务..."
nohup ./tinyPortMapper -l${LOCAL_IP}:${LOCAL_TCP_PORT} -r${TARGET_TCP_IP}:${TARGET_TCP_PORT} > /var/log/tpm_tcp_${LOCAL_TCP_PORT}.log 2>&1 &

# 启动 UDP 后台服务
echo "[6/6] 启动 UDP 转发服务..."
nohup ./tinyPortMapper -u -l${LOCAL_IP}:${LOCAL_UDP_PORT} -r${TARGET_UDP_IP}:${TARGET_UDP_PORT} > /var/log/tpm_udp_${LOCAL_UDP_PORT}.log 2>&1 &

echo ""
echo "✅ 转发配置完成："
echo "  [TCP] $LOCAL_IP:$LOCAL_TCP_PORT → $TARGET_TCP_IP:$TARGET_TCP_PORT"
echo "  [UDP] $LOCAL_IP:$LOCAL_UDP_PORT → $TARGET_UDP_IP:$TARGET_UDP_PORT"
echo ""
echo "📄 日志文件位置："
echo "  TCP: /var/log/tpm_tcp_${LOCAL_TCP_PORT}.log"
echo "  UDP: /var/log/tpm_udp_${LOCAL_UDP_PORT}.log"
echo ""
echo "📌 查看进程：ps -ef | grep tinyPortMapper"
echo "📌 查看监听端口：ss -tuln | grep -E '${LOCAL_TCP_PORT}|${LOCAL_UDP_PORT}'"
