#!/bin/bash
#
# Proxy Health Monitor
# 监控 delivery-queue 积压，自动切换 VPN 节点
#
# 安装: launchctl load ~/Library/LaunchAgents/ai.openclaw.proxy-health.plist
#

set -euo pipefail

# ============ 配置 ============
QUEUE_DIR="$HOME/.openclaw/delivery-queue"
QUEUE_THRESHOLD=3
LOG_FILE="$HOME/.openclaw/logs/proxy-health.log"
MAX_LOG_SIZE=5242880
DEBUG=false

# Clash API 配置
CLASH_API="${CLASH_API:-http://127.0.0.1:9097}"
CLASH_SECRET="${CLASH_SECRET:-set-your-secret}"
DELAY_TEST_URL="${DELAY_TEST_URL:-https://api.telegram.org}"
DELAY_TIMEOUT=5000
DELAY_THRESHOLD=3000

# 节点优先级（逗号分隔）
IFS=',' read -r -a REGIONS <<< "${PROXY_REGIONS:-TWN,JPN,HKG}"

# 通知配置
OPENCLAW_BIN="/opt/homebrew/bin/openclaw"
NOTIFY_CHANNEL="${OPENCLAW_NOTIFY_CHANNEL:-telegram}"
NOTIFY_TARGET="${OPENCLAW_NOTIFY_TARGET:-YOUR_TELEGRAM_ID}"
NOTIFY_ACCOUNT="${OPENCLAW_NOTIFY_ACCOUNT:-engineer}"

# 通知冷却时间（秒）
NOTIFY_COOLDOWN=300
NOTIFY_STATE_FILE="/tmp/proxy-health-notify.state"

# ============ 工具函数 ============
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # DEBUG 日志可选
    if [[ "$level" == "DEBUG" && "$DEBUG" != "true" ]]; then
        return 0
    fi

    # 日志轮转
    if [[ -f "$LOG_FILE" ]]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $MAX_LOG_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d-%H%M%S).old"
        fi
    fi

    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$timestamp] [$level] $message"
}

check_notify_cooldown() {
    if [[ ! -f "$NOTIFY_STATE_FILE" ]]; then
        echo "0"
        return 0
    fi
    local last_notify=$(cat "$NOTIFY_STATE_FILE" 2>/dev/null || echo "0")
    local now=$(date +%s)
    echo "$((now - last_notify))"
}

update_notify_time() {
    date +%s > "$NOTIFY_STATE_FILE"
}

notify_boss() {
    local message="$1"
    local cooldown=$(check_notify_cooldown)

    if [[ $cooldown -lt $NOTIFY_COOLDOWN ]]; then
        log "INFO" "跳过通知（冷却中）"
        return 0
    fi

    log "INFO" "发送通知"
    update_notify_time

    "$OPENCLAW_BIN" message send \
        --channel "$NOTIFY_CHANNEL" \
        --target "$NOTIFY_TARGET" \
        --message "$message" \
        --account "$NOTIFY_ACCOUNT" \
        > /dev/null 2>&1 || log "WARN" "通知发送失败"
}

# ============ Clash API 函数 ============
get_current_proxy() {
    curl -s -m 5 -H "Authorization: Bearer $CLASH_SECRET" \
        "$CLASH_API/proxies/GLOBAL" 2>/dev/null | \
        grep -o '"now":"[^"]*"' | cut -d'"' -f4 || echo "UNKNOWN"
}

test_proxy_delay() {
    local proxy_name="$1"
    local encoded_name=$(printf '%s' "$proxy_name" | jq -sRr @uri)
    
    local response=$(curl -s -m 10 \
        -H "Authorization: Bearer $CLASH_SECRET" \
        "$CLASH_API/proxies/$encoded_name/delay?timeout=$DELAY_TIMEOUT&url=$DELAY_TEST_URL" 2>/dev/null)
    
    local delay=$(echo "$response" | grep -o '"delay":[0-9]*' | cut -d':' -f2)
    
    if [[ -n "$delay" && "$delay" -gt 0 ]]; then
        echo "$delay"
    else
        echo "-1"
    fi
}

switch_proxy() {
    local proxy_name="$1"
    curl -s -X PUT -m 5 \
        -H "Authorization: Bearer $CLASH_SECRET" \
        -H "Content-Type: application/json" \
        "$CLASH_API/proxies/GLOBAL" \
        -d "{\"name\":\"$proxy_name\"}" > /dev/null 2>&1
}

get_all_proxies_by_region() {
    local region="$1"
    local pattern=""
    
    case "$region" in
        "TWN") pattern="TWN" ;;
        "JPN") pattern="JPN" ;;
        "HKG") pattern="HKG" ;;
    esac
    
    curl -s -m 5 -H "Authorization: Bearer $CLASH_SECRET" \
        "$CLASH_API/proxies/GLOBAL" 2>/dev/null | \
        jq -r '.all[]' 2>/dev/null | grep "$pattern" | sort -V
}

# ============ 核心逻辑 ============
check_queue_backlog() {
    if [[ ! -d "$QUEUE_DIR" ]]; then
        log "ERROR" "队列目录不存在: $QUEUE_DIR"
        echo "0"
        return 0
    fi
    local count=$(find "$QUEUE_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    log "DEBUG" "积压: $count 条 (阈值: $QUEUE_THRESHOLD)"
    echo "$count"
}

find_healthy_proxy_in_region() {
    local region="$1"
    local proxies=$(get_all_proxies_by_region "$region")
    
    if [[ -z "$proxies" ]]; then
        log "WARN" "$region 地区无节点"
        return 1
    fi
    
    while IFS= read -r proxy; do
        [[ -z "$proxy" ]] && continue
        local delay=$(test_proxy_delay "$proxy")
        if [[ "$delay" -gt 0 && "$delay" -lt "$DELAY_THRESHOLD" ]]; then
            echo "$proxy"
            return 0
        fi
    done <<< "$proxies"
    return 1
}

main() {
    local backlog=$(check_queue_backlog)
    
    if [[ "$backlog" -le "$QUEUE_THRESHOLD" ]]; then
        return 0
    fi
    
    log "WARN" "积压: $backlog 条"
    
    local current_proxy=$(get_current_proxy)
    log "INFO" "当前节点: $current_proxy"
    
    local current_delay=$(test_proxy_delay "$current_proxy")
    log "INFO" "当前延迟: ${current_delay}ms"
    
    if [[ "$current_delay" -gt 0 && "$current_delay" -lt "$DELAY_THRESHOLD" ]]; then
        log "WARN" "节点正常但积压，可能是 Gateway 问题"
        notify_boss "⚠️ Proxy Health 检测异常

积压: $backlog 条
节点: $current_proxy
延迟: ${current_delay}ms

节点正常但消息积压，可能是 Gateway 问题。"
        return 0
    fi
    
    log "WARN" "节点异常，查找健康节点..."
    
    local found_proxy=""
    for region in "${REGIONS[@]}"; do
        log "INFO" "检测 $region..."
        found_proxy=$(find_healthy_proxy_in_region "$region" || echo "")
        
        if [[ -n "$found_proxy" ]]; then
            break
        fi
    done
    
    if [[ -n "$found_proxy" ]]; then
        switch_proxy "$found_proxy"
        log "OK" "已切换: $current_proxy → $found_proxy"
        notify_boss "✅ Proxy Health 自动切换

原节点: $current_proxy
新节点: $found_proxy
积压: $backlog 条"
    else
        log "ERROR" "所有节点不可用，本地网络问题"
    fi
}

main
