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
    local start_num="$3"
    local end_num="$4"
    local add_sequence="$5"
    
    echo "📥 开始下载: $url"
    
    # 构建输出文件名模板
    local output_template
    if [ "$add_sequence" = "yes" ]; then
        output_template="$output_path/%(playlist_index)03d - %(upload_date)s - %(title)s.%(ext)s"
        echo "📋 文件命名格式: 序号 - 日期 - 标题.ext"
    else
        output_template="$output_path/%(upload_date)s - %(title)s.%(ext)s"
        echo "📋 文件命名格式: 日期 - 标题.ext"
    fi
    
    # 构建下载范围参数
    local playlist_params=""
    if [ ! -z "$start_num" ] && [ ! -z "$end_num" ]; then
        playlist_params="--playlist-start $start_num --playlist-end $end_num"
        echo "📊 下载范围: 第 $start_num 到第 $end_num 个视频"
    elif [ ! -z "$start_num" ]; then
        playlist_params="--playlist-start $start_num"
        echo "📊 下载范围: 从第 $start_num 个视频开始到最后"
    elif [ ! -z "$end_num" ]; then
        playlist_params="--playlist-end $end_num"
        echo "📊 下载范围: 前 $end_num 个视频"
    else
        echo "📊 下载范围: 所有视频"
    fi
    
    # 策略1: 使用iOS客户端（在Ubuntu上最稳定）
    echo "🔄 策略1: 使用iOS客户端..."
    yt-dlp \
        -f "bestvideo[height=1080]+bestaudio/best[height=1080]" \
        -o "$output_template" \
        --extractor-args "youtube:player_client=ios" \
        --ignore-errors \
        --sleep-interval 2 \
        --download-archive "$output_path/downloaded.txt" \
        $playlist_params \
        "$url"
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 101 ]; then
        echo "✅ 策略1完成！(退出码: $exit_code)"
        echo "📁 下载记录保存在: $output_path/downloaded.txt"
        return 0
    fi
    
    # 策略2: 模拟Windows web客户端
    echo "🔄 策略2: 模拟Windows web客户端..."
    yt-dlp \
        -f "bestvideo[height=1080]+bestaudio/best[height=1080]" \
        -o "$output_template" \
        --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        --extractor-args "youtube:player_client=web" \
        --ignore-errors \
        --sleep-interval 2 \
        --download-archive "$output_path/downloaded.txt" \
        $playlist_params \
        "$url"
    
    exit_code=$?
    
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 101 ]; then
        echo "✅ 策略2完成！(退出码: $exit_code)"
        echo "📁 下载记录保存在: $output_path/downloaded.txt"
        return 0
    fi
    
    # 策略3: 降级格式要求
    echo "🔄 策略3: 降级格式要求..."
    yt-dlp \
        -f "best[height<=1080]/best" \
        -o "$output_template" \
        --extractor-args "youtube:player_client=ios" \
        --ignore-errors \
        --sleep-interval 2 \
        --download-archive "$output_path/downloaded.txt" \
        $playlist_params \
        "$url"
    
    exit_code=$?
    
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 101 ]; then
        echo "✅ 策略3完成！(退出码: $exit_code)"
        echo "📁 下载记录保存在: $output_path/downloaded.txt"
        return 0
    fi
    
    echo "❌ 所有策略都失败了"
    return 1
}

# 函数：获取下载配置
get_download_config() {
    echo ""
    echo "🔧 下载配置选项:"
    
    # 1. 选择保存路径
    read -p "请输入保存路径 (直接回车使用 ./downloads): " custom_path
    if [ -z "$custom_path" ]; then
        custom_path="./downloads"
    fi
    mkdir -p "$custom_path"
    echo "📁 保存路径: $custom_path"
    
    # 2. 是否添加序号
    echo ""
    read -p "是否在文件名前添加序号? (y/n, 直接回车默认是): " add_seq
    if [ -z "$add_seq" ] || [ "$add_seq" = "y" ] || [ "$add_seq" = "Y" ]; then
        add_sequence="yes"
        echo "📋 文件命名: 序号 - 日期 - 标题.ext"
    else
        add_sequence="no"
        echo "📋 文件命名: 日期 - 标题.ext"
    fi
    
    # 3. 选择下载范围
    echo ""
    echo "📊 下载范围选择:"
    echo "1. 下载所有视频"
    echo "2. 下载指定范围 (例: 第10-50个视频)"
    echo "3. 从指定序号开始下载 (例: 从第20个开始)"
    echo "4. 下载前N个视频 (例: 前30个视频)"
    
    read -p "请选择 (1/2/3/4, 直接回车默认1): " range_choice
    
    start_num=""
    end_num=""
    
    case $range_choice in
        2)
            read -p "请输入开始序号: " start_num
            read -p "请输入结束序号: " end_num
            echo "📊 将下载第 $start_num 到第 $end_num 个视频"
            ;;
        3)
            read -p "请输入开始序号: " start_num
            echo "📊 将从第 $start_num 个视频开始下载到最后"
            ;;
        4)
            read -p "请输入要下载的视频数量: " end_num
            echo "📊 将下载前 $end_num 个视频"
            ;;
        *)
            echo "📊 将下载所有视频"
            ;;
    esac
    
    # 返回配置参数
    echo "$custom_path|$start_num|$end_num|$add_sequence"
}
echo "🔍 请选择下载方式:"
echo "1. 测试下载单个视频"
echo "2. 下载频道所有视频"
echo "3. 下载频道直播内容"
echo "4. 下载频道所有内容（视频+直播+短视频）"
echo "5. 自定义URL下载"

read -p "请选择 (1/2/3/4/5): " choice

case $choice in
    1)
        read -p "请输入视频URL: " video_url
        if [ -z "$video_url" ]; then
            video_url="https://www.youtube.com/watch?v=CcsALqR3s7Y"
            echo "使用默认测试视频: $video_url"
        fi
        echo "📺 测试下载单个视频..."
        download_with_windows_strategy "$video_url" "./downloads"
        ;;
    2)
        read -p "请输入频道URL或@用户名 (例: @dlw2023 或完整URL): " channel_input
        if [ -z "$channel_input" ]; then
            channel_input="@dlw2023"
            echo "使用默认频道: $channel_input"
        fi
        
        # 处理用户输入，确保格式正确
        if [[ "$channel_input" == @* ]]; then
            channel_url="https://www.youtube.com/$channel_input/videos"
        elif [[ "$channel_input" == *"youtube.com"* ]]; then
            # 如果已经是完整URL，确保是videos页面
            if [[ "$channel_input" != *"/videos" ]]; then
                channel_url="$channel_input/videos"
            else
                channel_url="$channel_input"
            fi
        else
            channel_url="https://www.youtube.com/@$channel_input/videos"
        fi
        
        echo "📺 下载频道所有视频: $channel_url"
        download_with_windows_strategy "$channel_url" "./downloads"
        ;;
    3)
        read -p "请输入频道URL或@用户名 (例: @dlw2023 或完整URL): " channel_input
        if [ -z "$channel_input" ]; then
            channel_input="@dlw2023"
            echo "使用默认频道: $channel_input"
        fi
        
        # 处理用户输入，确保格式正确
        if [[ "$channel_input" == @* ]]; then
            channel_url="https://www.youtube.com/$channel_input/streams"
        elif [[ "$channel_input" == *"youtube.com"* ]]; then
            # 如果已经是完整URL，确保是streams页面
            if [[ "$channel_input" != *"/streams" ]]; then
                channel_url="$channel_input/streams"
            else
                channel_url="$channel_input"
            fi
        else
            channel_url="https://www.youtube.com/@$channel_input/streams"
        fi
        
        echo "📺 下载频道直播内容: $channel_url"
        download_with_windows_strategy "$channel_url" "./downloads"
        ;;
    4)
        read -p "请输入频道URL或@用户名 (例: @dlw2023 或完整URL): " channel_input
        if [ -z "$channel_input" ]; then
            channel_input="@dlw2023"
            echo "使用默认频道: $channel_input"
        fi
        
        # 处理用户输入，确保格式正确
        if [[ "$channel_input" == @* ]]; then
            channel_url="https://www.youtube.com/$channel_input"
        elif [[ "$channel_input" == *"youtube.com"* ]]; then
            # 移除可能的子页面路径
            channel_url=$(echo "$channel_input" | sed 's|/videos||g' | sed 's|/streams||g' | sed 's|/shorts||g')
        else
            channel_url="https://www.youtube.com/@$channel_input"
        fi
        
        echo "📺 下载频道所有内容: $channel_url"
        download_with_windows_strategy "$channel_url" "./downloads"
        ;;
    5)
        read -p "请输入完整URL: " custom_url
        if [ -z "$custom_url" ]; then
            echo "❌ URL不能为空"
            exit 1
        fi
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
