#!/bin/bash
#
# OpenClaw 日志清理脚本
# 只保留 3 天的日志，直接删除
#

set -euo pipefail

LOG_DIR="$HOME/.openclaw/logs"
KEEP_DAYS=3
MAX_LOG_SIZE=10485760

echo "=== OpenClaw 日志清理 ==="
echo "日志目录: $LOG_DIR"
echo "保留天数: $KEEP_DAYS 天"
echo ""

# 删除超过保留期的日志文件
echo "清理过期日志..."
find "$LOG_DIR" -name "*.log" -type f -mtime +$KEEP_DAYS -delete
find "$LOG_DIR" -name "*.err.log" -type f -mtime +$KEEP_DAYS -delete
find "$LOG_DIR/archive" -type f -mtime +$KEEP_DAYS -delete

# 删除过大的日志文件
for log_file in "$LOG_DIR"/*.log "$LOG_DIR"/*.err.log; do
    [ -f "$log_file" ] || continue
    
    size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
    size_mb=$((size / 1024 / 1024))
    base_name=$(basename "$log_file")
    
    if [ $size -gt $MAX_LOG_SIZE ]; then
        echo "🗑️  删除 $base_name (${size_mb}MB，超过限制)"
        rm "$log_file"
        touch "$log_file"
    else
        echo "✓ $base_name (${size_mb}MB)"
    fi
done

echo ""
echo "=== 清理完成 ==="
df -h "$LOG_DIR" | tail -1
