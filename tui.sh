#!/usr/bin/env bash
# tui.sh - Interactive TUI for APK pipeline
# Usage: tui.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# ── Colors ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── State ───────────────────────────────────────────────
SELECTED_PKGS=()
SELECTED_APKS=()
LAST_DECOMPILE_DIR=""
DEVICE_MODEL=""
DEVICE_SERIAL=""

# ── Helpers ─────────────────────────────────────────────
clear_screen() { clear; }

header() {
    clear_screen
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}APK Pipeline TUI${RESET}  ${DIM}v1.0.0${RESET}                                  ${CYAN}║${RESET}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${RESET}"
    if [ -n "$DEVICE_MODEL" ]; then
        echo -e "${CYAN}║${RESET}  ${GREEN}Device:${RESET} ${DEVICE_MODEL}  ${DIM}(${DEVICE_SERIAL})${RESET}                  ${CYAN}║${RESET}"
    fi
    if [ ${#SELECTED_PKGS[@]} -gt 0 ]; then
        echo -e "${CYAN}║${RESET}  ${YELLOW}Selected:${RESET} ${#SELECTED_PKGS[@]} package(s)                            ${CYAN}║${RESET}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

msg()  { echo -e "  ${GREEN}[+]${RESET} $1"; }
warn() { echo -e "  ${YELLOW}[~]${RESET} $1"; }
err()  { echo -e "  ${RED}[-]${RESET} $1"; }
info() { echo -e "  ${CYAN}[i]${RESET} $1"; }
ok()   { echo -e "  ${GREEN}[+]${RESET} $1"; }

pause() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

check_adb() {
    if [ -z "$ADB" ]; then
        err "adb not found"
        return 1
    fi
    if ! $ADB get-state >/dev/null 2>&1; then
        err "No device connected"
        return 1
    fi
    DEVICE_SERIAL=$($ADB get-serialno 2>/dev/null | tr -d '\r')
    DEVICE_MODEL=$($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    return 0
}

# ── Package Browser ─────────────────────────────────────
pkg_browser() {
    header
    echo -e "${BOLD}  Package Browser${RESET}"
    echo -e "  ${DIM}Select packages to analyze (TAB to select, ENTER to confirm)${RESET}"
    echo ""

    local pkg_type
    echo -e "  Package type:"
    pkg_type=$(echo -e "All\nSystem\nThird-party" | fzf --height=4 --reverse --border --prompt="Type> " || echo "All")

    local flag=""
    case "$pkg_type" in
        "System")       flag="-s" ;;
        "Third-party")  flag="-3" ;;
        *)              flag="" ;;
    esac

    local packages
    packages=$($ADB shell pm list packages -f $flag 2>/dev/null | tr -d '\r' | sed 's/package://' | sort)

    if [ -z "$packages" ]; then
        err "No packages found"
        pause
        return
    fi

    local count
    count=$(echo "$packages" | wc -l)
    info "Found $count packages"

    # pm list packages -f emits one field per line: /path/to/base.apk=com.pkg.name
    SELECTED_PKGS=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local pkg_name pkg_path
        pkg_path="${line%=*}"
        pkg_name="${line##*=}"
        [ -z "$pkg_name" ] && pkg_name="$(basename "$pkg_path" .apk)"
        SELECTED_PKGS+=("${pkg_path}|${pkg_name}")
    done < <(echo -e "$packages\nBack" | fzf --multi --height=70% --reverse --border \
        --exact \
        --delimiter='=' --nth=-1 --with-nth=-1 \
        --header="TAB=select  CTRL-A=select all  ENTER=confirm  Back=ESC or select Back  (search by package name)" \
        --prompt="Packages> " \
        --preview-window=right:50% \
        --preview="echo 'Path: {}'; echo '---'; pkg=\$(echo {} | sed 's/.*=//'); [ \"\$pkg\" = 'Back' ] && exit 0; echo \"Package: \$pkg\"; echo '---'; adb shell dumpsys package \$pkg 2>/dev/null | head -40" | grep -v '^Back$' || true)

    if [ ${#SELECTED_PKGS[@]} -eq 0 ]; then
        return
    else
        msg "${#SELECTED_PKGS[@]} package(s) selected"
    fi
    pause
}

# ── Pull Selected ────────────────────────────────────────
pull_selected() {
    header
    if [ ${#SELECTED_PKGS[@]} -eq 0 ]; then
        err "No packages selected. Go to Package Browser first."
        pause
        return
    fi

    echo -e "${BOLD}  Pulling ${#SELECTED_PKGS[@]} APK(s)...${RESET}"
    echo ""

    SELECTED_APKS=()
    for entry in "${SELECTED_PKGS[@]}"; do
        local pkg_path="${entry%%|*}"
        local pkg_name="${entry##*|}"

        local apk_name out_dir
        apk_name=$(basename "$pkg_path" .apk)
        out_dir="${OUTPUT_BASE}/${pkg_name}"
        mkdir -p "$out_dir"

        msg "Pulling $pkg_name ($apk_name)..."
        if $ADB pull "$pkg_path" "${out_dir}/${apk_name}.apk" 2>&1 | tail -1; then
            SELECTED_APKS+=("${out_dir}/${apk_name}.apk")
        else
            err "Failed to pull $pkg_name"
        fi
    done

    msg "Pulled ${#SELECTED_APKS[@]} APK(s)"
    pause
}

# ── Analyze APK ──────────────────────────────────────────
analyze_apk_tui() {
    header
    echo -e "${BOLD}  Select APK to analyze${RESET}"
    echo ""

    local apk_list
    if [ ${#SELECTED_APKS[@]} -gt 0 ]; then
        apk_list=$(printf '%s\n' "${SELECTED_APKS[@]}")
    else
        # Find APKs in output directory
        apk_list=$(find "${OUTPUT_BASE}" -name "*.apk" -type f 2>/dev/null | sort)
    fi

    if [ -z "$apk_list" ]; then
        err "No APKs found. Pull some first."
        pause
        return
    fi

    local chosen
    chosen=$(echo -e "$apk_list\n Back to main menu" | fzf --height=40% --reverse --border --prompt="APK> " \
        --preview="file '{}' 2>/dev/null && echo '---' && sha256sum '{}' 2>/dev/null && echo '---' && du -h '{}' 2>/dev/null")

    if [ -z "$chosen" ] || [ "$chosen" = "Back to main menu" ]; then
        return
    fi

    local apk_name
    apk_name=$(basename "$chosen" .apk)

    header
    echo -e "${BOLD}  Pipeline: ${apk_name}${RESET}"
    echo ""

    # What to run
    local stages
    stages=$(echo -e "quick|Quick Scan|Extract URLs & secrets only (grep, strings)\nfull|Full Analysis|Decompile + Secrets + Permissions + Report (jadx, apktool, grep)\ndecompile|Decompile Only|Convert APK to Smali/Java (apktool, jadx)\nanalyze|Analyze Only|Scan existing decompiled code (grep, regex)\nreport|Generate Report|Create Markdown/HTML summary from results\nback|Back|Return to main menu" | fzf --height=20 --reverse --border --prompt="Stage> █ " \
        --with-nth=1..2 \
        --delimiter="|" \
        --preview-window=down:3 \
        --preview='echo "Mode: {1}"; echo "Description: {2}"; echo "Tools: {3}"')

    case "$stages" in
        *back*|*"Back"*|"") return ;;
        *quick*)
            msg "Running quick scan (URLs + secrets)..."
            bash "${SCRIPT_DIR}/scripts/decompile.sh" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            local decompile_dir="${OUTPUT_BASE}/${apk_name}/decompile"
            bash "${SCRIPT_DIR}/scripts/analyze.sh" "$decompile_dir" "$chosen" quick 2>&1 | while IFS= read -r line; do echo "  $line"; done
            LAST_DECOMPILE_DIR="$decompile_dir"
            ok "URLs:    ${decompile_dir}/urls/"
            ok "Secrets: ${decompile_dir}/analysis/secrets.txt"
            ;;
        *full*)
            msg "Running full pipeline..."
            bash "${SCRIPT_DIR}/scripts/decompile.sh" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            local decompile_dir="${OUTPUT_BASE}/${apk_name}/decompile"
            bash "${SCRIPT_DIR}/scripts/analyze.sh" "$decompile_dir" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            bash "${SCRIPT_DIR}/scripts/report.sh" "$decompile_dir" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            LAST_DECOMPILE_DIR="$decompile_dir"
            ok "Report: ${decompile_dir}/REPORT.md"
            ok "Analysis: ${decompile_dir}/analysis/"
            ok "URLs: ${decompile_dir}/urls/"
            ;;
        *decompil*)
            msg "Decompiling..."
            bash "${SCRIPT_DIR}/scripts/decompile.sh" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            LAST_DECOMPILE_DIR="${OUTPUT_BASE}/${apk_name}/decompile"
            ;;
        *analyze*)
            local decompile_dir="${OUTPUT_BASE}/${apk_name}/decompile"
            if [ ! -d "$decompile_dir" ]; then
                err "Run decompile first"
                pause
                return
            fi
            msg "Analyzing..."
            bash "${SCRIPT_DIR}/scripts/analyze.sh" "$decompile_dir" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            LAST_DECOMPILE_DIR="$decompile_dir"
            ;;
        *report*)
            local decompile_dir="${OUTPUT_BASE}/${apk_name}/decompile"
            if [ ! -d "$decompile_dir" ]; then
                err "Run decompile first"
                pause
                return
            fi
            msg "Generating report..."
            bash "${SCRIPT_DIR}/scripts/report.sh" "$decompile_dir" "$chosen" 2>&1 | while IFS= read -r line; do echo "  $line"; done
            LAST_DECOMPILE_DIR="$decompile_dir"
            ;;
    esac
    pause
}

# ── URL Browser ──────────────────────────────────────────
url_browser() {
    header
    echo -e "${BOLD}  URL / Domain Browser${RESET}"
    echo ""

    # Find decompiled dirs with URL output
    local url_dirs
    url_dirs=$(find "${OUTPUT_BASE}" -path "*/urls/*_urls.txt" -type f 2>/dev/null | sort)

    if [ -z "$url_dirs" ]; then
        err "No URL data found. Run analysis first."
        pause
        return
    fi

    local chosen_file
    chosen_file=$(echo -e "$url_dirs\n Back" | fzf --height=40% --reverse --border --prompt="URL file> " \
        --preview="head -50 '{}' 2>/dev/null")

    if [ -z "$chosen_file" ] || [ "$chosen_file" = "Back" ]; then
        return
    fi

    local dir_name
    dir_name=$(dirname "$chosen_file")
    local base
    base=$(basename "$chosen_file" _urls.txt)

    while true; do
        header
        echo -e "${BOLD}  URLs: ${base}${RESET}"
        echo ""

        local action
        action=$(echo -e "View all URLs\nView unique domains\nView IPs\nSearch URLs\nExport selected\nBack" | fzf --height=30% --reverse --border --prompt="Action> ")

        case "$action" in
            "View all URLs")
                header
                echo -e "${BOLD}  All URLs (${base})${RESET}"
                echo ""
                cat "$chosen_file" | fzf --multi --height=70% --reverse --border \
                    --header="TAB=select  ENTER=confirm" \
                    --prompt="URLs> " \
                    --preview-window=right:40% \
                    --preview="echo '{}' | grep -oE 'https?://[^ ]+' | head -1 | xargs -I{} curl -sI -m 5 {} 2>/dev/null | head -10 || echo 'Preview not available'"
                ;;
            "View unique domains")
                header
                echo -e "${BOLD}  Unique Domains${RESET}"
                echo ""
                cat "${dir_name}/${base}_domains.txt" 2>/dev/null | fzf --height=60% --reverse --border \
                    --prompt="Domains> " \
                    --preview="grep -c '{1}' ${dir_name}/${base}_urls.txt 2>/dev/null || echo '0 hits' && echo '---' && grep '{1}' ${dir_name}/${base}_urls.txt 2>/dev/null | head -5"
                ;;
            "View IPs")
                header
                echo -e "${BOLD}  IP Addresses${RESET}"
                echo ""
                cat "${dir_name}/${base}_ips.txt" 2>/dev/null | fzf --height=60% --reverse --border \
                    --prompt="IPs> " \
                    --preview="whois {} 2>/dev/null | head -15 || echo 'whois not available'"
                ;;
            "Search URLs")
                header
                echo -e "${BOLD}  Search${RESET}"
                echo ""
                local query
                query=$(echo "" | fzf --height=10 --reverse --border --prompt="Search> ")
                if [ -n "$query" ]; then
                    local results
                    results=$(grep -i "$query" "$chosen_file" 2>/dev/null)
                    if [ -n "$results" ]; then
                        echo "$results" | fzf --multi --height=60% --reverse --border \
                            --prompt="Results> " \
                            --preview="echo 'Full URL: {}'"
                    else
                        warn "No matches"
                    fi
                fi
                ;;
            "Export selected")
                local export_file="${dir_name}/${base}_selected_urls.txt"
                cat "$chosen_file" | fzf --multi --height=60% --reverse --border \
                    --prompt="Select to export> " > "$export_file" 2>/dev/null
                local exp_count
                exp_count=$(wc -l < "$export_file")
                msg "Exported $exp_count URLs to $export_file"
                ;;
            "Back")
                return
                ;;
        esac
    done
}

# ── Analysis Browser ─────────────────────────────────────
analysis_browser() {
    header
    echo -e "${BOLD}  Analysis Results Browser${RESET}"
    echo ""

    local decompile_dirs
    decompile_dirs=$(find "${OUTPUT_BASE}" -name "analysis" -type d 2>/dev/null | sort)

    if [ -z "$decompile_dirs" ]; then
        err "No analysis results found."
        pause
        return
    fi

    local chosen_dir
    chosen_dir=$(echo -e "$decompile_dirs\nBack" | fzf --height=40% --reverse --border --prompt="App> " \
        --preview="ls '{}' 2>/dev/null")

    if [ -z "$chosen_dir" ] || [ "$chosen_dir" = "Back" ]; then
        return
    fi

    while true; do
        header
        local app_name
        app_name=$(basename "$(dirname "$chosen_dir")")
        echo -e "${BOLD}  Analysis: ${app_name}${RESET}"
        echo ""

        local view
        view=$(echo -e "Permissions\nSecrets & API Keys\nYARA Hits\nCrypto Patterns\nNetwork Config\nSensitive Data\nSmali Patterns\nNative Strings\nOpen Report\nBack" | fzf --height=40% --reverse --border --prompt="View> ")

        local file=""
        case "$view" in
            "Permissions")        file="${chosen_dir}/permissions.txt" ;;
            "Secrets"*)           file="${chosen_dir}/secrets.txt" ;;
            "YARA"*)              file="${chosen_dir}/yara_hits.txt" ;;
            "Crypto"*)            file="${chosen_dir}/crypto.txt" ;;
            "Network"*)           file="${chosen_dir}/network.txt" ;;
            "Sensitive"*)         file="${chosen_dir}/sensitive_data.txt" ;;
            "Smali"*)             file="${chosen_dir}/smali_patterns.txt" ;;
            "Native"*)            file="${chosen_dir}/native_strings.txt" ;;
            "Open Report")
                local report
                report=$(dirname "$chosen_dir")/REPORT.md
                if [ -f "$report" ]; then
                    $PAGER "$report" 2>/dev/null || cat "$report"
                else
                    err "No report found"
                fi
                ;;
            "Back")               return ;;
        esac

        if [ -n "$file" ] && [ -f "$file" ]; then
            header
            echo -e "${BOLD}  $view${RESET}"
            echo ""
            cat "$file" | fzf --height=80% --reverse --border --prompt="$view> " \
                --preview-window=right:50% --preview="echo '{}'" || true
        elif [ -n "$file" ]; then
            warn "File not found: $file"
        fi
    done
}

# ── Batch Mode ───────────────────────────────────────────
batch_tui() {
    header
    echo -e "${BOLD}  Batch Mode${RESET}"
    echo ""

    local input
    echo -e "  Source:"
    local source_type
    source_type=$(echo -e "Directory of APKs\nDevice (all third-party)\nDevice (all)\nBack" | fzf --height=12 --reverse --border --prompt="Source> ")

    case "$source_type" in
        "Back"|"") return ;;
        "Directory"*)
            input=$(find / -maxdepth 4 -name "*.apk" -type f 2>/dev/null | head -50 | fzf --height=40% --reverse --border --prompt="Directory> " \
                --preview="ls '{}' 2>/dev/null || file '{}'")
            if [ -z "$input" ]; then
                return
            fi
            input=$(dirname "$input")
            ;;
        "Device (all third-party)")
            if ! check_adb; then pause; return; fi
            msg "Pulling third-party APKs from device..."
            input="${OUTPUT_BASE}/device_batch_$(date +%s)"
            mkdir -p "$input"
            local _pulled=0
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local _path="${line%=*}" _pkg="${line##*=}"
                local _name="$(basename "$_path" .apk)"
                if $ADB pull "$_path" "${input}/${_pkg}_${_name}.apk" >/dev/null 2>&1; then
                    ((_pulled++)) || true
                fi
            done < <($ADB shell pm list packages -f -3 2>/dev/null | tr -d '\r' | sort)
            info "Pulled $_pulled APKs to $input"
            ;;
        "Device (all)")
            if ! check_adb; then pause; return; fi
            msg "Pulling all APKs from device..."
            input="${OUTPUT_BASE}/device_batch_$(date +%s)"
            mkdir -p "$input"
            local _pulled=0
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local _path="${line%=*}" _pkg="${line##*=}"
                local _name="$(basename "$_path" .apk)"
                if $ADB pull "$_path" "${input}/${_pkg}_${_name}.apk" >/dev/null 2>&1; then
                    ((_pulled++)) || true
                fi
            done < <($ADB shell pm list packages -f 2>/dev/null | tr -d '\r' | sort)
            info "Pulled $_pulled APKs to $input"
            ;;
    esac

    if [ -z "$input" ]; then
        return
    fi

    local workers
    workers=$(echo -e "1\n2\n4\n8\nBack" | fzf --height=9 --reverse --border --prompt="Workers> " || echo "Back")
    [ "$workers" = "Back" ] && return

    header
    msg "Starting batch with $workers workers..."
    bash "${SCRIPT_DIR}/scripts/batch.sh" "$input" "$workers"
    pause
}

# ── Delete Output ────────────────────────────────────────
delete_output() {
    header
    echo -e "${BOLD}  Delete Output${RESET}"
    echo ""

    if [ ! -d "${OUTPUT_BASE}" ]; then
        err "No output directory yet (${OUTPUT_BASE})"
        pause
        return
    fi

    local targets
    targets=$(find "${OUTPUT_BASE}" -mindepth 1 -maxdepth 2 2>/dev/null | sort)
    if [ -z "$targets" ]; then
        info "Output directory is empty"
        pause
        return
    fi

    local chosen
    chosen=$(echo -e "$targets\nBack" | fzf --multi --height=50% --reverse --border \
        --header="TAB=select  CTRL-A=select all  ENTER=continue  (multi-delete enabled)" --prompt="Delete> " \
        --preview='if [ -d {} ]; then echo "Total size:"; du -sh {} 2>/dev/null; echo ""; find {} -maxdepth 1 | head -20; else echo "File: {}"; fi')

    if [ -z "$chosen" ] || [ "$chosen" = "Back" ]; then
        return
    fi

    header
    echo -e "${BOLD}  Confirm delete${RESET}"
    echo ""
    local _total
    _total=0
    echo "$chosen" | while IFS= read -r item; do
        printf '  %s\n' "$item"
    done
    _total=$(echo "$chosen" | grep -cv '^$' || true)
    echo ""
    if command -v du >/dev/null 2>&1; then
        local _size
        _size=$(echo "$chosen" | tr '\n' '\0' | du -sch --files0-from=- 2>/dev/null | tail -1 | cut -f1)
        [ -n "$_size" ] && echo -e "  ${DIM}Total size to free: ${_size} (${_total} item(s))${RESET}"
    fi
    echo ""
    local ans
    echo -e -n "  Delete these ${RED}(y/N)${RESET}? "
    read -r ans
    case "${ans,,}" in
        y|yes)
            local _deleted=0
            while IFS= read -r item; do
                [ -z "$item" ] && continue
                if rm -rf "$item" 2>/dev/null; then
                    info "Deleted $item"
                    ((_deleted++)) || true
                else
                    err "Failed to delete $item"
                fi
            done <<< "$chosen"
            ok "Deleted $_deleted item(s)"
            ;;
        *) info "Cancelled" ;;
    esac
    pause
}

# ── Main Menu ────────────────────────────────────────────
main_menu() {
    # Check ADB on start
    if check_adb; then
        msg "Connected: $DEVICE_MODEL ($DEVICE_SERIAL)"
    else
        warn "No device connected (pull/adb features unavailable)"
    fi
    sleep 1

    while true; do
        header

        echo -e "${BOLD}  Main Menu${RESET}"
        echo -e "  ${DIM}─────────────────────────────────${RESET}"
        echo ""

        local choice
        choice=$(echo -e " Package Browser   \${DIM}Browse & select APKs from device\${RESET}\n Pull APKs         \${DIM}Download selected packages\${RESET}\n Analyze APK       \${DIM}Run decompile + analysis pipeline\${RESET}\n URL Browser       \${DIM}View extracted URLs & domains\${RESET}\n Analysis Browser  \${DIM}Browse analysis results\${RESET}\n Batch Mode        \${DIM}Process multiple APKs\${RESET}\n Delete Output     \${DIM}Remove pulled APKs / decompile results\${RESET}\n Check Tools       \${DIM}Verify tool availability\${RESET}\n Quit" | envsubst | fzf --height=50% --reverse --border --no-multi --prompt="> " \
            --header="Use arrow keys or type to filter" | awk '{print $1}')

        case "$choice" in
            "Package")    pkg_browser ;;
            "Pull")       pull_selected ;;
            "Analyze")    analyze_apk_tui ;;
            "URL")        url_browser ;;
            "Analysis")   analysis_browser ;;
            "Batch")      batch_tui ;;
            "Delete")     delete_output ;;
            "Check")
                header
                bash "${SCRIPT_DIR}/apk-pipeline.sh" check
                pause
                ;;
            "Quit"|"")    clear_screen; exit 0 ;;
        esac
    done
}

# ── Entry ────────────────────────────────────────────────
trap 'clear_screen; exit 0' INT TERM

if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required. Install: sudo apt install fzf"
    exit 1
fi

export PAGER="${PAGER:-less}"
main_menu
