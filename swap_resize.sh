#!/bin/bash

# 指定新的 Swap 大小（单位：G）
NEW_SWAP_SIZE_GB=4

# Swap 文件路径
SWAPFILE="/swapfile"

echo "📦 开始修改 Swap 为 ${NEW_SWAP_SIZE_GB}G"

# 关闭现有 swap
echo "🔧 关闭现有 Swap..."
swapoff -a

# 删除原 swap 文件（如果存在）
if [ -f "$SWAPFILE" ]; then
    echo "🗑️ 删除旧 swapfile..."
    rm -f "$SWAPFILE"
fi

# 创建新的 swap 文件
echo "📝 创建 ${NEW_SWAP_SIZE_GB}G 的 swapfile..."
dd if=/dev/zero of=$SWAPFILE bs=1G count=$NEW_SWAP_SIZE_GB status=progress

# 设置权限
chmod 600 $SWAPFILE

# 格式化为 swap
mkswap $SWAPFILE

# 启用 swap
swapon $SWAPFILE

# 检查 /etc/fstab 中是否有 swapfile 项
if grep -q "$SWAPFILE" /etc/fstab; then
    echo "✅ fstab 中已有 swapfile 条目"
else
    echo "🔧 添加 swapfile 到 /etc/fstab..."
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# 显示 swap 状态
echo "✅ 当前 swap 使用情况："
swapon --show

free -h
