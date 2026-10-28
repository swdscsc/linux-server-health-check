# Linux Server Health Check

[![Shell checks](https://github.com/swdscsc/linux-server-health-check/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/swdscsc/linux-server-health-check/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A lightweight Bash-based health check for Linux servers. It reports CPU, memory, disk and inode usage, load average, optional process checks, TCP established connections, and uptime. It supports terminal output, JSON output, daily log files, and exit codes for cron or monitoring integrations.

[简体中文](#简体中文)

## Features

- No Python, Node.js, or third-party package is required at runtime.
- JSON output for integrations, with escaped string fields.
- Configurable thresholds for CPU, memory, disk, inode, and load average.
- Optional process checks: no assumptions about which services are installed.
- Daily log files and exit codes suitable for scheduled jobs.
- GitHub Actions checks for Bash syntax, smoke tests, and ShellCheck.

## Requirements

- Linux with `/proc` mounted.
- Bash, awk, GNU `df`, `pgrep`, and standard command-line utilities.
- Python 3 is needed only to run the JSON smoke test; ShellCheck is used by CI.

The script is intended for Linux environments. It is not a cross-platform Windows or macOS system monitor.

## Quick start

```bash
git clone https://github.com/swdscsc/linux-server-health-check.git
cd linux-server-health-check
chmod +x src/health_check.sh

# Human-readable report
./src/health_check.sh

# JSON to stdout
./src/health_check.sh --json

# Quiet mode for cron (writes logs, no normal terminal report)
./src/health_check.sh --quiet
```

The script writes daily logs under `./logs/` by default. Override the location with `LOG_DIR=/path/to/logs`.

## Configuration

All thresholds can be set with environment variables. Percentage thresholds must be integers from 0 to 100. `LOAD_FACTOR` must be greater than 0 and no more than 100.

| Variable | Default | Meaning |
| --- | ---: | --- |
| `CPU_THRESHOLD` | `80` | CPU usage warning percentage |
| `MEM_THRESHOLD` | `85` | Memory usage warning percentage |
| `DISK_THRESHOLD` | `85` | Disk usage warning percentage |
| `INODE_THRESHOLD` | `90` | Inode usage warning percentage |
| `LOAD_FACTOR` | `2.0` | Load warning threshold = CPU cores × factor |
| `WATCH_PROCESSES` | empty | Optional, whitespace-separated process names to check |
| `LOG_DIR` | `./logs` | Directory for daily log files |
| `JSON_OUT` | empty | Optional path to write the JSON snapshot |

Example: check that the SSH daemon and Nginx are running on a host where those services are expected:

```bash
WATCH_PROCESSES="sshd nginx" ./src/health_check.sh
```

The process list is intentionally opt-in to avoid false alarms on hosts that do not run those services.

To write a JSON snapshot to both stdout (with `--json`) and a file:

```bash
JSON_OUT=/var/tmp/health.json ./src/health_check.sh --json
```

## Exit codes and automation

- Exit code `0`: no threshold alerts were detected.
- Exit code `1`: one or more alerts were detected.
- Exit code `2`: invalid threshold configuration.

Run a daily check at 09:00 and call a notification script when alerts occur:

```cron
0 9 * * * WATCH_PROCESSES="sshd nginx" /opt/linux-server-health-check/src/health_check.sh --quiet || /opt/scripts/send_alert.sh
```

Review the configured process list and paths before enabling this example on a real server.

## Example JSON

Illustrative output (values vary by machine):

```json
{
  "host": "server-1",
  "timestamp": "2026-10-28 09:00:00",
  "cpu_cores": 4,
  "cpu_usage": 12.1,
  "mem_usage": 43.4,
  "mem_used_mb": 2048,
  "mem_total_mb": 4096,
  "load1": 0.36,
  "tcp_established": 12,
  "alerts": 0
}
```

When `--json` is used, the JSON document is printed even when the exit code is `1` because an alert was detected. Automation should check the process exit status as well as parse the output.

## Tests

Run locally:

```bash
bash -n src/health_check.sh tests/test_health_check.sh
bash tests/test_health_check.sh
shellcheck --severity=warning src/health_check.sh tests/test_health_check.sh
```

## Project files

- `src/health_check.sh`: the health-check script.
- `tests/test_health_check.sh`: smoke tests including JSON escaping, default process behavior, and invalid configuration.
- `.github/workflows/ci.yml`: automated checks on pushes and pull requests.
- `CONTRIBUTING.md`: contribution guidelines.
- `SECURITY.md`: vulnerability reporting guidance.
- `CHANGELOG.md`: notable changes.

## Contributing and security

Bug reports and feature requests can be submitted using the GitHub issue templates. Please remove credentials, host-specific sensitive information, and private production logs before posting. For security vulnerabilities, follow `SECURITY.md` rather than posting exploit details in a public issue.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).

---

# 简体中文

一个基于 Bash 的轻量级 Linux 服务器健康巡检脚本，可检查 CPU、内存、磁盘、inode、系统负载、可选进程、TCP 已建立连接数和运行时长，支持终端报告、JSON 输出、每日日志及适合 cron 的退出码。

## 快速开始

```bash
git clone https://github.com/swdscsc/linux-server-health-check.git
cd linux-server-health-check
chmod +x src/health_check.sh

./src/health_check.sh
./src/health_check.sh --json
./src/health_check.sh --quiet
```

运行环境需要 Linux、Bash、awk、GNU `df`、`pgrep` 以及常见命令行工具；运行时不需要 Python、Node.js 或第三方软件包。Python 3 只用于运行 JSON 冒烟测试。

## 配置项

| 变量 | 默认值 | 说明 |
| --- | ---: | --- |
| `CPU_THRESHOLD` | `80` | CPU 使用率告警阈值（整数百分比） |
| `MEM_THRESHOLD` | `85` | 内存使用率告警阈值 |
| `DISK_THRESHOLD` | `85` | 磁盘使用率告警阈值 |
| `INODE_THRESHOLD` | `90` | inode 使用率告警阈值 |
| `LOAD_FACTOR` | `2.0` | 负载阈值 = CPU 核心数 × 系数 |
| `WATCH_PROCESSES` | 空 | 要检查的进程名列表，默认不检查 |
| `LOG_DIR` | `./logs` | 每日日志目录 |
| `JSON_OUT` | 空 | 可选的 JSON 快照输出路径 |

例如，只在明确需要这些服务的服务器上检查 SSH 和 Nginx：

```bash
WATCH_PROCESSES="sshd nginx" ./src/health_check.sh
```

百分比阈值必须为 0–100 的整数；`LOAD_FACTOR` 必须大于 0 且不超过 100。错误配置会返回退出码 `2`。

## 退出码

- `0`：没有触发阈值告警。
- `1`：检测到一个或多个告警。
- `2`：阈值配置无效。

## 测试

```bash
bash -n src/health_check.sh tests/test_health_check.sh
bash tests/test_health_check.sh
shellcheck --severity=warning src/health_check.sh tests/test_health_check.sh
```

欢迎通过仓库中的 Bug 报告和功能建议模板提交可复现的问题。请勿公开令牌、密码或未经脱敏的生产环境信息。安全漏洞请参照 `SECURITY.md` 报告。
