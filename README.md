# linux-server-health-check · 服务器健康巡检脚本

> 纯 Shell 实现的服务器巡检工具：采集 CPU / 内存 / 磁盘 / inode / 负载 / 关键进程 / TCP 连接，
> 超阈值告警，输出彩色报告 + JSON 快照 + 按天滚动日志，并以退出码区分是否异常。

## 为什么做这个

运维最基础也最容易被忽略的一件事：**在故障发生前发现问题**。
磁盘满了、进程悄悄退了、内存慢慢涨上去——这些都是可以提前发现的，但没人会每天手动敲一遍 `df -h`。

这个脚本的定位是「**最小可用的巡检**」：不装 agent、不依赖任何第三方包，
一台新机器 `scp` 过去就能跑，配一条 crontab 就实现了每日自动巡检。

## 快速开始

```bash
chmod +x src/health_check.sh
./src/health_check.sh                  # 巡检并打印彩色报告
./src/health_check.sh --json           # 只输出 JSON（供监控程序消费）
./src/health_check.sh --quiet          # 静默模式，只写日志（cron 场景）
```

配进 crontab，每天 9 点自动跑：

```bash
0 9 * * * /opt/scripts/health_check.sh --quiet
```

想让告警自动推送，利用退出码串起来即可：

```bash
0 9 * * * /opt/scripts/health_check.sh --quiet || /opt/scripts/send_alert.sh
```

## 实测输出

```
===== 服务器健康巡检  LAPTOP-IBBOA0BK  2026-10-08 01:01:07 =====
[OK]   CPU 使用率 9.4%（阈值 80%）
[WARN] 内存使用率 93.3%（14982MB / 16065MB）超过阈值 85%
[WARN] 磁盘 /c 已用 98%（阈值 85%）
[OK]   磁盘 / 已用 57%
[OK]   磁盘 /e 已用 66%
[OK]   1 分钟负载 0.92（阈值 16.00，8 核）
[WARN] 进程 mysqld 未运行或已退出
[OK]   TCP ESTABLISHED 连接数 0
[OK]   已运行 3 天 8 小时
===== 巡检结束：共 6 条告警 =====
```

## 采集项与阈值

| 项目 | 数据来源 | 默认阈值 | 可覆盖环境变量 |
| --- | --- | --- | --- |
| CPU 使用率 | `/proc/stat` 两次采样求差 | 80% | `CPU_THRESHOLD` |
| 内存使用率 | `/proc/meminfo` | 85% | `MEM_THRESHOLD` |
| 磁盘空间 | `df -P -B1` | 85% | `DISK_THRESHOLD` |
| inode 使用率 | `df -Pi` | 90% | `INODE_THRESHOLD` |
| 系统负载 | `/proc/loadavg` | 核数 × 2.0 | `LOAD_FACTOR` |
| 关键进程存活 | `pgrep -x` | — | `WATCH_PROCESSES` |
| TCP 连接数 | `/proc/net/tcp` | — | — |
| 运行时长 | `/proc/uptime` | — | — |

## 设计取舍（面试能讲的点）

**① CPU 为什么不用 `top -bn1`？**
`top` 首屏显示的是**开机以来的平均**使用率，不是当前瞬时值，用它做告警会严重滞后。
本脚本读 `/proc/stat`，间隔 1 秒采样两次求差值：

```
CPU使用率 = (总时间片增量 - 空闲时间片增量) / 总时间片增量 × 100%
```

**② 为什么要看 inode？**
`df -h` 显示磁盘还剩 30%，但写文件报 "No space left on device"——这是经典故障，
原因是**小文件太多把 inode 耗尽了**。空间够但 inode 不够，一样写不进去。
只监控磁盘空间会漏掉这类问题。

**③ 为什么关键进程用 `pgrep -x`？**
`-x` 是精确匹配进程名。不加 `-x` 的话，`pgrep mysql` 会把 `mysqld_safe`、`mysql-backup.sh` 都匹配上，产生误判。

**④ 为什么不依赖 `jq`？**
JSON 是手写字符串拼的。运维机器上不一定装 `jq`，脚本要能在最小化安装的机器上跑，所以避免一切非必要依赖。

**⑤ 为什么要设退出码？**
`exit 1` 表示有告警。这样 cron 里可以直接 `||` 接告警动作，也能被监控系统（Zabbix/Prometheus 的 pushgateway）直接采集，脚本因此能融入更大的监控体系而不是孤岛。

## 已知的环境适配

脚本在不同环境实测时修掉过两个真实 bug，代码里都做了防御：

- 某些文件系统（如 Windows 挂载盘、NFS）不提供 inode 信息，`df -Pi` 输出 `-`，
  直接做数值比较会报 `arithmetic syntax error` → 已加 `[[ "$NUM" =~ ^[0-9]+$ ]] || continue` 跳过。
- Linux 3.14 之前的内核没有 `MemAvailable` 字段 → 已加回退：`MemFree + Buffers + Cached`。

## 目录结构

```
linux-server-health-check/
├── src/health_check.sh     # 主脚本
├── docs/讲解文档.md         # 设计思路、代码走读、面试问答
└── logs/                   # 按天滚动的巡检日志（health_YYYY-MM-DD.log）
```

## 后续可做

- [ ] 告警推送：接入企业微信 / 钉钉 webhook
- [ ] 历史趋势：把每次 JSON 快照落库，画 7 天内存曲线
- [ ] 进程内存 TOP N：找出具体是哪个进程在吃内存
