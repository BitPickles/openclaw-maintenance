# OpenClaw 维护脚本合集

用于保障 OpenClaw 稳定运行的本地维护脚本（监控、重启、日志清理、网络代理健康检查）。

## 目录结构

```
~/.openclaw/scripts/
├── README.md                      # 总说明（本文件）
├── README-proxy-health.md         # Proxy Health 详细说明
├── gateway-watchdog.sh            # Gateway 进程看护
├── proxy-health.sh                # 代理/网络健康监控
├── openclaw-safe-restart.sh       # 安全重启
├── cleanup-logs.sh                # 日志清理
└── log-cleanup-launchd.sh         # macOS LaunchAgent 启动日志清理
```

---

## 脚本功能一览

| 脚本 | 作用 | 典型场景 |
|------|------|----------|
| `gateway-watchdog.sh` | 检测 Gateway `/healthz`，异常时自动重启 | Gateway 崩溃或假死 |
| `proxy-health.sh` | 监控消息队列积压，切换 VPN/代理节点 | 网络不通导致消息积压 |
| `openclaw-safe-restart.sh` | 优雅重启 Gateway（避免误判） | 手动运维 | 
| `cleanup-logs.sh` | 清理 `.openclaw/logs` 日志 | 日志膨胀 |
| `log-cleanup-launchd.sh` | macOS 定期运行日志清理 | 定时维护 |

---

# 适配说明（不同设备 / 系统）

## ✅ macOS（推荐）
脚本默认适配 macOS，可直接使用 **LaunchAgent** 定时/常驻运行。

### 1. 安装 LaunchAgent
将对应 `.plist` 放入：
```
~/Library/LaunchAgents/
```

启动：
```bash
launchctl load ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.proxy-health.plist
```

查看状态：
```bash
launchctl list | grep openclaw
```

停止：
```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.watchdog.plist
launchctl unload ~/Library/LaunchAgents/ai.openclaw.proxy-health.plist
```

> 注意：plist 文件不在本目录，需要单独维护（可按需创建）。

---

## ✅ Linux（Ubuntu/Debian/CentOS）
建议用 **systemd** 或 **cron** 运行。

### A. systemd（推荐）
示例：`/etc/systemd/system/openclaw-watchdog.service`
```
[Unit]
Description=OpenClaw Gateway Watchdog
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /home/<user>/.openclaw/scripts/gateway-watchdog.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

启动：
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-watchdog
```

### B. cron（简易）
```
* * * * * /bin/bash /home/<user>/.openclaw/scripts/proxy-health.sh
0 */6 * * * /bin/bash /home/<user>/.openclaw/scripts/cleanup-logs.sh
```

---

## ✅ 群晖 / NAS
使用系统自带 **任务计划（Task Scheduler）**：

1. 新建「用户定义脚本」任务
2. 设定每分钟/每天执行
3. 脚本路径填写：
```
/bin/bash /volume1/homes/<user>/.openclaw/scripts/proxy-health.sh
```

---

# 依赖说明（不同软件）

| 功能 | 依赖 | 说明 |
|------|------|------|
| OpenClaw CLI | `openclaw` | 发送通知/重启 Gateway |
| 网络检测 | `curl` | 检测 Gateway 健康 |
| JSON 解析 | `jq` | Proxy Health 解析 Clash API |
| 代理节点切换 | Clash / Mihomo | `proxy-health.sh` 依赖 Clash API |

---

# 配置要点

## 1. `gateway-watchdog.sh`
- `HEALTH_URL`：Gateway 健康检查地址
- `OPENCLAW_BIN`：OpenClaw CLI 路径
- `NOTIFY_TARGET`：通知对象（Boss Telegram ID）

## 2. `proxy-health.sh`
- `CLASH_API`：Clash API 地址
- `CLASH_SECRET`：API 密钥
- `REGIONS`：节点优先级
- `QUEUE_THRESHOLD`：积压阈值

---

# 推荐部署流程（新设备）

1. **安装 OpenClaw**
2. **复制脚本目录**
   ```bash
   scp -r ~/.openclaw/scripts user@new-host:~/.openclaw/
   ```
3. **安装依赖**
   ```bash
   # macOS
   brew install jq curl

   # Linux
   sudo apt install -y jq curl
   ```
4. **配置 Clash（如需）**
5. **创建 systemd/LaunchAgent 定时任务**

---

# 常用命令

```bash
# 手动运行 watchdog
~/.openclaw/scripts/gateway-watchdog.sh

# 手动运行 proxy health
~/.openclaw/scripts/proxy-health.sh

# 清理日志
~/.openclaw/scripts/cleanup-logs.sh
```

---

# 注意事项

- `proxy-health.sh` 不依赖 Gateway，可独立部署
- `gateway-watchdog.sh` 依赖 `openclaw` CLI
- Clash API 密钥需要在脚本中配置
- 多设备部署时，请分别设置通知目标和账号
