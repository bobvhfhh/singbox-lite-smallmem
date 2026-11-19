#!/usr/bin/env bash
set -Eo pipefail
cd /work || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }
must() { "$@" || fail "$*"; }
checks() { grep -c "^$1 check$" /results/core-events 2>/dev/null || true; }
source <(sed '$d' singbox.sh)
source <(sed '$d' xray_manager.sh)
trap - EXIT INT TERM
INIT_SYSTEM=direct
server_ip=127.0.0.1
export SINGBOXLITE_LOCK_HELD=1 SMALLMEM_STOP_FOR_CHECK=1
must _prepare_singbox_runtime_pid
must bash -n singbox.sh
must bash -n xray_manager.sh
SKIP_SINGBOX_CONFIG_CHECK=1 must _manage_service start
SKIP_XRAY_CORE_PREFLIGHT=1 must _manage_xray_service start
main_snapshot=$(mktemp -d /tmp/.singbox-maintenance.XXXXXX)
must _main_create_tx_snapshot "$main_snapshot"
must _xray_snapshot_state
xray_snapshot=$XRAY_TX_DIR

modify_singbox() {
    local tag="$1" action="$2" value="$3" node meta proxy
    node=$(jq -cS --arg tag "$tag" '.inbounds[]|select(.tag==$tag)' "$CONFIG_FILE") || return 1
    meta=$(jq -cS --arg tag "$tag" '.[$tag] // {}' "$METADATA_FILE") || return 1
    proxy=$(_find_proxy_name "$(printf '%s' "$node" | jq -r .listen_port)" "$(printf '%s' "$node" | jq -r .type)" "$tag")
    _modify_node_apply "$tag" "$node" "$meta" "$proxy" "$action" "$value"
}

before=$(checks sing-box)
old_pid=$(cat "$PID_FILE")
must modify_singbox vless-in-21001 name Renamed-Reality
[[ $(checks sing-box) -eq $before && $(cat "$PID_FILE") == "$old_pid" ]] || fail 'name-only edit restarted or checked core'
must _modify_port vless-in-21001 <<<'21011'
[[ $(checks sing-box) -eq $((before+1)) ]] || fail 'sing-box port edit duplicate checks'
must jq -e '.inbounds[]|select(.tag=="vless-in-21011")|.listen_port==21011' "$CONFIG_FILE"
before_hash=$(sha256sum "$CONFIG_FILE" | cut -d' ' -f1)
if modify_singbox vless-in-21011 auth invalid-uuid; then fail 'invalid UUID committed'; fi
[[ $(sha256sum "$CONFIG_FILE" | cut -d' ' -f1) == "$before_hash" ]] || fail 'sing-box failed auth edit did not restore config'
must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
before=$(checks sing-box)
must _delete_one_main_node_locked anytls-in-21002 anytls 21002 Test-AnyTLS ''
[[ $(checks sing-box) -eq $((before+1)) ]] || fail 'sing-box delete duplicate checks'
must jq -e 'all(.inbounds[]; .type!="anytls")' "$CONFIG_FILE"
before=$(checks sing-box)
must _delete_all_main_nodes_locked
[[ $(checks sing-box) -eq $((before+1)) ]] || fail 'sing-box delete-all duplicate checks'
must jq -e '.inbounds|length==0' "$CONFIG_FILE"
must _main_create_tx_restore "$main_snapshot" 1

before=$(checks xray)
must _modify_xray_port <<'EOF'
1
22011
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray port edit duplicate checks'
must jq -e '.inbounds[]|select(.tag=="xray-vless-reality-22001")|.port==22011' "$XRAY_CONFIG"
before=$(checks xray)
must _delete_xray_node <<'EOF'
1
y
EOF
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray delete duplicate checks'
must jq -e '.inbounds|length==1' "$XRAY_CONFIG"

# 中转入口及其元数据不属于主节点全删范围。
add_protected_relay() {
    _xray_atomic_modify_json "$XRAY_CONFIG" '.inbounds += [($original[0].inbounds[0] | .tag="vless-tcp-in-22999" | .port=22999)]' --slurpfile original "$xray_snapshot/config.json" || return 1
    _xray_atomic_modify_json "$XRAY_METADATA" '.["vless-tcp-in-22999"]={name:"Protected-Relay"}'
}
must _run_xray_transaction add_protected_relay
before=$(checks xray)
must _delete_all_xray_nodes <<<'y'
[[ $(checks xray) -eq $((before+1)) ]] || fail 'Xray delete-all duplicate checks'
must jq -e '.inbounds|length==1 and .[0].tag=="vless-tcp-in-22999"' "$XRAY_CONFIG"
must jq -e 'keys==["vless-tcp-in-22999"]' "$XRAY_METADATA"
must _manage_xray_service stop
must _xray_restore_state "$xray_snapshot"
SKIP_XRAY_CORE_PREFLIGHT=1 must _manage_xray_service start
must _is_pid_file_running_cmd "$PID_FILE" "$SINGBOX_BIN"
must _xray_is_pid_file_running_cmd "$XRAY_PID_FILE" "$XRAY_BIN"
must _manage_service stop
must _manage_xray_service stop
echo 'PASS: port edits, metadata-only edits, deletion, single validation and rollback preserve service state'
