#!/bin/bash
#############################################
# Chatwoot v2.17.0 Docker 安装一键脚本（适用于宝塔）
# 文磊专用 - Chatwoot 客服系统
#############################################

echo -e "\n📦 开始安装 Chatwoot v2.17.0..."

# 安装必要工具
apt update -y
apt install -y git curl docker.io docker-compose

# 启动并设置 Docker 开机启动
systemctl enable docker
systemctl start docker

# 切换到网站根目录或你希望安装的地方
cd /www/wwwroot || exit

# 克隆 Chatwoot 源码并切换版本
rm -rf chatwoot
git clone https://github.com/chatwoot/chatwoot.git
cd chatwoot || exit
git checkout v2.17.0

# 拷贝环境文件
cp .env.example .env

# 启动容器
docker compose up -d

# 输出访问提醒
echo -e "\n✅ Chatwoot 安装完成！请到宝塔设置反向代理："
echo -e "   ➤ 将子域名（如 chat.你的域名.com）指向 http://127.0.0.1:3000"
echo -e "   ➤ 可选：在宝塔为该站点开启免费 SSL 证书"
echo -e "   ➤ 默认管理后台访问地址：http://chat.你的域名.com"
echo -e "\n💡 首次访问请注册一个管理员账号！"
