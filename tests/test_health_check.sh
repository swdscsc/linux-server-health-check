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
