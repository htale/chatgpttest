#!/bin/bash

echo "========= 硬盘运行时间检测脚本 ========="
echo ""

# 检查 smartmontools 是否安装
if ! command -v smartctl &> /dev/null; then
    echo "smartctl 未安装，正在尝试安装..."
    if [ -f /etc/debian_version ]; then
        sudo apt update && sudo apt install -y smartmontools
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y smartmontools
    else
        echo "未知系统，请手动安装 smartmontools"
        exit 1
    fi
fi

echo ""
echo "🔍 正在检测 SATA 和 NVMe 硬盘..."

# 检查所有硬盘（SATA）
for disk in /dev/sd?; do
    echo ""
    echo "=== 检测 $disk ==="
    smartctl -i -A "$disk" | grep -E "Model|Serial|Power_On_Hours"
done

# 检查所有 NVMe 硬盘
for nvme in /dev/nvme?n?; do
    echo ""
    echo "=== 检测 $nvme (NVMe) ==="
    smartctl -i -A "$nvme" | grep -E "Model|Serial|Power_On Hours"
done

echo ""
echo "✅ 检测完成"
