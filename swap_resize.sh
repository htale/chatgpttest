#!/bin/bash

SWAPFILE="/swapfile"

# 获取总内存大小（单位：GB）
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
CURRENT_SWAP=$(free -g | awk '/^Swap:/ {print $2}')

echo "🔍 检测到服务器总内存：${TOTAL_RAM_GB}G，当前 Swap：${CURRENT_SWAP}G"

# 推荐规则
if [ "$TOTAL_RAM_GB" -le 2 ]; then
    RECOMMENDED_SWAP=2
elif [ "$TOTAL_RAM_GB" -le 8 ]; then
    RECOMMENDED_SWAP=$TOTAL_RAM_GB
else
    RECOMMENDED_SWAP=$((TOTAL_RAM_GB / 2))
fi

# 用户输入
echo "💡 推荐 Swap 大小为：${RECOMMENDED_SWAP}G"
read -p "是否使用推荐值？(Y/n): " use_recommended

if [[ "$use_recommended" =~ ^[Nn]$ ]]; then
    read -p "请输入你想设置的 Swap 大小 (单位 G，例如 4): " CUSTOM_SWAP
    # 校验数字
    if ! [[ "$CUSTOM_SWAP" =~ ^[0-9]+$ ]]; then
        echo "❌ 输入无效，必须是整数，退出。"
        exit 1
    fi
    SWAP_SIZE_GB=$CUSTOM_SWAP
else
    SWAP_SIZE_GB=$RECOMMENDED_SWAP
fi

echo "⚙️ 开始设置 ${SWAP_SIZE_GB}G 的 Swap..."

# 关闭现有 swap
swapoff -a 2>/dev/null

# 删除旧 swapfile（如果存在）
[ -f "$SWAPFILE" ] && rm -f "$SWAPFILE"

# 创建新的 swapfile
dd if=/dev/zero of=$SWAPFILE bs=1G count=$SWAP_SIZE_GB status=progress

# 设置权限
chmod 600 $SWAPFILE

# 格式化 swap
mkswap $SWAPFILE

# 启用 swap
swapon $SWAPFILE

# 添加到 /etc/fstab（如果还没添加）
grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

# 显示当前状态
echo "✅ 新的 Swap 设置完成："
swapon --show
free -h
