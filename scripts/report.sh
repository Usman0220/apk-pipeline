#!/usr/bin/env bash
# report.sh - Generate markdown report from decompile + analysis output
# Usage: report.sh <decompile_output_dir> [apk_file]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

DECOMPILE_DIR="${1:-}"
APK_FILE="${2:-}"

if [ -z "$DECOMPILE_DIR" ]; then
    echo "Usage: $(basename "$0") <decompile_output_dir> [apk_file]"
    exit 1
fi

# Resolve app name: prefer manifest.json's apk name (matches decompile.sh's
# file naming "<basename>_urls.txt"), fall back to decompile dir name.
BASENAME="$(basename "$DECOMPILE_DIR")"
if [ -f "${DECOMPILE_DIR}/manifest.json" ]; then
    _apk=$(grep -o '"apk": "[^"]*"' "${DECOMPILE_DIR}/manifest.json" | head -1 | cut -d'"' -f4)
    [ -n "$_apk" ] && BASENAME="${_apk%.apk}"
fi
ANALYSIS_DIR="${DECOMPILE_DIR}/analysis"
REPORT_FILE="${DECOMPILE_DIR}/REPORT.md"

# Try to load manifest.json for metadata
SHA256="unknown"
SIZE="unknown"
if [ -f "${DECOMPILE_DIR}/manifest.json" ]; then
    SHA256=$(grep -o '"sha256": "[^"]*"' "${DECOMPILE_DIR}/manifest.json" | head -1 | cut -d'"' -f4)
    SIZE=$(grep -o '"size": "[^"]*"' "${DECOMPILE_DIR}/manifest.json" | head -1 | cut -d'"' -f4)
fi

if [ -n "$APK_FILE" ] && [ -f "$APK_FILE" ]; then
    SHA256=$(sha256sum "$APK_FILE" | awk '{print $1}')
    SIZE=$(du -h "$APK_FILE" | awk '{print $1}')
fi

# greps on possibly-empty outputs return 1 — not fatal
set +e

cat > "$REPORT_FILE" <<EOF
# APK Analysis Report

| Field | Value |
|-------|-------|
| **File** | \`$(basename "${APK_FILE:-$BASENAME}")\` |
| **SHA256** | \`${SHA256}\` |
| **Size** | \`${SIZE}\` |
| **Date** | \`$(date -u +"%Y-%m-%d %H:%M UTC")\` |

---

EOF

# ── Permissions ────────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/permissions.txt" ]; then
    echo "## Permissions" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/permissions.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── Secrets ────────────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/secrets.txt" ]; then
    secret_lines=$(grep -vE '^#|^$|^===|^---' "${ANALYSIS_DIR}/secrets.txt" | grep -v "^$" | wc -l)
    echo "## Secrets & Hardcoded Keys" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    if [ "$secret_lines" -gt 0 ]; then
        echo "> **Found $secret_lines potential secret(s)**" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        head -150 "${ANALYSIS_DIR}/secrets.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    else
        echo "> No hardcoded secrets found." >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
fi

# ── YARA ───────────────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/yara_hits.txt" ]; then
    yara_lines=$(wc -l < "${ANALYSIS_DIR}/yara_hits.txt" 2>/dev/null || echo 0)
    if [ "$yara_lines" -gt 0 ]; then
        echo "## YARA Rule Matches" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "${ANALYSIS_DIR}/yara_hits.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
fi

# ── Network ────────────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/network.txt" ]; then
    echo "## Network Configuration" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/network.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── Crypto ─────────────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/crypto.txt" ]; then
    echo "## Cryptography" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/crypto.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── Sensitive data ─────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/sensitive_data.txt" ]; then
    echo "## Sensitive Data Access" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/sensitive_data.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── Smali patterns ─────────────────────────────────────
if [ -f "${ANALYSIS_DIR}/smali_patterns.txt" ]; then
    echo "## Smali Patterns (Root/Debug/Emu Detection)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/smali_patterns.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── Native libraries ───────────────────────────────────
if [ -f "${ANALYSIS_DIR}/native_strings.txt" ]; then
    echo "## Native Libraries" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    cat "${ANALYSIS_DIR}/native_strings.txt" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# ── URLs / Domains ────────────────────────────────────
URLS_DIR="${DECOMPILE_DIR}/urls"
if [ -d "$URLS_DIR" ]; then
    echo "## Extracted URLs & Domains" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    if [ -f "${URLS_DIR}/${BASENAME}_domains.txt" ]; then
        domain_count=$(wc -l < "${URLS_DIR}/${BASENAME}_domains.txt")
        echo "### Unique Domains ($domain_count)" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        cat "${URLS_DIR}/${BASENAME}_domains.txt" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    fi

    if [ -f "${URLS_DIR}/${BASENAME}_urls.txt" ]; then
        url_count=$(wc -l < "${URLS_DIR}/${BASENAME}_urls.txt")
        echo "### All URLs ($url_count)" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        head -200 "${URLS_DIR}/${BASENAME}_urls.txt" >> "$REPORT_FILE"
        [ "$url_count" -gt 200 ] && echo "... (truncated, see full list in urls/)" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "*Generated by apk-pipeline*" >> "$REPORT_FILE"

set -e
echo "[+] Report: $REPORT_FILE"
wc -l "$REPORT_FILE" | awk '{print "[+] Lines: " $1}'
