#!/usr/bin/env bash
# apk-pipeline.sh - Main orchestrator for APK reverse engineering
# Usage: apk-pipeline.sh <command> [options]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Cache configuration
CACHE_DIR="$WORKSPACE/.cache"
HASH_FILE="$CACHE_DIR/apk_hashes.txt"

init_cache() {
    mkdir -p "$CACHE_DIR"
    touch "$HASH_FILE"
}

get_apk_hash() {
    local apk_path="$1"
    if [ -f "$apk_path" ]; then
        sha256sum "$apk_path" | awk '{print $1}'
    else
        echo ""
    fi
}

is_cache_valid() {
    local apk_path="$1"
    local output_dir="$2"
    local current_hash=$(get_apk_hash "$apk_path")
    
    if [ -z "$current_hash" ]; then
        return 1
    fi

    if [ ! -f "$HASH_FILE" ]; then
        return 1
    fi

    local stored_hash=$(grep "^$apk_path|" "$HASH_FILE" 2>/dev/null | cut -d'|' -f2)
    
    if [ "$current_hash" = "$stored_hash" ] && [ -d "$output_dir" ] && [ -f "$output_dir/report.txt" ]; then
        return 0
    fi
    
    return 1
}

update_cache() {
    local apk_path="$1"
    local hash=$(get_apk_hash "$apk_path")
    
    # Remove old entry if exists
    if grep -q "^$apk_path|" "$HASH_FILE" 2>/dev/null; then
        sed -i "/^$apk_path|/d" "$HASH_FILE"
    fi
    
    # Add new entry
    echo "$apk_path|$hash" >> "$HASH_FILE"
}

clean_cache() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR"
        echo "Cache cleared."
    fi
}

# Initialize cache on startup
init_cache

VERSION="1.0.0"

banner() {
    cat <<EOF

  ${CYAN}███████╗ ██████╗  ██████╗ ███████╗ ███╗   ███╗${NC}
  ${CYAN}██╔════╝██╔═══██╗██╔═══██╗██╔════╝ ╚██╗ ██╔╝${NC}
  ${CYAN}███████╗██║   ██║██║   ██║███████╗  ╚████╔╝${NC}
  ${CYAN}╚════██║██║   ██║██║   ██║╚════██║   ╚██╔╝${NC}
  ${CYAN}██╔═══██║██║   ██║██║   ██║██╔═══██║    ██║${NC}
  ${CYAN}╚═╝  ╚═╝╚═╝   ╚═╝╚═╝   ╚═╝╚═╝  ╚═╝    ╚═╝${NC}

  ${BOLD}APK Reverse Engineering Pipeline v${VERSION}${NC}
  ${DIM}jadx + apktool + apk2url + frida + yara + r2${NC}
EOF
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  tui         Launch interactive TUI (fzf-based)
  pull        Pull APK(s) from connected device
  decompile   Decompile APK with all engines (jadx + apktool)
  analyze     Run deep static analysis (secrets + permissions + strings)
  report      Generate markdown/HTML report
  quick       Quick scan: URLs + secrets only (decompile + grep)
  full        Run full pipeline (decompile + analyze + report)
  batch       Process multiple APKs in parallel
  check       Check tool availability
  cache-clear Clear the decompilation cache

Pull options:
  --list                  List installed packages
  --pkg <package>         Pull specific package
  --all                   Pull all installed APKs

Decompile/Analyze options:
  <apk_file>              Target APK
  -o, --output <dir>      Output directory
  --no-cache              Skip cache and force re-decompile

Batch options:
  <directory>             Directory with APKs
  --concurrency <n>       Parallel workers (default: 1)

Examples:
  $(basename "$0") full app.apk
  $(basename "$0") pull --pkg com.example.app
  $(basename "$0") batch ./apks/ --concurrency 4
  $(basename "$0") decompile app.apk -o ./output/
  $(basename "$0") analyze ./output/app/decompile
  $(basename "$0") cache-clear
EOF
    exit 0
}

check_tools() {
    echo "Tool availability:"
    echo ""
    local tools=(
        "jadx:Decompiler (Java/Kotlin sources)"
        "apktool:Disassembler (smali + resources)"
        "apk2url:URL/endpoint extractor"
        "aapt:Android asset packaging tool"
        "adb:Android debug bridge"
        "apksigner:APK signing"
        "zipalign:APK alignment"
        "r2:Radare2 binary analysis"
        "frida:Dynamic instrumentation"
        "yara:Pattern matching"
        "ssdeep:Fuzzy hashing"
        "exiftool:Metadata extraction"
        "d2j-dex2jar:DEX to JAR conversion"
        "python3:Python interpreter"
        "java:Java runtime"
    )

    printf "%-20s %-10s %s\n" "TOOL" "STATUS" "PURPOSE"
    printf "%-20s %-10s %s\n" "----" "------" "-------"
    for entry in "${tools[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        local path
        path=$(command -v "$name" 2>/dev/null || true)
        if [ -n "$path" ]; then
            printf "%-20s %s%-10s %s\n" "$name" "✓ " "OK" "$desc"
        else
            printf "%-20s %s%-10s %s\n" "$name" "✗ " "MISSING" "$desc"
        fi
    done

    # Python packages
    echo ""
    echo "Python packages:"
    python3 -c "import androguard; print('  ✓ androguard')" 2>/dev/null || echo "  ✗ androguard"
    python3 -c "import frida; print('  ✓ frida')" 2>/dev/null || echo "  ✗ frida"
}

# ── Banner ─────────────────────────────────────────────
banner

# ── Parse command ──────────────────────────────────────
COMMAND="${1:-}"
[ -z "$COMMAND" ] && usage
shift

case "$COMMAND" in
    tui)
        bash "${SCRIPT_DIR}/tui.sh"
        ;;
    pull)
        bash "${SCRIPT_DIR}/scripts/pull_apk.sh" "$@"
        ;;
    decompile)
        bash "${SCRIPT_DIR}/scripts/decompile.sh" "$@"
        ;;
    analyze)
        bash "${SCRIPT_DIR}/scripts/analyze.sh" "$@"
        ;;
    report)
        bash "${SCRIPT_DIR}/scripts/report.sh" "$@"
        ;;
    quick)
        APK_FILE="${1:-}"
        OUTPUT_DIR="${2:-}"
        NO_CACHE=false
        if [[ "${3:-}" == "--no-cache" ]]; then
            NO_CACHE=true
        fi
        [ -z "$APK_FILE" ] && { echo "Usage: $(basename "$0") quick <apk_file> [output_dir] [--no-cache]"; exit 1; }
        
        DECOMPILE_OUT="${OUTPUT_DIR:-${OUTPUT_BASE}/$(basename "$APK_FILE" .apk)/decompile}"
        
        # Check cache unless --no-cache is specified
        if [ "$NO_CACHE" = false ] && is_cache_valid "$APK_FILE" "$DECOMPILE_OUT"; then
            echo ""
            echo "[CACHE HIT] Using cached decompilation for: $APK_FILE"
            echo ""
        else
            echo ""
            echo "Quick scan (URLs + secrets) on: $APK_FILE"
            echo ""
            bash "${SCRIPT_DIR}/scripts/decompile.sh" "$APK_FILE" "$OUTPUT_DIR"
            update_cache "$APK_FILE"
        fi
        
        bash "${SCRIPT_DIR}/scripts/analyze.sh" "$DECOMPILE_OUT" "$APK_FILE" quick
        echo ""
        echo "[+] Quick scan complete"
        echo "    URLs:    ${DECOMPILE_OUT}/urls/"
        echo "    Secrets: ${DECOMPILE_OUT}/analysis/secrets.txt"
        ;;
    full)
        APK_FILE="${1:-}"
        OUTPUT_DIR="${2:-}"
        NO_CACHE=false
        if [[ "${3:-}" == "--no-cache" ]]; then
            NO_CACHE=true
        fi
        [ -z "$APK_FILE" ] && { echo "Usage: $(basename "$0") full <apk_file> [output_dir] [--no-cache]"; exit 1; }
        
        DECOMPILE_OUT="${OUTPUT_DIR:-${OUTPUT_BASE}/$(basename "$APK_FILE" .apk)/decompile}"
        
        # Check cache unless --no-cache is specified
        if [ "$NO_CACHE" = false ] && is_cache_valid "$APK_FILE" "$DECOMPILE_OUT"; then
            echo ""
            echo "[CACHE HIT] Using cached decompilation for: $APK_FILE"
            echo ""
        else
            echo ""
            echo "Running full pipeline on: $APK_FILE"
            echo ""
            bash "${SCRIPT_DIR}/scripts/decompile.sh" "$APK_FILE" "$OUTPUT_DIR"
            update_cache "$APK_FILE"
        fi
        
        bash "${SCRIPT_DIR}/scripts/analyze.sh" "$DECOMPILE_OUT" "$APK_FILE"
        bash "${SCRIPT_DIR}/scripts/report.sh" "$DECOMPILE_OUT" "$APK_FILE"
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  FULL PIPELINE COMPLETE                          ║"
        echo "╠══════════════════════════════════════════════════╣"
        echo "║  Report:   $DECOMPILE_OUT/REPORT.md"
        echo "║  Analysis: $DECOMPILE_OUT/analysis/"
        echo "║  URLs:     $DECOMPILE_OUT/urls/"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""
        echo "[+] Full pipeline complete"
        echo "    Report location: ${DECOMPILE_OUT}/REPORT.md"
        ;;
    batch)
        bash "${SCRIPT_DIR}/scripts/batch.sh" "$@"
        ;;
    check)
        check_tools
        ;;
    cache-clear)
        clean_cache
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
