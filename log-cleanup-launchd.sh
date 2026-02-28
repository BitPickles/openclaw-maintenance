#!/bin/bash
# 每天运行一次的日志清理任务

~/.openclaw/scripts/cleanup-logs.sh >> ~/.openclaw/logs/cleanup.log 2>&1
