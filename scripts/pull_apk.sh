#!/usr/bin/env bash
# pull_apk.sh - Extract APKs from connected Android device via ADB
# Usage: pull_apk.sh [--list | --all | --pkg <package>] [--output <dir>]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

OUTPUT_DIR=""
TARGET_PKG=""
MODE=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modes:
  --list              List installed packages on device
  --all               Pull ALL installed APKs
  --pkg <package>     Pull specific package APK
  --path <apk_path>   Pull a specific APK file from device
  --split <package>   Pull split APKs (app bundles)

Options:
  -o, --output <dir>  Output directory (default: output/<package>/)
  -h, --help          Show this help

Examples:
  $(basename "$0") --list
  $(basename "$0") --pkg com.example.app
  $(basename "$0") --all -o ./apks/
  $(basename "$0") --split com.example.app
EOF
    exit 0
}

check_adb() {
    if [ -z "$ADB" ]; then
        echo "[-] adb not found. Install: sudo apt install adb"
        exit 1
    fi
    if ! $ADB get-state >/dev/null 2>&1; then
        echo "[-] No device connected. Check USB debugging."
        exit 1
    fi
    echo "[+] Device: $($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
}

list_packages() {
    echo "[+] Installed packages:"
    $ADB shell pm list packages -f 2>/dev/null | tr -d '\r' | sort
}

pull_single_apk() {
    local pkg="$1"
    local out_dir="${2:-${OUTPUT_BASE}/${pkg}}"

    mkdir -p "$out_dir"

    local apk_path
    apk_path=$($ADB shell pm path "$pkg" 2>/dev/null | head -1 | sed 's/package://' | tr -d '\r')

    if [ -z "$apk_path" ]; then
        echo "[-] Package not found: $pkg"
        return 1
    fi

    local apk_name
    apk_name=$(basename "$apk_path")
    echo "[+] Pulling: $pkg -> $apk_name"
    $ADB pull "$apk_path" "${out_dir}/${apk_name}" 2>&1 | tail -1
    echo "[+] Saved to: ${out_dir}/${apk_name}"
}

pull_split_apks() {
    local pkg="$1"
    local out_dir="${2:-${OUTPUT_BASE}/${pkg}_split}"
    mkdir -p "$out_dir"

    echo "[+] Split APKs for: $pkg"
    local paths
    paths=$($ADB shell pm path "$pkg" 2>/dev/null | sed 's/package://' | tr -d '\r')

    local count=0
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        local name
        name=$(basename "$path")
        echo "  -> $name"
        $ADB pull "$path" "${out_dir}/${name}" 2>&1 | tail -1
        ((++count)) || true
    done <<< "$paths"

    echo "[+] Pulled $count APK(s) to: $out_dir"
}

pull_all_apks() {
    local out_dir="${1:-${OUTPUT_BASE}/all_apks}"
    mkdir -p "$out_dir"

    echo "[+] Pulling ALL installed APKs..."
    local packages
    packages=$($ADB shell pm list packages -3 2>/dev/null | sed 's/package://' | tr -d '\r')

    local count=0
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        pull_single_apk "$pkg" "$out_dir/$pkg"
        ((++count)) || true
    done <<< "$packages"

    echo "[+] Done. Pulled $count APK(s) to: $out_dir"
}

pull_file_from_device() {
    local remote_path="$1"
    local out_dir="${2:-${OUTPUT_BASE}/pulled}"
    mkdir -p "$out_dir"

    local name
    name=$(basename "$remote_path")
    echo "[+] Pulling file: $remote_path"
    $ADB pull "$remote_path" "${out_dir}/${name}" 2>&1 | tail -1
    echo "[+] Saved to: ${out_dir}/${name}"
}

# ── Parse args ──────────────────────────────────────────
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --list)    MODE="list"; shift ;;
        --all)     MODE="all"; shift ;;
        --pkg)     MODE="pkg"; TARGET_PKG="$2"; shift 2 ;;
        --split)   MODE="split"; TARGET_PKG="$2"; shift 2 ;;
        --path)    MODE="path"; shift 2; pull_file_from_device "$1" "${OUTPUT_DIR:-}"; exit $? ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

check_adb

case "$MODE" in
    list)   list_packages ;;
    all)    pull_all_apks "$OUTPUT_DIR" ;;
    pkg)    pull_single_apk "$TARGET_PKG" "$OUTPUT_DIR" ;;
    split)  pull_split_apks "$TARGET_PKG" "$OUTPUT_DIR" ;;
    *)      usage ;;
esac
