#!/usr/bin/env bash
set -Eo pipefail
cd /work || exit 1
source <(sed '$d' singbox.sh)
source <(sed '$d' xray_manager.sh)
trap - EXIT INT TERM
export SKIP_SINGBOX_CONFIG_CHECK=1 SKIP_XRAY_CORE_PREFLIGHT=1
sleep() { :; }
systemctl() {
    case "$1" in
        start|restart|reset-failed) return 0 ;;
        is-active) return 1 ;;
        *) return 0 ;;
    esac
}
rc-service() {
    [[ "$2" != status ]]
}
for INIT_SYSTEM in systemd openrc; do
    if _manage_service start; then echo "FAIL: sing-box $INIT_SYSTEM early exit reported success"; exit 1; fi
    if _manage_xray_service start; then echo "FAIL: Xray $INIT_SYSTEM early exit reported success"; exit 1; fi
done
echo 'PASS: systemd/OpenRC start commands returning success do not hide an exited core'
