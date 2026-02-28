#!/bin/bash
#
# OpenClaw Safe Restart
# 带锁机制的重启，不会触发 watchdog 告警
#
# 用法: openclaw-safe-restart.sh [start|stop|restart]
#

LOCK_FILE="/tmp/openclaw-restart.lock"

create_lock() {
    touch "$LOCK_FILE"
    echo "Lock created: $LOCK_FILE"
}

remove_lock() {
    rm -f "$LOCK_FILE"
    echo "Lock removed: $LOCK_FILE"
}

case "${1:-restart}" in
    start)
        create_lock
        /opt/homebrew/bin/openclaw gateway start
        sleep 3
        remove_lock
        ;;
    stop)
        create_lock
        /opt/homebrew/bin/openclaw gateway stop
        # 停止时保留锁文件，手动启动时再删除
        echo "Note: Lock file retained. Remove with: rm $LOCK_FILE"
        ;;
    restart)
        create_lock
        /opt/homebrew/bin/openclaw gateway restart
        sleep 3
        remove_lock
        ;;
    *)
        echo "Usage: $0 [start|stop|restart]"
        exit 1
        ;;
esac
