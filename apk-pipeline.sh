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

# Workspace directory (parent of SCRIPT_DIR)
export WORKSPACE="$SCRIPT_DIR"

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
    printf '%b\n' "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    printf '%b\n' "${CYAN}║         APK DECOMPILE PIPELINE                   ║${NC}"
    printf '%b\n' "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
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
  apk2url     Extract URLs/endpoints only (fast, no full decompile)
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
  $(basename "$0") apk2url app.apk
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
    apk2url)
        APK_FILE="${1:-}"
        OUTPUT_DIR="${2:-}"
        [ -z "$APK_FILE" ] && { echo "Usage: $(basename "$0") apk2url <apk_file> [output_dir]"; exit 1; }
        
        BASENAME="$(basename "$APK_FILE" .apk)"
        DECOMPILE_OUT="${OUTPUT_DIR:-${OUTPUT_BASE}/${BASENAME}/decompile}"
        URLS_DIR="${DECOMPILE_OUT}/urls"
        
        mkdir -p "$URLS_DIR"
        
        echo ""
        echo "Extracting URLs from: $APK_FILE"
        echo ""
        
        # Use fast mode extraction logic directly
        URL_RE='(\b(https?)://|www\.)[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]'
        
        # Extract from APK directly using unzip and strings (fastest method)
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf \$TEMP_DIR" EXIT
        
        # Unzip APK to temp location
        unzip -q -o "$APK_FILE" -d "$TEMP_DIR" 2>/dev/null || true
        
        # Search for URLs in all files
        {
            # Search in XML files (AndroidManifest.xml, etc.)
            find "$TEMP_DIR" -name "*.xml" -exec grep -oE "$URL_RE" {} \; 2>/dev/null
            
            # Search in raw resources
            find "$TEMP_DIR" -name "*.json" -exec grep -oE "$URL_RE" {} \; 2>/dev/null
            
            # Search in DEX files using strings
            find "$TEMP_DIR" -name "*.dex" -exec strings {} \; 2>/dev/null | grep -oE "$URL_RE"
            
            # Search in native libraries
            find "$TEMP_DIR" -name "*.so" -exec strings {} \; 2>/dev/null | grep -oE "$URL_RE"
        } | sort -u > "${URLS_DIR}/${BASENAME}_urls.txt"
        
        # Extract unique domains
        grep -oE '((http|https)://[^/]+)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
            | sort -u > "${URLS_DIR}/${BASENAME}_domains.txt" || true
        grep -E '^www\.' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null | sort -u >> "${URLS_DIR}/${BASENAME}_domains.txt" || true
        
        # Extract IPs
        grep -oE '((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
            | sort -u > "${URLS_DIR}/${BASENAME}_ips.txt" || true
        
        url_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null || echo 0)
        domain_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_domains.txt" 2>/dev/null || echo 0)
        ip_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_ips.txt" 2>/dev/null || echo 0)
        
        echo ""
        printf '%b\n' "${CYAN}========================================${NC}"
        printf '%b\n' "${GREEN}       APK2URL EXTRACTION COMPLETE      ${NC}"
        printf '%b\n' "${CYAN}========================================${NC}"
        echo ""
        echo "[+] URLs extracted: $url_count"
        echo "[+] Domains found:  $domain_count"
        echo "[+] IPs found:      $ip_count"
        echo ""
        echo "    Output: ${URLS_DIR}/"
        echo "    URLs file:    ${URLS_DIR}/${BASENAME}_urls.txt"
        echo "    Domains file: ${URLS_DIR}/${BASENAME}_domains.txt"
        echo "    IPs file:     ${URLS_DIR}/${BASENAME}_ips.txt"
        echo ""
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
