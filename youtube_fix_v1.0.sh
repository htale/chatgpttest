#!/bin/bash
# Ubuntu YouTube下载修复脚本
# 模拟Windows环境成功的下载方式

echo "🐧 Ubuntu YouTube下载修复工具"
echo "====================================="

# 创建下载目录
mkdir -p ./downloads

echo "🔧 正在检查和修复环境..."

# 1. 检查yt-dlp版本
current_version=$(yt-dlp --version 2>/dev/null || echo "未安装")
echo "当前yt-dlp版本: $current_version"

# 2. 更新到最新版本（使用多种方法）
echo "🔄 更新yt-dlp到最新版本..."

# 方法1: 直接下载最新版本
echo "下载最新版本..."
sudo wget -q -O /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp
sudo chmod +x /usr/local/bin/yt-dlp

# 验证版本
new_version=$(yt-dlp --version)
echo "✅ 更新后版本: $new_version"

echo ""
echo "🎯 使用与Windows相同的下载策略..."

# 函数：模拟Windows环境下载
download_with_windows_strategy() {
    local url="$1"
    local output_path="$2"
    
    echo "📥 开始下载: $url"
    
    # 策略1: 使用iOS客户端（在Ubuntu上最稳定）
    echo "🔄 策略1: 使用iOS客户端..."
    yt-dlp \
        -f "bestvideo[height=1080]+bestaudio/best[height=1080]" \
        -o "$output_path/%(upload_date)s - %(title)s.%(ext)s" \
        --extractor-args "youtube:player_client=ios" \
        "$url"
    
    if [ $? -eq 0 ]; then
        echo "✅ 策略1成功！"
        return 0
    fi
    
    # 策略2: 模拟Windows web客户端
    echo "🔄 策略2: 模拟Windows web客户端..."
    yt-dlp \
        -f "bestvideo[height=1080]+bestaudio/best[height=1080]" \
        -o "$output_path/%(upload_date)s - %(title)s.%(ext)s" \
        --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        --extractor-args "youtube:player_client=web" \
        "$url"
    
    if [ $? -eq 0 ]; then
        echo "✅ 策略2成功！"
        return 0
    fi
    
    # 策略3: 降级格式要求
    echo "🔄 策略3: 降级格式要求..."
    yt-dlp \
        -f "best[height<=1080]/best" \
        -o "$output_path/%(upload_date)s - %(title)s.%(ext)s" \
        --extractor-args "youtube:player_client=ios" \
        "$url"
    
    if [ $? -eq 0 ]; then
        echo "✅ 策略3成功！"
        return 0
    fi
    
    # 策略4: 最基础的下载
    echo "🔄 策略4: 基础下载..."
    yt-dlp \
        -o "$output_path/%(upload_date)s - %(title)s.%(ext)s" \
        --extractor-args "youtube:player_client=ios" \
        "$url"
    
    if [ $? -eq 0 ]; then
        echo "✅ 策略4成功！"
        return 0
    fi
    
    echo "❌ 所有策略都失败了"
    return 1
}

# 主菜单
echo "🔍 请选择下载方式:"
echo "1. 测试下载单个视频"
echo "2. 下载频道所有视频"
echo "3. 下载频道直播内容"
echo "4. 自定义URL下载"

read -p "请选择 (1/2/3/4): " choice

case $choice in
    1)
        echo "📺 测试下载单个视频..."
        download_with_windows_strategy \
            "https://www.youtube.com/watch?v=CcsALqR3s7Y" \
            "./downloads"
        ;;
    2)
        echo "📺 下载频道所有视频..."
        download_with_windows_strategy \
            "https://www.youtube.com/@dlw2023/videos" \
            "./downloads"
        ;;
    3)
        echo "📺 下载频道直播内容..."
        download_with_windows_strategy \
            "https://www.youtube.com/@dlw2023/streams" \
            "./downloads"
        ;;
    4)
        read -p "请输入URL: " custom_url
        read -p "请输入保存路径 (直接回车使用./downloads): " custom_path
        if [ -z "$custom_path" ]; then
            custom_path="./downloads"
        fi
        mkdir -p "$custom_path"
        download_with_windows_strategy "$custom_url" "$custom_path"
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac

echo ""
echo "📊 下载完成！"
echo "📁 文件保存在指定目录中"
echo "💡 提示: 如果下载失败，可能需要使用代理或VPN"
