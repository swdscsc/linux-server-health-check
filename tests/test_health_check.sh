#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/src/health_check.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$SCRIPT"
help_output=$("$SCRIPT" --help)
grep -q -- '--json' <<<"$help_output"

# Use an unusual hostname to verify JSON quotes and backslashes are escaped.
mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/hostname" <<'MOCK_HOSTNAME'
#!/usr/bin/env bash
printf 'node"slash\\name\n'
MOCK_HOSTNAME
chmod +x "$TMP_DIR/bin/hostname"

set +e
json_output=$(PATH="$TMP_DIR/bin:$PATH" \
  LOG_DIR="$TMP_DIR/logs" \
  WATCH_PROCESSES="__health_check_test_missing_process__" \
  "$SCRIPT" --json)
status=$?
set -e

# An alert is expected because the mock process deliberately does not exist.
[[ "$status" -eq 0 || "$status" -eq 1 ]]

printf '%s\n' "$json_output" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
expected = "node\"slash\\name"
assert data["host"] == expected, (data["host"], expected)
required = {
    "host", "timestamp", "cpu_cores", "cpu_usage", "mem_usage",
    "mem_used_mb", "mem_total_mb", "load1", "tcp_established", "alerts",
}
assert required <= data.keys(), required - data.keys()
for key in ("cpu_cores", "cpu_usage", "mem_usage", "mem_used_mb",
            "mem_total_mb", "load1", "tcp_established", "alerts"):
    assert isinstance(data[key], (int, float)), (key, type(data[key]))
print("health_check.sh smoke tests passed")
'

# With no explicit process list, the script must not assume common services exist.
set +e
default_output=$(CPU_THRESHOLD=100 MEM_THRESHOLD=100 DISK_THRESHOLD=100 \
  INODE_THRESHOLD=100 LOAD_FACTOR=100 WATCH_PROCESSES="" \
  LOG_DIR="$TMP_DIR/default-process-logs" "$SCRIPT")
default_status=$?
set -e
[[ "$default_status" -eq 0 || "$default_status" -eq 1 ]] || {
  printf 'Unexpected default run exit code: %s\n' "$default_status" >&2
  exit 1
}
grep -q '关键进程检查未启用' <<<"$default_output"
! grep -q '未运行或已退出' <<<"$default_output"

# Invalid configuration must fail fast with a clear, non-zero exit.
set +e
invalid_output=$(DISK_THRESHOLD=not-a-number LOG_DIR="$TMP_DIR/invalid-config-logs" "$SCRIPT" 2>&1)
invalid_status=$?
set -e
[[ "$invalid_status" -eq 2 ]] || {
  printf 'Expected invalid threshold exit code 2; got %s\n' "$invalid_status" >&2
  exit 1
}
grep -q 'DISK_THRESHOLD' <<<"$invalid_output"
