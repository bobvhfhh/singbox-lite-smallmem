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
# Xray 的默认入站策略阻止代理访问私网；仅测试夹具允许本地 HTTP 目标。
must _xray_atomic_modify_json "$XRAY_CONFIG" '(.outbounds[] | select(.tag=="direct") | .settings.finalRules)=[{action:"allow",network:"tcp",port:28080,ip:["127.0.0.1/32"]}]'
expected_listen=::
[[ "${IPV4_ONLY:-0}" == 1 ]] && expected_listen=0.0.0.0
[[ "$(_node_listen_address)" == "$expected_listen" ]] || fail 'wrong listener family'
[[ "$(_get_mem_limit)" == "$(_xray_get_mem_limit)" ]] || fail 'core budgets differ'
echo "budget=$GOMEMLIMIT family=$expected_listen" | tee /results/environment.txt

create_singbox() {
    local operation="$1" port="$2" before after
    before=$(checks sing-box)
    must python3 tests/cgroup-phase.py begin "create-$operation"
    export BATCH_MODE=true BATCH_IP=127.0.0.1 BATCH_SNI=localhost BATCH_PORT="$port"
    must _run_main_create_transaction "$operation"
    after=$(checks sing-box)
    [[ $((after-before)) == 1 ]] || fail "$operation performed $((after-before)) checks"
    must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
    must python3 tests/cgroup-phase.py end "create-$operation"
}
create_singbox _add_vless_reality 21001
create_singbox _add_anytls 21002
create_singbox _add_tuic 21003
must jq -e --arg listen "$expected_listen" '[.inbounds[].type] | sort == ["anytls","tuic","vless"]' "$CONFIG_FILE"
must jq -e --arg listen "$expected_listen" 'all(.inbounds[]; .listen == $listen)' "$CONFIG_FILE"

# Xray 输入与实际向导顺序一致；端口必须来自提供商分配的范围。
BATCH_MODE=false
before=$(checks xray)
must python3 tests/cgroup-phase.py begin create-xray-reality
must _run_xray_transaction _add_vless_reality_vision <<'EOF'
127.0.0.1
22001
localhost
Test-Xray-Reality
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray Reality duplicate checks'
must python3 tests/cgroup-phase.py end create-xray-reality
before=$(checks xray)
must python3 tests/cgroup-phase.py begin create-xray-xhttp
must _run_xray_transaction _add_vless_h2_tls <<'EOF'
127.0.0.1
22002
localhost
/smallmem
Test-Xray-XHTTP
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray XHTTP duplicate checks'
must python3 tests/cgroup-phase.py end create-xray-xhttp
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

# 快照复制失败必须在操作前中止。中断发生在改配置后或停服务后都要恢复。
before_hash=$(sha256sum "$XRAY_CONFIG" | cut -d' ' -f1)
if (
    cp() { return 72; }
    _run_xray_transaction true
); then fail 'partial Xray snapshot accepted'; fi
[[ "$(sha256sum "$XRAY_CONFIG" | cut -d' ' -f1)" == "$before_hash" ]] || fail 'snapshot error changed Xray config'
if (
    interrupted_operation() {
        _xray_atomic_modify_json "$XRAY_CONFIG" '.test_interrupted=true' || return 1
        kill -TERM "$BASHPID"
    }
    _run_xray_transaction interrupted_operation
); then fail 'interrupted operation committed'; fi
[[ "$(sha256sum "$XRAY_CONFIG" | cut -d' ' -f1)" == "$before_hash" ]] || fail 'operation interruption did not restore config'
must _xray_is_pid_file_running_cmd "$XRAY_PID_FILE" "$XRAY_BIN"
if (
    record_transaction_pid() { echo "$BASHPID" > /results/transaction-pid; }
    _validate_xray_config() { kill -TERM "$(cat /results/transaction-pid)"; sleep 1; return 1; }
    _run_xray_transaction record_transaction_pid
); then fail 'interrupted validation committed'; fi
must _xray_is_pid_file_running_cmd "$XRAY_PID_FILE" "$XRAY_BIN"
echo 'PASS: Xray partial snapshots and interrupted transactions restore prior state'

# 删除、改端口与创建共用主快照，失败后不能把原来运行的 sing-box 停掉。
snapshot=$(mktemp -d /tmp/.singbox-shared-rollback.XXXXXX)
must _main_create_tx_snapshot "$snapshot"
[[ -f "$snapshot/service-was-running" ]] || fail 'shared snapshot omitted original service state'
must _main_create_tx_restore "$snapshot" 1
must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
before_hash=$(sha256sum "$XRAY_CONFIG" | cut -d' ' -f1)
if _run_xray_transaction _add_vless_reality_vision </dev/null; then fail 'EOF accepted as Reality input'; fi
if _run_xray_transaction _add_vless_h2_tls </dev/null; then fail 'EOF accepted as XHTTP input'; fi
[[ "$(sha256sum "$XRAY_CONFIG" | cut -d' ' -f1)" == "$before_hash" ]] || fail 'EOF changed config'
echo 'PASS: shared service rollback and EOF input preserve original state'

# 在每个输入点关闭 stdin：必须及时退出并保留配置，尤其不能在端口循环里空转。
before_hash=$(sha256sum "$CONFIG_FILE" | cut -d' ' -f1)
for operation in _add_vless_reality _add_anytls _add_tuic; do
    case "$operation" in
        _add_vless_reality) input=$'127.0.0.1\nlocalhost\n21011\nTest\n' ;;
        _add_anytls) input=$'127.0.0.1\n21012\nlocalhost\npassword\nTest\n1\n' ;;
        _add_tuic) input=$'127.0.0.1\n21013\nlocalhost\nTest\n' ;;
    esac
    count=$(printf '%s' "$input" | wc -l)
    for ((line=0; line<count; line++)); do
        printf '%s' "$input" | head -n "$line" > /results/eof-input
        if _run_main_create_transaction "$operation" < /results/eof-input; then fail "$operation accepted EOF at input $line"; fi
        [[ "$(sha256sum "$CONFIG_FILE" | cut -d' ' -f1)" == "$before_hash" ]] || fail "$operation EOF changed config"
        must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
    done
done
echo 'PASS: all sing-box creation input boundaries exit on EOF without spinning'

# 两个核心同时运行，分别统计空闲 CPU 和 RSS。
python3 tests/resource-sample.py "$(cat "$PID_FILE")" 60 singbox-idle 1 &
sample_sb=$!
python3 tests/resource-sample.py "$(cat "$XRAY_PID_FILE")" 60 xray-idle 1 &
sample_x=$!
must wait "$sample_sb"
must wait "$sample_x"
traffic_result=0
python3 tests/traffic.py || traffic_result=$?
cat /sys/fs/cgroup/memory.events | tee /results/memory.events
cat /sys/fs/cgroup/memory.peak | tee /results/memory.peak
must awk '$1=="oom" || $1=="oom_kill" {if($2 != 0) exit 1}' /sys/fs/cgroup/memory.events
must _manage_service stop
must _manage_xray_service stop
[[ "$traffic_result" == 0 ]] || fail 'protocol traffic test failed'
echo 'PASS: installer, five protocol creators, single checks, rollback, idle sampling, real traffic, no OOM'
