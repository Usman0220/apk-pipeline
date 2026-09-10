#!/usr/bin/env bash
# analyze.sh - Deep static analysis of decompiled APK
# Usage: analyze.sh <decompile_output_dir> [apk_file]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

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

DECOMPILE_DIR="${1:-}"
APK_FILE="${2:-}"
MODE="${3:-full}"   # full | quick (quick = secrets only; URLs via decompile)
PROGRESS_CALLBACK="${4:-}"  # Optional: command to call for progress updates

# Progress reporting function
report_progress() {
    local step="$1"
    local total_steps="$2"
    local message="$3"
    local percent=$((step * 100 / total_steps))
    
    if [ -n "$PROGRESS_CALLBACK" ] && command -v "$PROGRESS_CALLBACK" >/dev/null 2>&1; then
        $PROGRESS_CALLBACK "$percent" "$message"
    else
        printf "\r[%3d%%] %-50s" "$percent" "$message"
    fi
}

if [ -z "$DECOMPILE_DIR" ]; then
    echo "Usage: $(basename "$0") <decompile_output_dir> [apk_file] [full|quick]"
    exit 1
fi

BASENAME="$(basename "$DECOMPILE_DIR")"
if [ -f "${DECOMPILE_DIR}/manifest.json" ]; then
    _apk=$(grep -o '"apk": "[^"]*"' "${DECOMPILE_DIR}/manifest.json" | head -1 | cut -d'"' -f4)
    [ -n "$_apk" ] && BASENAME="${_apk%.apk}"
fi
ANALYSIS_DIR="${DECOMPILE_DIR}/analysis"
mkdir -p "$ANALYSIS_DIR"

echo "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║         APK ANALYSIS PIPELINE                    ║${NC}"
echo "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

TOTAL_STEPS=8

# ── Secrets scan (used by full & quick modes) ──────────
scan_secrets() {
    echo ""
    echo "━━━ Secrets & API keys ━━━━━━━━━━━━━━━━━━━━━━━━━"
    SEARCH_DIRS=()
    [ -d "${DECOMPILE_DIR}/jadx_sources" ] && SEARCH_DIRS+=("${DECOMPILE_DIR}/jadx_sources")
    [ -d "${DECOMPILE_DIR}/apktool_smali" ] && SEARCH_DIRS+=("${DECOMPILE_DIR}/apktool_smali")

    {
        echo "=== POTENTIAL SECRETS ==="

        echo ""
        echo "--- API Keys ---"
        grep -rniE '(api[_-]?key|apikey|secret[_-]?key|auth[_-]?token|access[_-]?token|client[_-]?secret)\s*[=:]\s*["\x27][A-Za-z0-9+/=_-]{16,}["\x27]' "${SEARCH_DIRS[@]}" 2>/dev/null | head -100

        echo ""
        echo "--- AWS Keys ---"
        # AWS Access Key ID pattern
        grep -rniE 'AKIA[0-9A-Z]{16}' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20
        # AWS Secret Key pattern
        grep -rniE '(aws[_-]?secret[_-]?access[_-]?key|wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

        echo ""
        echo "--- Google API Keys ---"
        grep -rniE 'AIza[0-9A-Za-z_-]{35}' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

        echo ""
        echo "--- Firebase ---"
        grep -rniE '(firebaseio\.com|firebase\.google\.com|googleapis\.com.*firebase)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

        echo ""
        echo "--- Hardcoded Passwords ---"
        grep -rniE '(password|passwd|pwd)\s*[=:]\s*["\x27][^"\x27]{4,}["\x27]' "${SEARCH_DIRS[@]}" 2>/dev/null | head -50

        echo ""
        echo "--- Private Keys ---"
        grep -rniE 'BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY' "${SEARCH_DIRS[@]}" 2>/dev/null | head -10

        echo ""
        echo "--- JWT Tokens ---"
        grep -rniE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' "${SEARCH_DIRS[@]}" 2>/dev/null | head -10

        echo ""
        echo "--- Hardcoded IPs (Public Only) ---"
        # Extract all IPs, then filter out private/reserved ranges
        grep -rnoE '\b((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)\b' "${SEARCH_DIRS[@]}" 2>/dev/null \
            | grep -vE '(0\.0\.0\.0|127\.0\.0\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|255\.255|169\.254\.|::1|localhost)' \
            | sort -u | head -50

        echo ""
        echo "--- Azure SAS Tokens ---"
        grep -rniE 'sig=[A-Za-z0-9%]{40,}' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

        echo ""
        echo "--- GitHub Tokens ---"
        grep -rniE '(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|ghu_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}|ghr_[A-Za-z0-9]{36})' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

        echo ""
        echo "--- Stripe Keys ---"
        grep -rniE '(sk_live_[0-9a-zA-Z]{24}|pk_live_[0-9a-zA-Z]{24})' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

    } > "${ANALYSIS_DIR}/secrets.txt" 2>&1

    echo "[+] Secrets scan saved"
}

# Analysis greps return exit 1 on "no match" — expected, not fatal.
set +e

# ── Quick mode: URLs (decompile) + secrets only ────────
if [ "$MODE" = "quick" ]; then
    scan_secrets
    set -e
    echo ""
    echo "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║  QUICK SCAN COMPLETE (URLs + Secrets)            ║${NC}"
    echo "${GREEN}╠══════════════════════════════════════════════════╣${NC}"
    echo "${GREEN}║${NC}  ${BOLD}URLs:${NC}    ${DECOMPILE_DIR}/urls/"
    echo "${GREEN}║${NC}  ${BOLD}Secrets:${NC} ${ANALYSIS_DIR}/secrets.txt"
    echo "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    exit 0
fi

# ── 1. YARA rules scan ────────────────────────────────
report_progress 1 $TOTAL_STEPS "Running YARA scanning..."
if [ -n "$YARA" ] && [ -f "${PIPELINE_DIR}/rules/default.yar" ]; then
    $YARA -r "${PIPELINE_DIR}/rules/default.yar" "$DECOMPILE_DIR" > "${ANALYSIS_DIR}/yara_hits.txt" 2>&1 || true
    yara_count=$(wc -l < "${ANALYSIS_DIR}/yara_hits.txt" 2>/dev/null || echo 0)
    echo "[+] YARA hits: $yara_count"
else
    echo "[~] Skipped (no rules or yara not found)"
    echo "# No YARA scan performed" > "${ANALYSIS_DIR}/yara_hits.txt"
fi

# ── 2. Permissions analysis with Risk Scoring ───────────
report_progress 2 $TOTAL_STEPS "Analyzing permissions & risk score..."
{
    echo "=== ANDROID PERMISSIONS ==="
    # From manifest
    manifest="${DECOMPILE_DIR}/apktool_smali/AndroidManifest.xml"
    [ ! -f "$manifest" ] && manifest="${DECOMPILE_DIR}/metadata/manifest_xmltree.txt"

    if [ -f "$manifest" ]; then
        grep -i "permission" "$manifest" 2>/dev/null | sed 's/.*android:name="\([^"]*\)".*/\1/' | sort -u
    fi

    echo ""
    echo "=== DANGEROUS PERMISSIONS ==="
    dangerous_perms=(
        "SEND_SMS" "READ_SMS" "RECEIVE_SMS" "READ_CONTACTS" "WRITE_CONTACTS"
        "READ_CALL_LOG" "WRITE_CALL_LOG" "CALL_PHONE" "READ_PHONE_STATE"
        "READ_EXTERNAL_STORAGE" "WRITE_EXTERNAL_STORAGE" "CAMERA"
        "RECORD_AUDIO" "ACCESS_FINE_LOCATION" "ACCESS_COARSE_LOCATION"
        "READ_CALENDAR" "WRITE_CALENDAR" "RECEIVE_BOOT_COMPLETED"
        "SYSTEM_ALERT_WINDOW" "WRITE_SETTINGS" "INSTALL_PACKAGES"
        "DELETE_PACKAGES" "READ_MEDIA_IMAGES" "READ_MEDIA_VIDEO"
        "READ_MEDIA_AUDIO" "BODY_SENSORS" "ACTIVITY_RECOGNITION"
    )

    # High-risk permissions (score = 3)
    high_risk_perms=("SEND_SMS" "READ_SMS" "RECEIVE_SMS" "READ_CALL_LOG" "WRITE_CALL_LOG" 
                     "CALL_PHONE" "CAMERA" "RECORD_AUDIO" "READ_CONTACTS" "WRITE_CONTACTS"
                     "ACCESS_FINE_LOCATION" "BODY_SENSORS" "INSTALL_PACKAGES" "DELETE_PACKAGES")
    
    # Medium-risk permissions (score = 2)
    medium_risk_perms=("READ_PHONE_STATE" "READ_EXTERNAL_STORAGE" "WRITE_EXTERNAL_STORAGE"
                       "ACCESS_COARSE_LOCATION" "READ_CALENDAR" "WRITE_CALENDAR"
                       "SYSTEM_ALERT_WINDOW" "WRITE_SETTINGS" "READ_MEDIA_IMAGES"
                       "READ_MEDIA_VIDEO" "READ_MEDIA_AUDIO")
    
    # Low-risk permissions (score = 1)
    low_risk_perms=("RECEIVE_BOOT_COMPLETED" "ACTIVITY_RECOGNITION")

    high_count=0
    medium_count=0
    low_count=0
    found_high=()
    found_medium=()
    found_low=()

    for perm in "${dangerous_perms[@]}"; do
        if grep -qi "$perm" "$manifest" 2>/dev/null; then
            # Check risk level
            is_high=false
            is_medium=false
            is_low=false
            
            for hp in "${high_risk_perms[@]}"; do
                [[ "$perm" == *"$hp"* ]] && is_high=true && break
            done
            if ! $is_high; then
                for mp in "${medium_risk_perms[@]}"; do
                    [[ "$perm" == *"$mp"* ]] && is_medium=true && break
                done
            fi
            if ! $is_high && ! $is_medium; then
                for lp in "${low_risk_perms[@]}"; do
                    [[ "$perm" == *"$lp"* ]] && is_low=true && break
                done
            fi
            
            if $is_high; then
                ((high_count++))
                found_high+=("$perm")
                echo "  [!!!] $perm (HIGH RISK)"
            elif $is_medium; then
                ((medium_count++))
                found_medium+=("$perm")
                echo "  [!!] $perm (MEDIUM RISK)"
            elif $is_low; then
                ((low_count++))
                found_low+=("$perm")
                echo "  [!] $perm (LOW RISK)"
            else
                echo "  [!] $perm"
            fi
        fi
    done

    echo ""
    echo "=== EXPORTED COMPONENTS ==="
    # Check for exported activities and services
    exported_count=0
    if [ -f "$manifest" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -qi 'android:exported="true"'; then
                ((exported_count++))
            fi
        done < <(grep -iE '(activity|service|receiver|provider)' "$manifest" 2>/dev/null)
    fi
    echo "Exported components: $exported_count"
    
    # Calculate risk score
    risk_score=$((high_count * 3 + medium_count * 2 + low_count * 1))
    if [ $exported_count -gt 5 ]; then
        risk_score=$((risk_score + exported_count / 2))
    fi
    
    # Determine risk level
    if [ $risk_score -ge 15 ]; then
        risk_level="CRITICAL"
        risk_icon="🔴"
    elif [ $risk_score -ge 8 ]; then
        risk_level="HIGH"
        risk_icon="🟠"
    elif [ $risk_score -ge 4 ]; then
        risk_level="MEDIUM"
        risk_icon="🟡"
    elif [ $risk_score -ge 1 ]; then
        risk_level="LOW"
        risk_icon="🟢"
    else
        risk_level="MINIMAL"
        risk_icon="⚪"
    fi

    echo ""
    echo "=== RISK SCORE SUMMARY ==="
    echo "High-risk permissions: $high_count"
    echo "Medium-risk permissions: $medium_count"
    echo "Low-risk permissions: $low_count"
    echo "Exported components: $exported_count"
    echo ""
    echo "OVERALL RISK SCORE: $risk_score / 50"
    echo "RISK LEVEL: $risk_icon $risk_level"
    
    if [ ${#found_high[@]} -gt 0 ]; then
        echo ""
        echo "⚠️  HIGH-RISK PERMISSIONS FOUND:"
        for p in "${found_high[@]}"; do
            echo "   - $p"
        done
    fi
    
} > "${ANALYSIS_DIR}/permissions.txt" 2>&1

echo "[+] Permissions analysis saved"

# ── 3. Hardcoded secrets & API keys ───────────────────
report_progress 3 $TOTAL_STEPS "Scanning secrets & API keys..."
scan_secrets

# ── 4. Crypto detection ───────────────────────────────
report_progress 4 $TOTAL_STEPS "Detecting crypto patterns..."
{
    echo "=== CRYPTO USAGE ==="

    echo ""
    echo "--- Java/Kotlin Crypto ---"
    grep -rniE '(javax\.crypto|SecretKeyFactory|Cipher\.getInstance|MessageDigest\.getInstance|KeyGenerator|KeyStore)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -50

    echo ""
    echo "--- Hardcoded IVs / Keys ---"
    grep -rniE '(IvParameterSpec|SecretKeySpec)\s*\(' "${SEARCH_DIRS[@]}" 2>/dev/null | head -30

    echo ""
    echo "--- Custom Encryption ---"
    grep -rniE '(Base64\.encode|Base64\.decode|encodeToString|getBytes\("UTF-8"\))' "${SEARCH_DIRS[@]}" 2>/dev/null | head -30
} > "${ANALYSIS_DIR}/crypto.txt" 2>&1

echo "[+] Crypto analysis saved"

# ── 5. Network analysis ───────────────────────────────
report_progress 5 $TOTAL_STEPS "Analyzing network patterns..."
{
    echo "=== NETWORK CONFIGURATION ==="

    echo ""
    echo "--- Network Security Config ---"
    netsec="${DECOMPILE_DIR}/apktool_smali/res/xml/network_security_config.xml"
    if [ -f "$netsec" ]; then
        cat "$netsec"
    else
        echo "(no network_security_config.xml found)"
    fi

    echo ""
    echo "--- HTTP URLs (cleartext) ---"
    grep -rniE 'http://' "${SEARCH_DIRS[@]}" 2>/dev/null | grep -v "https://" | head -50

    echo ""
    echo "--- Trust Anchors ---"
    grep -rniE '(TrustManager|X509TrustManager|SSLSocketFactory|hostnameVerifier|ALLOW_ALL_HOSTNAME)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -30

    echo ""
    echo "--- Certificate Pinning ---"
    grep -rniE '(CertificatePinner|PinningTrustManager|checkServerTrusted|certificate)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20
} > "${ANALYSIS_DIR}/network.txt" 2>&1

echo "[+] Network analysis saved"

# ── 6. Sensitive data access ──────────────────────────
report_progress 6 $TOTAL_STEPS "Checking sensitive data access..."
{
    echo "=== SENSITIVE DATA ACCESS ==="

    echo ""
    echo "--- Clipboard ---"
    grep -rniE '(ClipboardManager|setPrimaryClip|getPrimaryClip)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

    echo ""
    echo "--- Contacts/SMS/Call Log ---"
    grep -rniE '(content://sms|content://contacts|content://call_log|Telephony\.Sms)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

    echo ""
    echo "--- Location ---"
    grep -rniE '(LocationManager|getLastKnownLocation|requestLocationUpdates|FusedLocationProvider)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

    echo ""
    echo "--- Keylogging / Accessibility ---"
    grep -rniE '(AccessibilityService|getWindows|performAction|FLAG_SECURE|KeyStore)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -20

    echo ""
    echo "--- Data Exfiltration ---"
    grep -rniE '(HttpURLConnection|OkHttpClient|Retrofit|Volley|URLConnection| openConnection)' "${SEARCH_DIRS[@]}" 2>/dev/null | head -30
} > "${ANALYSIS_DIR}/sensitive_data.txt" 2>&1

echo "[+] Sensitive data analysis saved"

# ── 7. Native binary strings ──────────────────────────
report_progress 7 $TOTAL_STEPS "Scanning native binary strings..."
NATIVE_DIR="${DECOMPILE_DIR}/native_libs"
if [ -d "$NATIVE_DIR" ]; then
    {
        echo "=== NATIVE LIBRARY ANALYSIS ==="
        find "$NATIVE_DIR" -name "*.so" | while read -r so; do
            so_name="$(basename "$so")"
            echo ""
            echo "--- $so_name ---"
            echo "  Size: $(du -h "$so" | awk '{print $1}')"
            echo "  Arch: $(file "$so")"
            echo ""
            echo "  Interesting strings:"
            strings "$so" | grep -iE '(http|api|key|secret|password|token|encrypt|decrypt|base64|socket|connect|ssl|tls|cert|jni|native)' | head -20
            echo ""
            echo "  Imported libs:"
            readelf -d "$so" 2>/dev/null | grep NEEDED | awk '{print "    " $NF}' || true
        done
    } > "${ANALYSIS_DIR}/native_strings.txt" 2>&1
    echo "[+] Native string analysis saved"
else
    echo "[~] No native libraries found"
fi

# ── 8. Smali dangerous patterns ───────────────────────
report_progress 8 $TOTAL_STEPS "Scanning smali patterns..."
SMALI_DIR="${DECOMPILE_DIR}/apktool_smali"
if [ -d "$SMALI_DIR" ]; then
    {
        echo "=== SMALI DANGEROUS PATTERNS ==="

        echo ""
        echo "--- Runtime.exec ---"
        grep -rn "Runtime.getRuntime" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- DexClassLoader (dynamic loading) ---"
        grep -rn "DexClassLoader\|PathClassLoader\|DexFile" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- Reflection ---"
        grep -rn "Ljava/lang/reflect" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- Native method calls ---"
        grep -rn "invoke.*native" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- Root detection ---"
        grep -rniE "(su |/system/app/Superuser|test-keys|RootBeer)" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- Debugger detection ---"
        grep -rniE "(isDebuggerConnected|Debug.isDebuggerConnected|ptrace)" "$SMALI_DIR" 2>/dev/null | head -20

        echo ""
        echo "--- Emulator detection ---"
        grep -rniE "(goldfish|generic|sdk_gphone|android_x86|nox|bluestacks)" "$SMALI_DIR" 2>/dev/null | head -20
    } > "${ANALYSIS_DIR}/smali_patterns.txt" 2>&1
    echo "[+] Smali pattern analysis saved"
else
    echo "[~] No smali directory found"
fi

set -e

# Clear progress line and show summary
printf "\r%70s\r" ""
echo ""
echo "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║  ANALYSIS COMPLETE                               ║${NC}"
echo "${GREEN}╠══════════════════════════════════════════════════╣${NC}"
echo "${GREEN}║${NC}  ${BOLD}Output:${NC} $ANALYSIS_DIR"
echo "${GREEN}║${NC}  ${BOLD}Files:${NC}  $(ls "$ANALYSIS_DIR"/*.txt 2>/dev/null | wc -l) analysis reports"
echo "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
