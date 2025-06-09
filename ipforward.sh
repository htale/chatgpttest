#!/bin/bash

echo "=== TinyPortMapper 一键安装与配置 ==="

# 安装依赖
echo "[1/5] 安装编译依赖..."
apt-get update && apt-get install -y git build-essential || yum install -y git gcc make

# 克隆并编译
echo "[2/5] 下载 tinyPortMapper 并编译..."
cd /opt || exit
if [ ! -d "tinyPortMapper" ]; then
    git clone https://github.com/wangyu-/tinyPortMapper.git
fi
cd tinyPortMapper || exit
make

# 获取用户输入
echo "[3/5] 配置端口转发参数"
read -rp "请输入目标服务器IP（如 1.1.1.1）: " TARGET_IP
read -rp "请输入目标端口（如 6688）: " TARGET_PORT
read -rp "请输入本地TCP监听端口（如 8182）: " LOCAL_TCP_PORT
read -rp "请输入本地UDP监听端口（如 7799）: " LOCAL_UDP_PORT

# 启动 TCP 后台转发
echo "[4/5] 启动 TCP 转发: 本地 $LOCAL_TCP_PORT → 远程 $TARGET_IP:$TARGET_PORT"
nohup ./tinyPortMapper -l0.0.0.0:$LOCAL_TCP_PORT -r$TARGET_IP:$TARGET_PORT > /var/log/tpm_tcp_$LOCAL_TCP_PORT.log 2>&1 &

# 启动 UDP 后台转发
echo "[4/5] 启动 UDP 转发: 本地 $LOCAL_UDP_PORT → 远程 $TARGET_IP:$TARGET_PORT"
nohup ./tinyPortMapper -u -l0.0.0.0:$LOCAL_UDP_PORT -r$TARGET_IP:$TARGET_PORT > /var/log/tpm_udp_$LOCAL_UDP_PORT.log 2>&1 &

# 显示运行状态
echo "[5/5] 转发服务已启动。"
echo "TCP 日志文件: /var/log/tpm_tcp_$LOCAL_TCP_PORT.log"
echo "UDP 日志文件: /var/log/tpm_udp_$LOCAL_UDP_PORT.log"
echo "你可以使用命令 'ps -ef | grep tinyPortMapper' 查看运行状态"
