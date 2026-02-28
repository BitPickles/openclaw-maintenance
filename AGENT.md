# Agent Quickstart (60s)

> **复制给你的 Agent 的提示词（Prompt）**：
> ```
> 你需要在目标机器部署 OpenClaw 维护脚本。请在仓库根目录执行：
> 1) 复制环境变量示例：cp .env.example .env
> 2) 填写 .env（至少设置 OPENCLAW_NOTIFY_TARGET、CLASH_API/CLASH_SECRET 如需）
> 3) 运行安装脚本：bash install.sh
> 4) 运行自检：bash check.sh
> 如果是 macOS 用 LaunchAgent；Linux 用 systemd。脚本放在 ~/.openclaw/scripts。
> ```

---

## Minimal Steps

```bash
cp .env.example .env
# 编辑 .env
bash install.sh
bash check.sh
```

## What gets installed

- `gateway-watchdog.sh`
- `proxy-health.sh` (optional, if Clash configured)
- `cleanup-logs.sh`

## REQUIREMENTS

- `openclaw` CLI
- `curl`
- `jq`
- (optional) Clash / Mihomo API

