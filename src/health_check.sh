#!/usr/bin/env bash
# ==============================================================================
# 服务器健康巡检脚本
#
# 采集：CPU / 内存 / 磁盘 /  inode / 负载 / 关键进程 / TCP 连接数 / 运行时长
# 输出：控制台彩色报告 + JSON 快照 + 按天滚动的日志文件
# 退出码：0=全部正常  1=存在告警（可直接用于 cron + 告警联动判断）
#
# 用法：
#   ./health_check.sh                 # 巡检并打印报告
#   ./health_check.sh --json          # 只输出 JSON（方便被其他程序消费）
#   ./health_check.sh --quiet         # 不打印，只写日志（cron 场景）
#
# 定时任务（每天 9 点）：
#   0 9 * * * /opt/scripts/health_check.sh --quiet
# ==============================================================================
set -uo pipefail

# ------------------------------- 配置区 --------------------------------------
CPU_THRESHOLD=${CPU_THRESHOLD:-80}      # CPU 使用率告警阈值(%)
MEM_THRESHOLD=${MEM_THRESHOLD:-85}      # 内存使用率告警阈值(%)
DISK_THRESHOLD=${DISK_THRESHOLD:-85}    # 磁盘使用率告警阈值(%)
INODE_THRESHOLD=${INODE_THRESHOLD:-90}  # inode 使用率告警阈值(%)
LOAD_FACTOR=${LOAD_FACTOR:-2.0}         # 负载告警 = CPU核数 × 该系数
WATCH_PROCESSES=${WATCH_PROCESSES:-"sshd nginx mysqld docker"}  # 需存活的关键进程
LOG_DIR=${LOG_DIR:-"./logs"}
JSON_OUT=${JSON_OUT:-""}
QUIET=0
JSON_ONLY=0

# ------------------------------- 参数解析 ------------------------------------
for arg in "$@"; do
  case "$arg" in
    --json)  JSON_ONLY=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  esac
done

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/health_$(date +%F).log"

# ------------------------------- 工具函数 ------------------------------------
ALERT_COUNT=0

log() {                       # 写日志（带时间戳）
  printf '[%s] %s\n' "$(date '+%F %T')" "$1" >>"$LOG_FILE"
}
say() {                       # 写日志 + 按开关打印
  log "$1"
  [[ "$QUIET" -eq 0 && "$JSON_ONLY" -eq 0 ]] && printf '%s\n' "$1"
}
alert() {                     # 告警：黄色 WARN 前缀 + 计数
  ALERT_COUNT=$((ALERT_COUNT + 1))
  log "[WARN] $1"
  [[ "$QUIET" -eq 0 && "$JSON_ONLY" -eq 0 ]] && printf '\033[33m[WARN]\033[0m %s\n' "$1"
}
ok() {
  log "[OK] $1"
  [[ "$QUIET" -eq 0 && "$JSON_ONLY" -eq 0 ]] && printf '\033[32m[OK]\033[0m   %s\n' "$1"
}

# 读 /proc/stat 采样一次 CPU 总时间片
cpu_snapshot() {
  awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat
}

# ------------------------------- 采集开始 ------------------------------------
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%F %T')
CPU_CORES=$(nproc)

say "===== 服务器健康巡检  $HOSTNAME  $TIMESTAMP ====="

# --- CPU：两次采样求差，比 top -bn1 更准（top 取的是开机以来的平均值）---
read -r TOTAL1 IDLE1 < <(cpu_snapshot)
sleep 1
read -r TOTAL2 IDLE2 < <(cpu_snapshot)
TOTAL_DIFF=$((TOTAL2 - TOTAL1))
IDLE_DIFF=$((IDLE2 - IDLE1))
if [[ "$TOTAL_DIFF" -gt 0 ]]; then
  CPU_USE=$(awk -v t="$TOTAL_DIFF" -v i="$IDLE_DIFF" 'BEGIN{printf "%.1f", (t-i)/t*100}')
else
  CPU_USE="0.0"
fi
if awk -v c="$CPU_USE" -v th="$CPU_THRESHOLD" 'BEGIN{exit !(c>th)}'; then
  alert "CPU 使用率 ${CPU_USE}% 超过阈值 ${CPU_THRESHOLD}%"
else
  ok "CPU 使用率 ${CPU_USE}%（阈值 ${CPU_THRESHOLD}%）"
fi

# --- 内存 ---
# MemAvailable 在 3.14 之前的内核里不存在，缺失时用 MemFree+Buffers+Cached 估算
read -r MEM_TOTAL MEM_AVAIL < <(awk '
  /^MemTotal:/      {t=$2}
  /^MemAvailable:/  {a=$2}
  /^MemFree:/       {f=$2}
  /^Buffers:/       {b=$2}
  /^Cached:/        {c=$2}
  END{if(a=="") a=f+b+c; print t, a}' /proc/meminfo)
MEM_USE=$(awk -v t="$MEM_TOTAL" -v a="$MEM_AVAIL" 'BEGIN{printf "%.1f", (t-a)/t*100}')
MEM_USED_MB=$(( (MEM_TOTAL - MEM_AVAIL) / 1024 ))
MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
if awk -v m="$MEM_USE" -v th="$MEM_THRESHOLD" 'BEGIN{exit !(m>th)}'; then
  alert "内存使用率 ${MEM_USE}%（${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB）超过阈值 ${MEM_THRESHOLD}%"
else
  ok "内存使用率 ${MEM_USE}%（${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB）"
fi

# --- 磁盘空间（跳过 tmpfs / devtmpfs 等内存文件系统）---
DISK_ALERT=0
while read -r FS SIZE USED PCT MOUNT; do
  [[ "$FS" == tmpfs* || "$FS" == devtmpfs || "$FS" == overlay ]] && continue
  NUM=${PCT%\%}
  [[ "$NUM" =~ ^[0-9]+$ ]] || continue   # 部分文件系统不报告百分比（显示为 -），跳过
  [[ "$SIZE" =~ ^[0-9]+$ && "$SIZE" -lt 1048576 ]] && continue   # 小于 1MB 的系统分区忽略
  if [[ "$NUM" -ge "$DISK_THRESHOLD" ]]; then
    alert "磁盘 ${MOUNT} 已用 ${PCT}（阈值 ${DISK_THRESHOLD}%）"
    DISK_ALERT=1
  else
    ok "磁盘 ${MOUNT} 已用 ${PCT}"
  fi
done < <(df -P -B1 | awk 'NR>1{print $1, $2, $3, $5, $6}')
[[ "$DISK_ALERT" -eq 0 ]] || :

# --- inode 使用率（磁盘满了但 df 看不出来，往往是 inode 耗尽）---
INODE_MAX=0
while read -r PCT MOUNT; do
  NUM=${PCT%\%}
  [[ "$NUM" =~ ^[0-9]+$ ]] || continue   # 某些文件系统（如 Windows 挂载盘）不提供 inode 信息，显示为 -
  [[ "$NUM" -gt "$INODE_MAX" ]] && INODE_MAX=$NUM
  if [[ "$NUM" -ge "$INODE_THRESHOLD" ]]; then
    alert "inode ${MOUNT} 已用 ${PCT}（阈值 ${INODE_THRESHOLD}%）"
  fi
done < <(df -Pi | awk 'NR>1{print $5, $6}')
if [[ "$INODE_MAX" -eq 0 ]]; then
  ok "inode 使用率：当前环境不支持统计，已跳过"
else
  ok "inode 最高使用率 ${INODE_MAX}%（阈值 ${INODE_THRESHOLD}%）"
fi

# --- 系统负载 ---
LOAD1=$(awk '{print $1}' /proc/loadavg)
LOAD_THRESHOLD=$(awk -v c="$CPU_CORES" -v f="$LOAD_FACTOR" 'BEGIN{printf "%.2f", c*f}')
if awk -v l="$LOAD1" -v th="$LOAD_THRESHOLD" 'BEGIN{exit !(l>th)}'; then
  alert "1 分钟负载 ${LOAD1} 超过阈值 ${LOAD_THRESHOLD}（${CPU_CORES} 核 × ${LOAD_FACTOR}）"
else
  ok "1 分钟负载 ${LOAD1}（阈值 ${LOAD_THRESHOLD}，${CPU_CORES} 核）"
fi

# --- 关键进程存活 ---
for proc in $WATCH_PROCESSES; do
  if pgrep -x "$proc" >/dev/null 2>&1; then
    ok "进程 ${proc} 运行正常"
  else
    alert "进程 ${proc} 未运行或已退出"
  fi
done

# --- TCP 连接数（ESTABLISHED）---
TCP_EST=$(awk '$4=="01"{n++} END{print n+0}' /proc/net/tcp 2>/dev/null || echo 0)
ok "TCP ESTABLISHED 连接数 ${TCP_EST}"

# --- 运行时长 ---
UPTIME_INFO=$(awk '{d=int($1/86400); h=int($1%86400/3600); printf "%d 天 %d 小时", d, h}' /proc/uptime)
ok "已运行 ${UPTIME_INFO}"

say "===== 巡检结束：共 ${ALERT_COUNT} 条告警 ====="

# ------------------------------- JSON 输出 -----------------------------------
# 手写 JSON（运维机上不一定装 jq，避免依赖）
json=$(cat <<EOF
{
  "host": "$HOSTNAME",
  "timestamp": "$TIMESTAMP",
  "cpu_cores": $CPU_CORES,
  "cpu_usage": $CPU_USE,
  "mem_usage": $MEM_USE,
  "mem_used_mb": $MEM_USED_MB,
  "mem_total_mb": $MEM_TOTAL_MB,
  "load1": $LOAD1,
  "tcp_established": $TCP_EST,
  "alerts": $ALERT_COUNT
}
EOF
)
if [[ -n "$JSON_OUT" ]]; then
  printf '%s\n' "$json" >"$JSON_OUT"
fi
if [[ "$JSON_ONLY" -eq 1 ]]; then
  printf '%s\n' "$json"
fi

# 有告警时以退出码 1 结束，方便 cron 后面接告警动作：
#   ./health_check.sh --quiet || ./send_alert.sh
exit $((ALERT_COUNT > 0 ? 1 : 0))
