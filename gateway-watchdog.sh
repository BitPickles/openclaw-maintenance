#!/bin/bash
#
# OpenClaw Gateway Watchdog
# 自动监控并重启异常退出的 Gateway 服务
#
# 安装: launchctl load ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
# 卸载: launchctl unload ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
#

# 配置
CHECK_INTERVAL=60                                    # 检查间隔（秒）
HEALTH_URL="${OPENCLAW_HEALTH_URL:-http://127.0.0.1:18789/healthz}"         # 健康检查 URL
LOCK_FILE="/tmp/openclaw-restart.lock"              # 重启锁文件
LOG_FILE="$HOME/.openclaw/logs/watchdog.log"        # 日志文件
MAX_LOG_SIZE=1048576                                # 日志最大 1MB
MAX_RETRY=3                                         # 最大重试次数
RETRY_DELAY=10                                      # 重试间隔（秒）

# 通知配置
NOTIFY_CHANNEL="${OPENCLAW_NOTIFY_CHANNEL:-telegram}"
NOTIFY_TARGET="${OPENCLAW_NOTIFY_TARGET:-YOUR_TELEGRAM_ID}"
OPENCLAW_BIN="${OPENCLAW_BIN:-/opt/homebrew/bin/openclaw}"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数（带轮转）
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 检查日志大小，超过则轮转
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 通知函数（通过 OpenClaw CLI）
notify_boss() {
    local message="$1"
    "$OPENCLAW_BIN" message send \
        --channel "$NOTIFY_CHANNEL" \
        --target "$NOTIFY_TARGET" \
        --message "$message" \
        --account engineer \
        > /dev/null 2>&1
}

# 检查 Gateway 健康状态
check_health() {
    curl -s -m 5 "$HEALTH_URL" > /dev/null 2>&1
    return $?
}

# 检查是否存在重启锁
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        # 检查锁文件是否超过 5 分钟（防止锁文件残留）
        local lock_age=$(( $(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || stat -c%Y "$LOCK_FILE" 2>/dev/null) ))
        if [[ $lock_age -gt 300 ]]; then
            log "WARN" "Lock file stale (${lock_age}s), removing"
            rm -f "$LOCK_FILE"
            return 1
        fi
        return 0
    fi
    return 1
}

# 重启 Gateway
restart_gateway() {
    log "INFO" "Attempting to restart gateway..."
    
    # 创建锁文件（防止自己触发的重启被检测为异常）
    touch "$LOCK_FILE"
    
    # 执行重启
    /opt/homebrew/bin/openclaw gateway restart > /dev/null 2>&1
    local result=$?
    
    # 等待服务启动
    sleep 5
    
    # 删除锁文件
    rm -f "$LOCK_FILE"
    
    return $result
}

# 主循环
main() {
    log "INFO" "Watchdog started (interval: ${CHECK_INTERVAL}s)"
    
    local consecutive_failures=0
    local last_healthy_log=$(date +%s)
    
    while true; do
        sleep "$CHECK_INTERVAL"
        
        # 检查锁文件
        if check_lock; then
            log "INFO" "Lock file present, skipping check"
            continue
        fi
        
        # 健康检查
        if check_health; then
            # 健康 - 每小时记录一次
            local now=$(date +%s)
            if [[ $((now - last_healthy_log)) -ge 3600 ]]; then
                log "OK" "Gateway healthy"
                last_healthy_log=$now
            fi
            consecutive_failures=0
        else
            # 不健康 - 尝试重启
            consecutive_failures=$((consecutive_failures + 1))
            log "WARN" "Gateway unreachable (attempt $consecutive_failures/$MAX_RETRY)"
            
            if [[ $consecutive_failures -ge $MAX_RETRY ]]; then
                log "ERROR" "Gateway failed $MAX_RETRY consecutive checks, attempting restart..."
                
                if restart_gateway && check_health; then
                    log "OK" "Gateway restart successful"
                    notify_boss "✅ OpenClaw Watchdog: Gateway 自动重启成功"
                    consecutive_failures=0
                else
                    log "ERROR" "Gateway restart FAILED"
                    notify_boss "🚨 OpenClaw Watchdog: Gateway 重启失败！需要人工干预。请检查: openclaw status"
                    # 重置计数器，避免无限重启
                    consecutive_failures=0
                    # 失败后等待更长时间再试
                    sleep 300
                fi
            fi
        fi
    done
}

# 运行
main
