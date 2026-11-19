#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for file in install.sh singbox.sh xray_manager.sh advanced_relay.sh parser.sh tests/*.sh; do
    bash -n "$file"
done
_get_mem_limit() { echo 40; }
pattern="GOMEMLIMIT=\"?$(_get_mem_limit)MiB"
for line in 'Environment="GOMEMLIMIT=40MiB"' 'export GOMEMLIMIT="40MiB"'; do
    echo "$line" | grep -Eq "$pattern"
done
if echo 'export GOMEMLIMIT="64MiB"' | grep -Eq "$pattern"; then
    echo 'FAIL: resource service migration accepts stale memory budget' >&2
    exit 1
fi
echo 'PASS: shell syntax and systemd/OpenRC resource-setting detection'
