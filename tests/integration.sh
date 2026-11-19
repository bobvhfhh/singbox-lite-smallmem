#!/usr/bin/env bash
set -Eo pipefail
cd /work || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }
must() { "$@" || fail "$*"; }
checks() { grep -c "^$1 check$" /results/core-events 2>/dev/null || true; }

# 仅去掉交互菜单入口，加载仓库原函数并调用真实配置生成/事务/服务实现。
source <(sed '$d' singbox.sh)
source <(sed '$d' xray_manager.sh)
trap 'echo "FAIL: integration interrupted" >&2; exit 1' INT TERM
INIT_SYSTEM=direct
export SINGBOXLITE_LOCK_HELD=1
export SMALLMEM_STOP_FOR_CHECK=1
export GOMEMLIMIT="$(_get_mem_limit)MiB" GOGC=100 GOMAXPROCS=1
server_ip=127.0.0.1
mkdir -p /results "$SINGBOX_DIR" "$XRAY_DIR" "$RUNTIME_DIR"
: > /results/core-events
must bash install.sh --source /work --install-dir /opt/installed --bin /opt/sb --install-only
for file in singbox.sh xray_manager.sh advanced_relay.sh parser.sh; do
    must cmp "/opt/installed/$file" "/work/$file"
    must bash -n "$file"
done
must _initialize_config_files
# 测试固定本地目标，避免把公网 TLS 可达性混入内存和转发测试。
must _atomic_modify_json "$CONFIG_FILE" '.ntp.enabled=false'
must _init_xray_config
expected_listen=::
[[ "${IPV4_ONLY:-0}" == 1 ]] && expected_listen=0.0.0.0
[[ "$(_node_listen_address)" == "$expected_listen" ]] || fail 'wrong listener family'
[[ "$(_get_mem_limit)" == "$(_xray_get_mem_limit)" ]] || fail 'core budgets differ'
echo "budget=$GOMEMLIMIT family=$expected_listen" | tee /results/environment.txt

create_singbox() {
    local operation="$1" port="$2" before after
    before=$(checks sing-box)
    export BATCH_MODE=true BATCH_IP=127.0.0.1 BATCH_SNI=localhost BATCH_PORT="$port"
    must _run_main_create_transaction "$operation"
    after=$(checks sing-box)
    [[ $((after-before)) == 1 ]] || fail "$operation performed $((after-before)) checks"
    must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
}
create_singbox _add_vless_reality 21001
create_singbox _add_anytls 21002
create_singbox _add_tuic 21003
must jq -e --arg listen "$expected_listen" '[.inbounds[].type] | sort == ["anytls","tuic","vless"]' "$CONFIG_FILE"
must jq -e --arg listen "$expected_listen" 'all(.inbounds[]; .listen == $listen)' "$CONFIG_FILE"

# Xray 输入与实际向导顺序一致；端口必须来自提供商分配的范围。
BATCH_MODE=false
before=$(checks xray)
must _run_xray_transaction _add_vless_reality_vision <<'EOF'
127.0.0.1
22001
localhost
Test-Xray-Reality
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray Reality duplicate checks'
before=$(checks xray)
must _run_xray_transaction _add_vless_h2_tls <<'EOF'
127.0.0.1
22002
localhost
/smallmem
Test-Xray-XHTTP
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray XHTTP duplicate checks'
must jq -e --arg listen "$expected_listen" '.inbounds|length==2 and all(.[]; .listen==$listen)' "$XRAY_CONFIG"
must _xray_is_pid_file_running_cmd "$XRAY_PID_FILE" "$XRAY_BIN"

# 失败路径必须恢复所有文件和原来运行的进程。
for core in singbox xray; do
    if [[ "$core" == singbox ]]; then
        file="$CONFIG_FILE"
        pidfile="$PID_FILE"
    else
        file="$XRAY_CONFIG"
        pidfile="$XRAY_PID_FILE"
    fi
    before_hash=$(sha256sum "$file" | cut -d' ' -f1)
    bad_config() { jq '.inbounds += [{"type":"invalid-test-protocol","protocol":"invalid-test-protocol"}]' "$file" > "$file.bad" && mv "$file.bad" "$file"; }
    if [[ "$core" == singbox ]]; then
        if _run_main_create_transaction bad_config; then fail 'invalid sing-box config committed'; fi
    else
        if _run_xray_transaction bad_config; then fail 'invalid Xray config committed'; fi
    fi
    [[ "$(sha256sum "$file" | cut -d' ' -f1)" == "$before_hash" ]] || fail "$core rollback changed config"
    kill -0 "$(cat "$pidfile")" || fail "$core rollback did not restore service"
done

# 两个核心同时运行，分别统计空闲 CPU 和 RSS。
python3 tests/resource-sample.py "$(cat "$PID_FILE")" 12 singbox-idle &
sample_sb=$!
python3 tests/resource-sample.py "$(cat "$XRAY_PID_FILE")" 12 xray-idle &
sample_x=$!
must wait "$sample_sb"
must wait "$sample_x"
must python3 tests/traffic.py
cat /sys/fs/cgroup/memory.events | tee /results/memory.events
cat /sys/fs/cgroup/memory.peak | tee /results/memory.peak
must awk '$1=="oom" || $1=="oom_kill" {if($2 != 0) exit 1}' /sys/fs/cgroup/memory.events
must _manage_service stop
must _manage_xray_service stop
echo 'PASS: installer, five protocol creators, single checks, rollback, idle sampling, real traffic, no OOM'
