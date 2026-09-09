#!/usr/bin/env bash
# apk-pipeline.sh - Main orchestrator for APK reverse engineering
# Usage: apk-pipeline.sh <command> [options]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

VERSION="1.0.0"

banner() {
    cat <<EOF

  █████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗
 ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝
 ███████║██████╔╝███████║██████╔╝█████╔╝
 ██╔══██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗
 ██║  ██║██║     ██║  ██║██║  ██║██║  ██╗
 ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝

  APK Reverse Engineering Pipeline v${VERSION}
  jadx + apktool + apk2url + frida + yara + r2
EOF
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  tui         Launch interactive TUI (fzf-based)
  pull        Pull APK(s) from connected device
  decompile   Decompile APK with all engines
  analyze     Run deep static analysis
  report      Generate markdown report
  quick       Quick scan: URLs + secrets only (decompile + secrets)
  full        Run full pipeline (decompile + analyze + report)
  batch       Process multiple APKs
  check       Check tool availability

Pull options:
  --list                  List installed packages
  --pkg <package>         Pull specific package
  --all                   Pull all installed APKs

Decompile/Analyze options:
  <apk_file>              Target APK
  -o, --output <dir>      Output directory

Batch options:
  <directory>             Directory with APKs
  --concurrency <n>       Parallel workers (default: 1)

Examples:
  $(basename "$0") full app.apk
  $(basename "$0") pull --pkg com.example.app
  $(basename "$0") batch ./apks/ --concurrency 4
  $(basename "$0") decompile app.apk -o ./output/
  $(basename "$0") analyze ./output/app/decompile
  $(basename "$0") check
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
        [ -z "$APK_FILE" ] && { echo "Usage: $(basename "$0") quick <apk_file> [output_dir]"; exit 1; }
        echo ""
        echo "Quick scan (URLs + secrets) on: $APK_FILE"
        echo ""
        bash "${SCRIPT_DIR}/scripts/decompile.sh" "$APK_FILE" "$OUTPUT_DIR"
        DECOMPILE_OUT="${OUTPUT_DIR:-${OUTPUT_BASE}/$(basename "$APK_FILE" .apk)/decompile}"
        bash "${SCRIPT_DIR}/scripts/analyze.sh" "$DECOMPILE_OUT" "$APK_FILE" quick
        echo ""
        echo "[+] Quick scan complete"
        echo "    URLs:    ${DECOMPILE_OUT}/urls/"
        echo "    Secrets: ${DECOMPILE_OUT}/analysis/secrets.txt"
        ;;
    full)
        APK_FILE="${1:-}"
        OUTPUT_DIR="${2:-}"
        [ -z "$APK_FILE" ] && { echo "Usage: $(basename "$0") full <apk_file> [output_dir]"; exit 1; }
        echo ""
        echo "Running full pipeline on: $APK_FILE"
        echo ""
        bash "${SCRIPT_DIR}/scripts/decompile.sh" "$APK_FILE" "$OUTPUT_DIR"
        DECOMPILE_OUT="${OUTPUT_DIR:-${OUTPUT_BASE}/$(basename "$APK_FILE" .apk)/decompile}"
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
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
