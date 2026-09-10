#!/usr/bin/env bash
# decompile.sh - Decompile APK with jadx, apktool, dex2jar, and apk2url
# Usage: decompile.sh <apk_file> [output_dir]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

APK_FILE="${1:-}"
OUTPUT_DIR="${2:-}"
PROGRESS_CALLBACK="${3:-}"  # Optional: command to call for progress updates

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

if [ -z "$APK_FILE" ]; then
    echo "Usage: $(basename "$0") <apk_file> [output_dir]"
    exit 1
fi

if [ ! -f "$APK_FILE" ]; then
    echo "[-] File not found: $APK_FILE"
    exit 1
fi

BASENAME="$(basename "$APK_FILE" .apk)"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="${OUTPUT_BASE}/${BASENAME}/decompile"
mkdir -p "$OUTPUT_DIR"

JADX_DIR="${OUTPUT_DIR}/jadx_sources"
APKTOOL_DIR="${OUTPUT_DIR}/apktool_smali"
DEX2JAR_DIR="${OUTPUT_DIR}/dex2jar"
URLS_DIR="${OUTPUT_DIR}/urls"
NATIVE_DIR="${OUTPUT_DIR}/native_libs"
META_DIR="${OUTPUT_DIR}/metadata"

# extract_so_files <apk> <dest_dir>
#   Extract all *.so from an APK, or from every inner APK of an App Bundle
#   (.apks/.xapk/.apkm). Writes each extracted .so path to stdout.
extract_so_files() {
    local apk="$1" dest="$2"
    mkdir -p "$dest"
    case "${apk##*.}" in
        apks|xapk|apkm)
            while IFS= read -r inner; do
                [ -z "$inner" ] && continue
                unzip -o -q "$apk" "$inner" -d "$dest" 2>/dev/null || true
            done < <(unzip -Z1 "$apk" 2>/dev/null | grep -E '\.apk$' || true)
            while IFS= read -r inner_apk; do
                [ -f "$inner_apk" ] || continue
                unzip -o -q "$inner_apk" 'lib/*' -d "$dest" 2>/dev/null || true
            done < <(find "$dest" -maxdepth 1 -name '*.apk' 2>/dev/null || true)
            ;;
        *)
            unzip -o -q "$apk" 'lib/*' -d "$dest" 2>/dev/null || true
            ;;
    esac
    find "$dest" -name '*.so' -type f 2>/dev/null || true
}

echo "╔══════════════════════════════════════════════════╗"
echo "║         APK DECOMPILE PIPELINE                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo "[+] Target: $APK_FILE"
echo "[+] SHA256: $(sha256sum "$APK_FILE" | awk '{print $1}')"
echo "[+] Size:   $(du -h "$APK_FILE" | awk '{print $1}')"
echo "[+] Output: $OUTPUT_DIR"
echo ""

TOTAL_STEPS=6

# ── 1. Metadata extraction ─────────────────────────────
report_progress 1 $TOTAL_STEPS "Extracting metadata..."
mkdir -p "$META_DIR"

# Basic file info
file "$APK_FILE" > "${META_DIR}/file_type.txt"

# aapt dump
if [ -n "$AAPT" ]; then
    echo "[+] aapt: dumping manifest & permissions"
    $AAPT dump badging "$APK_FILE" > "${META_DIR}/badging.txt" 2>&1 || true
    $AAPT dump xmltree "$APK_FILE" AndroidManifest.xml > "${META_DIR}/manifest_xmltree.txt" 2>&1 || true
    $AAPT dump permissions "$APK_FILE" > "${META_DIR}/permissions.txt" 2>&1 || true
fi

# exiftool
if [ -n "$EXIFTOOL" ]; then
    $EXIFTOOL "$APK_FILE" > "${META_DIR}/exiftool.txt" 2>&1 || true
fi

# ssdeep fuzzy hash
if [ -n "$SSDEEP" ]; then
    $SSDEEP "$APK_FILE" > "${META_DIR}/ssdeep.txt" 2>&1 || true
fi

echo "[+] Metadata saved"

# ── 2. APKTool (smali + resources) ────────────────────
report_progress 2 $TOTAL_STEPS "Decompiling with APKTool..."
if [ -n "$APKTOOL" ]; then
    mkdir -p "$APKTOOL_DIR"
    $APKTOOL d "$APK_FILE" -o "$APKTOOL_DIR" -f 2>&1 | tail -3 || true
    echo "[+] Smali + resources: $APKTOOL_DIR"

    # Count smali files
    smali_count=$(find "$APKTOOL_DIR" -name "*.smali" 2>/dev/null | wc -l)
    echo "[+] Smali files: $smali_count"
else
    echo "[-] apktool not found, skipping"
fi

# ── 3. JADX (Java/Kotlin sources) ─────────────────────
report_progress 3 $TOTAL_STEPS "Decompiling with JADX..."
if [ -n "$JADX" ]; then
    mkdir -p "$JADX_DIR"
    jadx_flags="--deobf"
    [ "$DECOMPILE_RESOURCES" = "false" ] && jadx_flags="$jadx_flags --no-res"
    $JADX -d "$JADX_DIR" $jadx_flags "$APK_FILE" 2>&1 | tail -3 || true

    java_count=$(find "$JADX_DIR" -name "*.java" 2>/dev/null | wc -l)
    kt_count=$(find "$JADX_DIR" -name "*.kt" 2>/dev/null | wc -l)
    echo "[+] Java files: $java_count | Kotlin files: $kt_count"
else
    echo "[-] jadx not found, skipping"
fi

# ── 4. dex2jar ────────────────────────────────────────
report_progress 4 $TOTAL_STEPS "Converting with dex2jar..."
if [ -n "$D2J_DEX2JAR" ]; then
    mkdir -p "$DEX2JAR_DIR"
    $D2J_DEX2JAR -f -o "${DEX2JAR_DIR}/${BASENAME}.jar" "$APK_FILE" 2>&1 | tail -2 || true
    [ -f "${DEX2JAR_DIR}/${BASENAME}.jar" ] && echo "[+] JAR: ${DEX2JAR_DIR}/${BASENAME}.jar"
else
    echo "[-] dex2jar not found, skipping"
fi

# ── 5. apk2url (URL/domain/IP extraction) ──────────────
report_progress 5 $TOTAL_STEPS "Extracting URLs with apk2url..."
if [ -z "$APK2URL" ] && [ "$APK2URL_MODE" = "binary" ]; then
    echo "[-] apk2url binary not found, falling back to fast extract"
    APK2URL_MODE="fast"
fi

mkdir -p "$URLS_DIR"

case "$APK2URL_MODE" in
    "binary")
        # Run the actual apk2url tool. It re-decompiles with apktool+jadx
        # into <name>-decompiled and writes endpoints into ./endpoints/.
        scratch="${OUTPUT_DIR}/_apk2url_work"
        rm -rf "$scratch"
        mkdir -p "$scratch"
        pushd "$scratch" >/dev/null 2>&1 || exit 1

        timeout "${APK2URL_TIMEOUT}" "$APK2URL" "$APK_FILE" </dev/null >/dev/null 2>&1 || true

        if [ -d "${scratch}/endpoints" ]; then
            ep_file="${scratch}/endpoints/${BASENAME}_endpoints.txt"
            [ -f "$ep_file" ] && cp "$ep_file" "${URLS_DIR}/${BASENAME}_urls.txt"
            [ -f "${scratch}/endpoints/${BASENAME}_uniqurls.txt" ] && cp "${scratch}/endpoints/${BASENAME}_uniqurls.txt" "${URLS_DIR}/${BASENAME}_uniqurls.txt"
        fi
        popd >/dev/null 2>&1 || true
        rm -rf "$scratch"
        ;;
    *)
        # Fast mode: apply apk2url's extraction logic to our own output.
        # No redundant decompile, same regexes, instant.
        SRC_DIRS=()
        [ -d "$JADX_DIR" ] && SRC_DIRS+=("$JADX_DIR")
        [ -d "$APKTOOL_DIR" ] && SRC_DIRS+=("$APKTOOL_DIR")

        URL_RE='(\b(https?)://|www\.)[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]'

        if command -v rg >/dev/null 2>&1; then
            rg -IooN --no-filename -g '*.java' -g '*.kt' -g '*.smali' -g '*.xml' -g '*.json' -g '*.properties' -g '*.txt' "$URL_RE" "${SRC_DIRS[@]}" 2>/dev/null \
                | sort -u > "${URLS_DIR}/${BASENAME}_urls.txt" || true
        else
            grep -rIoE "$URL_RE" "${SRC_DIRS[@]}" 2>/dev/null \
                | sed 's/^[^:]*://' | sort -u > "${URLS_DIR}/${BASENAME}_urls.txt" || true
        fi

        # Pull scheme/domain/host portion into uniq urls
        grep -oE '((http|https)://[^/]+)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
            | sort -u > "${URLS_DIR}/${BASENAME}_uniqurls.txt" || true
        grep -E '^www\.' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null | sort -u >> "${URLS_DIR}/${BASENAME}_uniqurls.txt" || true

        # Raw IPs
        grep -oE '((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
            | sort -u > "${URLS_DIR}/${BASENAME}_ips.txt" || true

        # Split unique domains from urls
        grep -oE '((http|https)://[^/]+)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
            | awk -F/ '{print $1 "//" $3}' | sort -u > "${URLS_DIR}/${BASENAME}_domains.txt" || true
        grep -E '^www\.' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null | sort -u >> "${URLS_DIR}/${BASENAME}_domains.txt" || true

        # Native binary strings: Flutter/Dart apps compile their logic into
        # libapp.so (+ libflutter.so), invisible to java/kt/smali greps.
        # Extract .so files and run `strings` to catch URLs/IPs/domains in
        # the compiled snapshot. Handles single .apk and .apks App Bundles.
        if [ "$EXTRACT_NATIVE_LIBS" = "true" ]; then
            echo "[+] Native binary string scan (libapp.so / Dart snapshot)..."
            native_scan="${URLS_DIR}/_native_scan"
            native_strings_file="${URLS_DIR}/${BASENAME}_native_strings.txt"
            : > "$native_strings_file"

            while IFS= read -r so; do
                strings -n 6 "$so" 2>/dev/null
            done < <(extract_so_files "$APK_FILE" "$native_scan") >> "$native_strings_file" || true
            rm -rf "$native_scan"

            if [ -s "$native_strings_file" ]; then
                grep -oE "$URL_RE" "$native_strings_file" 2>/dev/null \
                    >> "${URLS_DIR}/${BASENAME}_urls.txt" || true
                sort -u -o "${URLS_DIR}/${BASENAME}_urls.txt" "${URLS_DIR}/${BASENAME}_urls.txt"

                # Regenerate derived lists from the merged set so native hits
                # are reflected in uniqurls/ips/domains too.
                grep -oE '((http|https)://[^/]+)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
                    | sort -u > "${URLS_DIR}/${BASENAME}_uniqurls.txt" || true
                grep -E '^www\.' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null | sort -u >> "${URLS_DIR}/${BASENAME}_uniqurls.txt" || true

                grep -oE '((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
                    | sort -u > "${URLS_DIR}/${BASENAME}_ips.txt" || true

                grep -oE '((http|https)://[^/]+)' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null \
                    | awk -F/ '{print $1 "//" $3}' | sort -u > "${URLS_DIR}/${BASENAME}_domains.txt" || true
                grep -E '^www\.' "${URLS_DIR}/${BASENAME}_urls.txt" 2>/dev/null | sort -u >> "${URLS_DIR}/${BASENAME}_domains.txt" || true

                native_url_count=$(grep -oE "$URL_RE" "$native_strings_file" 2>/dev/null | wc -l || echo 0)
                echo "[+] Native strings: $native_url_count URL(s) found"
                echo "    native strings: $native_strings_file"
            else
                echo "[~] No URLs in native binaries"
                rm -f "$native_strings_file"
            fi
        fi
        ;;
esac

# ── Post-process: counts + fallback clean ─────────────
if [ -f "${URLS_DIR}/${BASENAME}_urls.txt" ]; then
    url_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_urls.txt" || true); url_count=${url_count:-0}
    ip_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_ips.txt" 2>/dev/null || true); ip_count=${ip_count:-0}
    domain_count=$(grep -cv '^$' "${URLS_DIR}/${BASENAME}_domains.txt" 2>/dev/null || true); domain_count=${domain_count:-0}
    echo "[+] Endpoints: $url_count URLs | $domain_count domains | $ip_count IPs"
else
    echo "[~] No endpoints extracted"
fi

# ── 6. Extract native libraries ───────────────────────
report_progress 6 $TOTAL_STEPS "Extracting native libraries..."
if [ "$EXTRACT_NATIVE_LIBS" = "true" ]; then
    mkdir -p "$NATIVE_DIR"

    # From apktool output
    if [ -d "$APKTOOL_DIR/lib" ]; then
        cp -r "$APKTOOL_DIR/lib/"* "$NATIVE_DIR/" 2>/dev/null || true
    fi

    # Extract directly from APK (helper handles .apks/.xapk/.apkm bundles)
    scratch="${OUTPUT_DIR}/_lib_extract"
    rm -rf "$scratch"
    mkdir -p "$scratch"
    while IFS= read -r so; do
        rel="${so#*lib/}"
        mkdir -p "$(dirname "${NATIVE_DIR}/${rel}")"
        cp "$so" "${NATIVE_DIR}/${rel}" 2>/dev/null || true
    done < <(extract_so_files "$APK_FILE" "$scratch")
    rm -rf "$scratch"

    so_count=$(find "$NATIVE_DIR" -name "*.so" 2>/dev/null | wc -l || true)
    echo "[+] Native .so files: $so_count"

    # Quick r2 analysis on each .so
    if [ -n "$R2" ] && [ "$so_count" -gt 0 ]; then
        echo "[+] Running radare2 info on .so files..."
        find "$NATIVE_DIR" -name "*.so" | while read -r so; do
            so_name=$(basename "$so")
            $R2 -q -c "aaa; afl; iz~http" "$so" 2>/dev/null > "${NATIVE_DIR}/${so_name}.r2_strings.txt" || true
        done
    fi
fi

# Clear progress line and show summary
printf "\r%70s\r" ""
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  DECOMPILE COMPLETE                              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  jadx sources:  $JADX_DIR"
echo "║  apktool smali: $APKTOOL_DIR"
echo "║  dex2jar:       $DEX2JAR_DIR"
echo "║  urls/domains:  $URLS_DIR"
echo "║  native libs:   $NATIVE_DIR"
echo "║  metadata:      $META_DIR"
echo "╚══════════════════════════════════════════════════╝"

# Write decompile manifest
cat > "${OUTPUT_DIR}/manifest.json" <<EOJSON
{
    "apk": "$(basename "$APK_FILE")",
    "sha256": "$(sha256sum "$APK_FILE" | awk '{print $1}')",
    "size": "$(stat -c%s "$APK_FILE" 2>/dev/null || stat -f%z "$APK_FILE" 2>/dev/null)",
    "jadx_dir": "$JADX_DIR",
    "apktool_dir": "$APKTOOL_DIR",
    "dex2jar_dir": "$DEX2JAR_DIR",
    "urls_dir": "$URLS_DIR",
    "native_dir": "$NATIVE_DIR",
    "metadata_dir": "$META_DIR"
}
EOJSON

echo "[+] Manifest: ${OUTPUT_DIR}/manifest.json"
