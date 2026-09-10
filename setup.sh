#!/usr/bin/env bash
# setup.sh - Install all dependencies for apk-pipeline
# Usage: sudo bash setup.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════╗"
echo "║  APK Pipeline - Dependency Setup                 ║"
echo "╚══════════════════════════════════════════════════╝"

echo "[1/4] System packages..."
apt-get update -qq
apt-get install -y -qq \
    jadx apktool aapt apksigner zipalign \
    adb android-tools-adb \
    radare2 \
    dex2jar \
    yara \
    ssdeep libfuzzy-dev \
    exiftool \
    libxml2-utils \
    2>&1 | tail -3

echo "[2/4] Python packages..."
pip3 install --break-system-packages androguard frida-tools 2>&1 | tail -3

echo "[3/4] apk2url..."
if ! command -v apk2url >/dev/null 2>&1; then
    git clone https://github.com/n0mi1k/apk2url.git /opt/apk2url 2>/dev/null || true
    chmod +x /opt/apk2url/apk2url.sh 2>/dev/null || true
    ln -sf /opt/apk2url/apk2url.sh /usr/local/bin/apk2url 2>/dev/null || true
fi

echo "[4/4] Configuring pipeline..."
chmod +x "${SCRIPT_DIR}/apk-pipeline.sh"
chmod +x "${SCRIPT_DIR}/scripts/"*.sh

echo ""
echo "[+] Setup complete. Run: ./apk-pipeline.sh check"
