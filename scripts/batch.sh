#!/usr/bin/env bash
# batch.sh - Batch process multiple APKs
# Usage: batch.sh <directory_or_apk_list> [concurrency]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

# Cache configuration (shared with apk-pipeline.sh)
CACHE_DIR="$WORKSPACE/.cache"
HASH_FILE="$CACHE_DIR/apk_hashes.txt"
mkdir -p "$CACHE_DIR"
touch "$HASH_FILE"

INPUT="${1:-}"
CONCURRENCY="${2:-1}"
RESULTS_DIR="${OUTPUT_BASE}/batch_results"
LOG_FILE="${RESULTS_DIR}/batch_$(date +%Y%m%d_%H%M%S).log"

if [ -z "$INPUT" ]; then
    cat <<EOF
Usage: $(basename "$0") <input> [concurrency]

Input can be:
  - A directory containing .apk files
  - A text file with one APK path per line
  - A single .apk file

Examples:
  $(basename "$0") ./apks/
  $(basename "$0") apk_list.txt 4
  $(basename "$0") single_app.apk
EOF
    exit 1
fi

mkdir -p "$RESULTS_DIR"

echo "╔══════════════════════════════════════════════════╗"
echo "║         BATCH APK ANALYSIS                      ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Input:  $INPUT"
echo "║  Workers: $CONCURRENCY"
echo "║  Output:  $RESULTS_DIR"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Collect APK list
APK_LIST=()

if [ -d "$INPUT" ]; then
    while IFS= read -r apk; do
        APK_LIST+=("$apk")
    done < <(find "$INPUT" -maxdepth 1 -name "*.apk" -type f | sort)
elif [[ "$INPUT" == *.txt ]] && [ -f "$INPUT" ]; then
    # Text file with one APK path per line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ -f "$line" ] && APK_LIST+=("$line")
    done < "$INPUT"
elif [ -f "$INPUT" ] && [[ "$INPUT" == *.apk ]]; then
    # Single APK file
    APK_LIST=("$INPUT")
else
    echo "[-] Invalid input: $INPUT"
    exit 1
fi

TOTAL=${#APK_LIST[@]}
if [ "$TOTAL" -eq 0 ]; then
    echo "[-] No APK files found"
    exit 1
fi

echo "[+] Found $TOTAL APK(s) to process"
echo ""

# ── Run pipeline on each APK ──────────────────────────
COUNT=0
PASS=0
FAIL=0

for apk in "${APK_LIST[@]}"; do
    ((++COUNT))
    apk_name="$(basename "$apk" .apk)"
    echo "[$COUNT/$TOTAL] Processing: $apk_name"

    # Check cache first
    decompile_out="${RESULTS_DIR}/${apk_name}/decompile"
    if [ -f "$HASH_FILE" ] && grep -q "^$apk|" "$HASH_FILE" 2>/dev/null; then
        stored_hash=$(grep "^$apk|" "$HASH_FILE" | cut -d'|' -f2)
        current_hash=$(sha256sum "$apk" | awk '{print $1}')
        if [ "$current_hash" = "$stored_hash" ] && [ -d "$decompile_out" ] && [ -f "$decompile_out/report.txt" ]; then
            echo "  [~] Cache hit - skipping decompile"
        else
            # Decompile
            if bash "${SCRIPT_DIR}/decompile.sh" "$apk" "${RESULTS_DIR}/${apk_name}" >> "$LOG_FILE" 2>&1; then
                # Update cache
                echo "$apk|$current_hash" >> "$HASH_FILE"
            else
                echo "  [-] Decompile failed (see log)"
                ((++FAIL))
                continue
            fi
        fi
    else
        # Decompile
        if bash "${SCRIPT_DIR}/decompile.sh" "$apk" "${RESULTS_DIR}/${apk_name}" >> "$LOG_FILE" 2>&1; then
            # Add to cache
            mkdir -p "$CACHE_DIR"
            current_hash=$(sha256sum "$apk" | awk '{print $1}')
            echo "$apk|$current_hash" >> "$HASH_FILE"
        else
            echo "  [-] Decompile failed (see log)"
            ((++FAIL))
            continue
        fi
    fi
    
    # Analyze
    if bash "${SCRIPT_DIR}/analyze.sh" "${RESULTS_DIR}/${apk_name}/decompile" "$apk" >> "$LOG_FILE" 2>&1; then
        # Report
        bash "${SCRIPT_DIR}/report.sh" "${RESULTS_DIR}/${apk_name}/decompile" "$apk" >> "$LOG_FILE" 2>&1 || true
        echo "  [+] OK - ${RESULTS_DIR}/${apk_name}/decompile/REPORT.md"
        ((++PASS))
    else
        echo "  [-] Analysis failed (see log)"
        ((++FAIL))
    fi
    echo ""
done

# ── Summary ────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════╗"
echo "║  BATCH COMPLETE                                 ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Total:   $TOTAL"
echo "║  Success: $PASS"
echo "║  Failed:  $FAIL"
echo "║  Log:     $LOG_FILE"
echo "╚══════════════════════════════════════════════════╝"

# ── Generate batch summary ────────────────────────────
SUMMARY="${RESULTS_DIR}/batch_summary_$(date +%Y%m%d_%H%M%S).md"
{
    echo "# Batch Analysis Summary"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Total | $TOTAL |"
    echo "| Passed | $PASS |"
    echo "| Failed | $FAIL |"
    echo "| Date | $(date -u +"%Y-%m-%d %H:%M UTC") |"
    echo ""
    echo "## Results"
    echo ""
    echo "| APK | Status | Report |"
    echo "|-----|--------|--------|"
    for apk in "${APK_LIST[@]}"; do
        apk_name="$(basename "$apk" .apk)"
        report="${RESULTS_DIR}/${apk_name}/decompile/REPORT.md"
        if [ -f "$report" ]; then
            echo "| $apk_name | PASS | [Report]($report) |"
        else
            echo "| $apk_name | FAIL | - |"
        fi
    done
} > "$SUMMARY"

echo "[+] Summary: $SUMMARY"
