#!/bin/bash

echo "========= 改进版硬盘运行时间检测脚本 ========="
echo ""

# 检查 smartctl 是否存在
if ! command -v smartctl &> /dev/null; then
    echo "❌ smartctl 未安装，正在尝试安装 smartmontools..."
    if [ -f /etc/debian_version ]; then
        sudo apt update && sudo apt install -y smartmontools
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y smartmontools
    else
        echo "❌ 无法识别系统类型，请手动安装 smartmontools 后重试"
        exit 1
    fi
fi

echo ""
echo "🔍 开始扫描磁盘..."

# 支持的磁盘设备类型
devices=$(lsblk -ndo NAME,TYPE | awk '$2 == "disk" { print "/dev/" $1 }')

for dev in $devices; do
    echo ""
    echo "=== 检测 $dev ==="

    # 检测是否为NVMe
    if [[ "$dev" == *nvme* ]]; then
        sudo smartctl -i -A "$dev" | grep -E "Model Number|Serial Number|Power_On Hours"
    else
        sudo smartctl -i -A "$dev" | grep -E "Model|Serial|Power_On_Hours"
    fi
done

echo ""
echo "✅ 检测完成"
