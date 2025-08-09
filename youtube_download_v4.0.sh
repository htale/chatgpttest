#!/bin/bash
# 后台YouTube下载器 - 支持后台运行和进度查看

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
PID_FILE="$SCRIPT_DIR/youtube_downloader.pid"
STATUS_FILE="$SCRIPT_DIR/download_status.txt"

# 创建必要的目录
mkdir -p "$LOG_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🎬 后台YouTube下载器"
echo "================================="

# 检查是否有正在运行的下载任务
check_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # 正在运行
        else
            rm -f "$PID_FILE"
            return 1  # 不在运行
        fi
    fi
    return 1  # 不在运行
}

# 显示当前状态
show_status() {
    echo ""
    echo "📊 当前下载状态"
    echo "================="
    
    if check_running; then
        local pid=$(cat "$PID_FILE")
        echo -e "${GREEN}✅ 下载任务正在运行中${NC}"
        echo "🆔 进程ID: $pid"
        
        # 显示最新状态
        if [ -f "$STATUS_FILE" ]; then
            echo "📋 最新状态:"
            tail -5 "$STATUS_FILE"
        fi
        
        # 显示最新日志
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ -f "$latest_log" ]; then
            echo ""
            echo "📄 最新日志 ($(basename "$latest_log")):"
            tail -10 "$latest_log"
        fi
        
        echo ""
        echo "💡 查看完整日志: tail -f $latest_log"
        echo "💡 查看进程状态: ps aux | grep $pid"
        
    else
        echo -e "${YELLOW}⏸️  没有正在运行的下载任务${NC}"
        
        # 显示最近的下载记录
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ -f "$latest_log" ]; then
            echo ""
            echo "📄 上次下载日志 ($(basename "$latest_log")):"
            tail -5 "$latest_log"
        fi
    fi
    
    echo ""
}

# 后台下载函数
background_download() {
    local url="$1"
    local output_path="$2"
    local start_num="$3"
    local end_num="$4"
    local add_sequence="$5"
    local log_file="$6"
    
    # 构建输出文件名模板
    local output_template
    if [ "$add_sequence" = "yes" ]; then
        output_template="$output_path/%(playlist_index)03d - %(upload_date)s - %(title)s.%(ext)s"
    else
        output_template="$output_path/%(upload_date)s - %(title)s.%(ext)s"
    fi
    
    # 构建下载范围参数
    local playlist_params=""
    if [ ! -z "$start_num" ] && [ ! -z "$end_num" ]; then
        playlist_params="--playlist-start $start_num --playlist-end $end_num"
    elif [ ! -z "$start_num" ]; then
        playlist_params="--playlist-start $start_num"
    elif [ ! -z "$end_num" ]; then
        playlist_params="--playlist-end $end_num"
    fi
    
    # 记录开始状态
    echo "$(date): 开始下载 - $url" >> "$STATUS_FILE"
    echo "保存路径: $output_path" >> "$STATUS_FILE"
    echo "下载范围: ${start_num:-1} - ${end_num:-all}" >> "$STATUS_FILE"
    echo "=================================" >> "$STATUS_FILE"
    
    # 执行下载 (使用iOS客户端策略)
    yt-dlp \
        -f "bestvideo[height=1080]+bestaudio/best[height=1080]" \
        -o "$output_template" \
        --extractor-args "youtube:player_client=ios" \
        --ignore-errors \
        --sleep-interval 2 \
        --download-archive "$output_path/downloaded.txt" \
        --progress \
        --newline \
        $playlist_params \
        "$url" >> "$log_file" 2>&1
    
    local exit_code=$?
    
    # 记录完成状态
    echo "$(date): 下载完成 - 退出码: $exit_code" >> "$STATUS_FILE"
    
    # 清理PID文件
    rm -f "$PID_FILE"
    
    return $exit_code
}

# 获取下载配置
get_download_config() {
    echo ""
    echo "🔧 下载配置:"
    
    # 1. 选择保存路径
    read -p "请输入保存路径 (直接回车使用 ./downloads): " custom_path
    if [ -z "$custom_path" ]; then
        custom_path="./downloads"
    fi
    mkdir -p "$custom_path"
    
    # 2. 是否添加序号
    read -p "是否在文件名前添加序号? (y/n, 默认y): " add_seq
    if [ -z "$add_seq" ] || [ "$add_seq" = "y" ] || [ "$add_seq" = "Y" ]; then
        add_sequence="yes"
    else
        add_sequence="no"
    fi
    
    # 3. 选择下载范围
    echo ""
    echo "📊 下载范围:"
    echo "1. 下载所有视频"
    echo "2. 下载指定范围 (例: 10-50)"
    echo "3. 从指定序号开始 (例: 从20开始)"
    echo "4. 下载前N个视频 (例: 前30个)"
    
    read -p "请选择 (1-4, 默认1): " range_choice
    
    start_num=""
    end_num=""
    
    case $range_choice in
        2)
            read -p "开始序号: " start_num
            read -p "结束序号: " end_num
            ;;
        3)
            read -p "开始序号: " start_num
            ;;
        4)
            read -p "视频数量: " end_num
            ;;
    esac
    
    echo "$custom_path|$start_num|$end_num|$add_sequence"
}

# 主菜单
show_status

echo "🔍 请选择操作:"
echo "1. 开始新的下载任务"
echo "2. 查看当前下载状态"
echo "3. 停止当前下载"
echo "4. 查看历史日志"
echo "5. 清理日志文件"

read -p "请选择 (1-5): " choice

case $choice in
    1)
        if check_running; then
            echo -e "${YELLOW}⚠️  已有下载任务在运行中，请先停止或等待完成${NC}"
            exit 1
        fi
        
        echo ""
        echo "📺 选择下载类型:"
        echo "1. 测试单个视频"
        echo "2. 频道所有视频" 
        echo "3. 频道直播内容"
        echo "4. 频道所有内容"
        echo "5. 自定义URL"
        
        read -p "请选择 (1-5): " download_type
        
        case $download_type in
            1)
                read -p "视频URL: " video_url
                [ -z "$video_url" ] && video_url="https://www.youtube.com/watch?v=CcsALqR3s7Y"
                url="$video_url"
                ;;
            2)
                read -p "频道名 (如@dlw2023): " channel_input
                [ -z "$channel_input" ] && channel_input="@dlw2023"
                [[ "$channel_input" == @* ]] && channel_input="https://www.youtube.com/$channel_input/videos" || channel_input="https://www.youtube.com/@$channel_input/videos"
                url="$channel_input"
                ;;
            3)
                read -p "频道名 (如@dlw2023): " channel_input
                [ -z "$channel_input" ] && channel_input="@dlw2023"
                [[ "$channel_input" == @* ]] && channel_input="https://www.youtube.com/$channel_input/streams" || channel_input="https://www.youtube.com/@$channel_input/streams"
                url="$channel_input"
                ;;
            4)
                read -p "频道名 (如@dlw2023): " channel_input
                [ -z "$channel_input" ] && channel_input="@dlw2023"
                [[ "$channel_input" == @* ]] && channel_input="https://www.youtube.com/$channel_input" || channel_input="https://www.youtube.com/@$channel_input"
                url="$channel_input"
                ;;
            5)
                read -p "完整URL: " url
                [ -z "$url" ] && { echo "URL不能为空"; exit 1; }
                ;;
            *)
                echo "无效选择"
                exit 1
                ;;
        esac
        
        # 获取配置
        config=$(get_download_config)
        IFS='|' read -r output_path start_num end_num add_sequence <<< "$config"
        
        # 创建日志文件
        timestamp=$(date +"%Y%m%d_%H%M%S")
        log_file="$LOG_DIR/download_$timestamp.log"
        
        echo ""
        echo -e "${GREEN}🚀 启动后台下载任务...${NC}"
        echo "📁 保存路径: $output_path"
        echo "📄 日志文件: $log_file"
        echo ""
        
        # 后台执行下载
        nohup bash -c "
            # 记录PID
            echo \$$ > '$PID_FILE'
            
            # 调用下载函数
            $(declare -f background_download)
            background_download '$url' '$output_path' '$start_num' '$end_num' '$add_sequence' '$log_file'
        " &
        
        sleep 2  # 等待进程启动
        
        if check_running; then
            echo -e "${GREEN}✅ 后台任务已启动${NC}"
            echo "🆔 进程ID: $(cat "$PID_FILE")"
            echo "💡 查看进度: tail -f $log_file"
            echo "💡 查看状态: $0 选择选项2"
        else
            echo -e "${RED}❌ 后台任务启动失败${NC}"
        fi
        ;;
        
    2)
        show_status
        ;;
        
    3)
        if check_running; then
            local pid=$(cat "$PID_FILE")
            echo -e "${YELLOW}⚠️  正在停止下载任务 (PID: $pid)...${NC}"
            kill "$pid"
            sleep 2
            
            if check_running; then
                echo -e "${YELLOW}强制停止...${NC}"
                kill -9 "$pid"
                rm -f "$PID_FILE"
            fi
            
            echo -e "${GREEN}✅ 下载任务已停止${NC}"
        else
            echo -e "${YELLOW}ℹ️  没有正在运行的下载任务${NC}"
        fi
        ;;
        
    4)
        echo "📚 历史日志文件:"
        ls -la "$LOG_DIR"/*.log 2>/dev/null || echo "没有找到日志文件"
        
        echo ""
        read -p "请输入要查看的日志文件名 (或直接回车查看最新): " log_name
        
        if [ -z "$log_name" ]; then
            latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
            [ -f "$latest_log" ] && less "$latest_log" || echo "没有找到日志文件"
        else
            [ -f "$LOG_DIR/$log_name" ] && less "$LOG_DIR/$log_name" || echo "日志文件不存在"
        fi
        ;;
        
    5)
        read -p "确认清理所有日志文件? (y/N): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -f "$LOG_DIR"/*.log
            rm -f "$STATUS_FILE"
            echo -e "${GREEN}✅ 日志文件已清理${NC}"
        else
            echo "操作已取消"
        fi
        ;;
        
    *)
        echo "无效选择"
        exit 1
        ;;
esac
