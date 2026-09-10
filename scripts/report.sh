#!/usr/bin/env bash
# report.sh - Generate markdown and HTML reports from decompile + analysis output
# Usage: report.sh <decompile_output_dir> [apk_file] [--html]
# Options:
#   --html    Also generate an HTML report in addition to Markdown

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

DECOMPILE_DIR="${1:-}"
APK_FILE="${2:-}"
OUTPUT_FORMAT="${3:-md}"  # md, html, or both

if [ -z "$DECOMPILE_DIR" ]; then
    echo "Usage: $(basename "$0") <decompile_output_dir> [apk_file] [--html]"
    exit 1
fi

# Check for --html flag
GENERATE_HTML=false
if [ "${3:-}" = "--html" ] || [ "${4:-}" = "--html" ]; then
    GENERATE_HTML=true
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

# ── HTML Report Generation ───────────────────────────────
if [ "$GENERATE_HTML" = true ]; then
    HTML_REPORT="${DECOMPILE_DIR}/REPORT.html"
    echo "Generating HTML report..."
    
    # Extract risk score from permissions.txt if available
    risk_score="N/A"
    risk_level="Unknown"
    if [ -f "${ANALYSIS_DIR}/permissions.txt" ]; then
        risk_score_line=$(grep "OVERALL RISK SCORE:" "${ANALYSIS_DIR}/permissions.txt" 2>/dev/null || echo "")
        risk_level_line=$(grep "RISK LEVEL:" "${ANALYSIS_DIR}/permissions.txt" 2>/dev/null || echo "")
        if [ -n "$risk_score_line" ]; then
            risk_score=$(echo "$risk_score_line" | grep -oE '[0-9]+ / [0-9]+' || echo "N/A")
        fi
        if [ -n "$risk_level_line" ]; then
            risk_level=$(echo "$risk_level_line" | sed 's/RISK LEVEL://' | xargs)
        fi
    fi
    
    # Count findings
    secret_count=0
    if [ -f "${ANALYSIS_DIR}/secrets.txt" ]; then
        secret_count=$(grep -cvE '^$|^===|^---' "${ANALYSIS_DIR}/secrets.txt" 2>/dev/null || echo 0)
    fi
    
    cat > "$HTML_REPORT" << 'HTMLHEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK Analysis Report</title>
    <style>
        :root {
            --primary: #2563eb;
            --danger: #dc2626;
            --warning: #d97706;
            --success: #16a34a;
            --bg: #f8fafc;
            --card-bg: #ffffff;
            --text: #1e293b;
            --text-muted: #64748b;
            --border: #e2e8f0;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
            padding: 2rem;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        header {
            background: linear-gradient(135deg, var(--primary), #1e40af);
            color: white;
            padding: 2rem;
            border-radius: 12px;
            margin-bottom: 2rem;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
        }
        header h1 { font-size: 2rem; margin-bottom: 0.5rem; }
        header .meta { opacity: 0.9; font-size: 0.9rem; }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }
        .stat-card {
            background: var(--card-bg);
            padding: 1.5rem;
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            border-left: 4px solid var(--primary);
        }
        .stat-card.danger { border-left-color: var(--danger); }
        .stat-card.warning { border-left-color: var(--warning); }
        .stat-card.success { border-left-color: var(--success); }
        .stat-card h3 { font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
        .stat-card .value { font-size: 1.75rem; font-weight: 700; margin-top: 0.25rem; }
        
        .risk-badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 9999px;
            font-weight: 600;
            font-size: 0.875rem;
        }
        .risk-critical { background: #fef2f2; color: var(--danger); }
        .risk-high { background: #fff7ed; color: var(--warning); }
        .risk-medium { background: #fefce8; color: #ca8a04; }
        .risk-low { background: #f0fdf4; color: var(--success); }
        .risk-minimal { background: #f8fafc; color: var(--text-muted); }
        
        section {
            background: var(--card-bg);
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 1.5rem;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        section h2 {
            font-size: 1.25rem;
            color: var(--primary);
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid var(--border);
        }
        section h3 {
            font-size: 1rem;
            color: var(--text);
            margin: 1rem 0 0.5rem;
        }
        pre {
            background: #1e293b;
            color: #e2e8f0;
            padding: 1rem;
            border-radius: 6px;
            overflow-x: auto;
            font-size: 0.85rem;
            line-height: 1.5;
        }
        code { font-family: 'Monaco', 'Consolas', monospace; }
        .finding { 
            padding: 0.75rem; 
            margin: 0.5rem 0; 
            background: #fef2f2; 
            border-left: 3px solid var(--danger);
            border-radius: 0 4px 4px 0;
        }
        .finding.medium { background: #fff7ed; border-left-color: var(--warning); }
        .finding.low { background: #f0fdf4; border-left-color: var(--success); }
        table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
        th, td { padding: 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
        th { background: var(--bg); font-weight: 600; }
        .tag {
            display: inline-block;
            padding: 0.125rem 0.5rem;
            background: var(--bg);
            border-radius: 4px;
            font-size: 0.75rem;
            margin: 0.125rem;
        }
        footer {
            text-align: center;
            padding: 2rem;
            color: var(--text-muted);
            font-size: 0.875rem;
        }
        @media (max-width: 768px) {
            body { padding: 1rem; }
            .stats-grid { grid-template-columns: 1fr 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔒 APK Security Analysis Report</h1>
            <div class="meta">
                <p><strong>File:</strong> <code id="apk-file">LOADING</code></p>
                <p><strong>SHA256:</strong> <code id="apk-sha">LOADING</code></p>
                <p><strong>Generated:</strong> <span id="report-date">LOADING</span></p>
            </div>
        </header>
        
        <div class="stats-grid">
HTMLHEADER

    # Add stats to HTML
    cat >> "$HTML_REPORT" << STATS
            <div class="stat-card ${secret_count gt 0 && echo 'danger' || echo 'success'}">
                <h3>Secrets Found</h3>
                <div class="value">$secret_count</div>
            </div>
            <div class="stat-card warning">
                <h3>Risk Score</h3>
                <div class="value">$risk_score</div>
            </div>
            <div class="stat-card">
                <h3>Risk Level</h3>
                <div class="value"><span class="risk-badge risk-$(echo "$risk_level" | tr '[:upper:]' '[:lower:]' | tr -d ' ')">$risk_level</span></div>
            </div>
            <div class="stat-card success">
                <h3>Status</h3>
                <div class="value">Complete</div>
            </div>
STATS

    cat >> "$HTML_REPORT" << 'HTMLMID'
        </div>
HTMLMID

    # Process each analysis file and add to HTML
    if [ -f "${ANALYSIS_DIR}/permissions.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>📋 Permissions Analysis</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/permissions.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/secrets.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>🔑 Secrets & Hardcoded Keys</h2>" >> "$HTML_REPORT"
        if [ "$secret_count" -gt 0 ]; then
            echo "            <div class=\"finding danger\"><strong>⚠️ $secret_count potential secrets found!</strong></div>" >> "$HTML_REPORT"
        else
            echo "            <div class=\"finding low\"><strong>✅ No hardcoded secrets detected.</strong></div>" >> "$HTML_REPORT"
        fi
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/secrets.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/network.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>🌐 Network Configuration</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/network.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/crypto.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>🔐 Cryptography Usage</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/crypto.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/sensitive_data.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>👁️ Sensitive Data Access</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/sensitive_data.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/smali_patterns.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>🔍 Smali Patterns (Root/Debug/Emulator Detection)</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/smali_patterns.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    if [ -f "${ANALYSIS_DIR}/native_strings.txt" ]; then
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>📦 Native Libraries</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${ANALYSIS_DIR}/native_strings.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi
    
    # Add URLs section
    if [ -d "$URLS_DIR" ] && [ -f "${URLS_DIR}/${BASENAME}_domains.txt" ]; then
        domain_count=$(wc -l < "${URLS_DIR}/${BASENAME}_domains.txt")
        echo "        <section>" >> "$HTML_REPORT"
        echo "            <h2>🔗 Extracted Domains ($domain_count)</h2>" >> "$HTML_REPORT"
        echo "            <pre><code>" >> "$HTML_REPORT"
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "${URLS_DIR}/${BASENAME}_domains.txt" >> "$HTML_REPORT"
        echo "            </code></pre>" >> "$HTML_REPORT"
        echo "        </section>" >> "$HTML_REPORT"
    fi

    # Close HTML
    cat >> "$HTML_REPORT" << 'HTMLFOOTER'
        <footer>
            <p>Generated by <strong>apk-pipeline</strong> • Security Analysis Tool</p>
            <p id="report-timestamp"></p>
        </footer>
        
        <script>
            // Populate dynamic values
            document.getElementById('apk-file').textContent = window.location.pathname.split('/').pop().replace('.html', '');
            document.getElementById('report-date').textContent = new Date().toLocaleString();
            document.getElementById('report-timestamp').textContent = 'Report generated: ' + new Date().toISOString();
        </script>
    </div>
</body>
</html>
HTMLFOOTER

    echo "[+] HTML Report: $HTML_REPORT"
fi
