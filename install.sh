#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly REPO="bobvhfhh/singbox-lite-smallmem"
branch="main"
install_dir="/usr/local/lib/singbox-lite-smallmem"
bin_path="/usr/local/bin/sb"
readonly FILES=(singbox.sh xray_manager.sh advanced_relay.sh parser.sh install.sh)
readonly RUNTIME_FILES=(singbox.sh xray_manager.sh advanced_relay.sh parser.sh)

info() { printf '[info] %s\n' "$*" >&2; }
error() { printf '[error] %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Usage:
  sudo bash install.sh [--source DIR] [--branch NAME] [--install-dir DIR] [--bin PATH]

Options:
  --source DIR       Install from a local checkout instead of GitHub
  --branch NAME      GitHub branch to install (default: main)
  --install-dir DIR  Script installation directory
  --bin PATH         Launcher path (default: /usr/local/bin/sb)
  -h, --help         Show this help
EOF
}

source_dir=""
temp_source_dir=""
stage_dir=""
installed_files=()
launcher_installed=0
committed=0
install_only=0
cleanup() { [[ -z "${temp_source_dir:-}" ]] || rm -rf -- "$temp_source_dir"; }

finish() {
    local rc=$?
    trap - EXIT
    if [[ "$rc" -ne 0 && "$committed" -ne 1 && -n "$stage_dir" ]]; then
        local index file
        for ((index=${#installed_files[@]}-1; index>=0; index--)); do
            file="${installed_files[index]}"
            if [[ -f "${stage_dir}/backup/${file}" ]]; then
                mv -f -- "${stage_dir}/backup/${file}" "${install_dir}/${file}" || true
            else
                rm -f -- "${install_dir}/${file}"
            fi
        done
        if [[ "$launcher_installed" -eq 1 ]]; then
            if [[ -f "${stage_dir}/backup-launcher" ]]; then
                mv -f -- "${stage_dir}/backup-launcher" "$bin_path" || true
            else
                rm -f -- "$bin_path"
            fi
        fi
    fi
    [[ -z "$stage_dir" ]] || rm -rf -- "$stage_dir"
    cleanup
    exit "$rc"
}

trap finish EXIT
while (($#)); do
    case "$1" in
        --source)
            (($# >= 2)) || { error "--source requires a directory"; exit 2; }
            source_dir="$2"
            shift 2
            ;;
        --branch)
            (($# >= 2)) || { error "--branch requires a name"; exit 2; }
            branch="$2"
            shift 2
            ;;
        --install-dir)
            (($# >= 2)) || { error "--install-dir requires a directory"; exit 2; }
            install_dir="$2"
            shift 2
            ;;
        --bin)
            (($# >= 2)) || { error "--bin requires a path"; exit 2; }
            bin_path="$2"
            shift 2
            ;;
        --install-only)
            install_only=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -n "$source_dir" ]]; then
    source_dir="$(cd -- "$source_dir" && pwd -P)"
    for file in "${FILES[@]}"; do
        [[ -s "${source_dir}/${file}" ]] || { error "missing source file: ${source_dir}/${file}"; exit 1; }
    done
else
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
        error "curl or wget is required for online installation"
        exit 1
    }
    command -v bash >/dev/null 2>&1 || { error "bash is required"; exit 1; }
    command -v mktemp >/dev/null 2>&1 || { error "mktemp is required"; exit 1; }

    source_dir="$(mktemp -d "${TMPDIR:-/tmp}/singbox-lite-smallmem.XXXXXX")"
    temp_source_dir="$source_dir"
    info "downloading ${REPO}@${branch}"
    for file in "${FILES[@]}"; do
        download_url="https://raw.githubusercontent.com/${REPO}/${branch}/${file}"
        if command -v curl >/dev/null 2>&1; then
            curl --fail --location --silent \
                "$download_url" -o "${source_dir}/${file}" 2>/dev/null || rm -f -- "${source_dir}/${file}"
        else
            wget -q "$download_url" -O "${source_dir}/${file}" || rm -f -- "${source_dir}/${file}"
        fi
        if [[ ! -s "${source_dir}/${file}" ]]; then
            if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1 \
                || ! gh api "repos/${REPO}/contents/${file}?ref=${branch}" --jq .content \
                    | tr -d '\n' | base64 -d > "${source_dir}/${file}"; then
                error "download failed for ${file}; verify repository visibility and network access"
                exit 1
            fi
        fi
        [[ -s "${source_dir}/${file}" ]] || { error "downloaded file is empty: ${file}"; exit 1; }
        bash -n "${source_dir}/${file}" || { error "Bash syntax check failed: ${file}"; exit 1; }
    done
    chmod 0755 "$source_dir"
    chmod 0644 "${source_dir}/"*
fi

for file in "${FILES[@]}"; do
    bash -n "${source_dir}/${file}" || { error "Bash syntax check failed: ${file}"; exit 1; }
done

if [[ "${EUID}" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { error "sudo is required to install into ${install_dir}"; exit 1; }
    sudo bash "${source_dir}/install.sh" --source "$source_dir" --install-dir "$install_dir" --bin "$bin_path" --install-only
    install_rc=$?
    [[ "$install_rc" -eq 0 ]] || exit "$install_rc"
    exec sudo "$bin_path"
fi

install -d -m 0755 "$install_dir" "$(dirname -- "$bin_path")"
stage_dir="$(mktemp -d "${install_dir}/.install.XXXXXX")"
mkdir -m 0700 "${stage_dir}/new" "${stage_dir}/backup"

for file in "${RUNTIME_FILES[@]}"; do
    install -m 0755 "${source_dir}/${file}" "${stage_dir}/new/${file}"
    if [[ -e "${install_dir}/${file}" ]]; then
        cp -p -- "${install_dir}/${file}" "${stage_dir}/backup/${file}"
    fi
done

for file in "${RUNTIME_FILES[@]}"; do
    installed_files+=("$file")
    mv -f -- "${stage_dir}/new/${file}" "${install_dir}/${file}"
done

if [[ -e "$bin_path" ]]; then
    cp -p -- "$bin_path" "${stage_dir}/backup-launcher"
fi
launcher_installed=1
printf -v quoted_install_dir '%q' "$install_dir"
launcher_tmp="${stage_dir}/new/launcher"
cat > "$launcher_tmp" <<EOF
#!/usr/bin/env bash
exec bash ${quoted_install_dir}/singbox.sh "\$@"
EOF
chmod 0755 "$launcher_tmp"
mv -f -- "$launcher_tmp" "$bin_path"
committed=1

info "installed scripts to ${install_dir}"
info "launcher: ${bin_path}"
rm -rf -- "$stage_dir"
stage_dir=""
if [[ "$install_only" -eq 1 ]]; then
    exit 0
fi
exec "$bin_path"
