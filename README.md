# APK Pipeline

Automated Android APK reverse engineering pipeline. Decompiles, analyzes, and reports on APKs using multiple engines and security analysis tools.

## Quick Start

```bash
# Interactive TUI (browse device packages, pull, analyze, browse URLs)
./apk-pipeline.sh tui

# Check available tools
./apk-pipeline.sh check

# Full pipeline on a single APK
./apk-pipeline.sh full app.apk

# Pull from device and analyze
./apk-pipeline.sh pull --pkg com.example.app
./apk-pipeline.sh full output/com.example.app/apk_name.apk

# Batch process a directory of APKs
./apk-pipeline.sh batch ./apks/ --concurrency 4
```

## Pipeline Stages

```
APK Input
    │
    ├── 1. Decompile ──────────────────────────────────────
    │   ├── aapt          metadata, permissions, manifest
    │   ├── apktool       smali bytecode + resources
    │   ├── jadx          Java/Kotlin sources (deobfuscated)
    │   ├── dex2jar       JAR conversion
    │   ├── apk2url       URL/domain/IP extraction
    │   ├── radare2       native .so string analysis
    │   └── exiftool      file metadata
    │
    ├── 2. Analyze ────────────────────────────────────────
    │   ├── YARA          pattern/rule matching (8 rules)
    │   ├── permissions   dangerous permission combos
    │   ├── secrets       API keys, passwords, tokens
    │   ├── crypto        weak/hardcoded crypto patterns
    │   ├── network       cleartext, trust managers
    │   ├── sensitive     clipboard, contacts, location
    │   ├── smali         root/debug/emu detection
    │   └── native        .so imports and strings
    │
    └── 3. Report ─────────────────────────────────────────
        └── REPORT.md    consolidated markdown report
```

## Commands

| Command | Description |
|---------|-------------|
| `tui` | Launch interactive TUI (fzf-based) |
| `pull` | Extract APKs from connected Android device via ADB |
| `decompile` | Decompile APK with all engines |
| `analyze` | Run deep static analysis on decompiled output |
| `report` | Generate markdown report |
| `quick` | Fast scan — URLs + secrets only (skips full analysis) |
| `full` | Run all stages (decompile + analyze + report) |
| `batch` | Process multiple APKs from directory or list |
| `check` | Show tool availability status |

### Interactive TUI

```bash
./apk-pipeline.sh tui
```

The TUI provides:
- **Package Browser** — list device packages (all/system/third-party), multi-select with fzf, live preview of `dumpsys package` info
- **Pull APKs** — download selected packages via ADB
- **Analyze APK** — pick decompile/analyze/report stages interactively
- **URL Browser** — browse extracted URLs, unique domains, IPs (with whois preview), search, export selections
- **Analysis Browser** — view permissions, secrets, YARA hits, crypto, network, smali patterns, native strings
- **Batch Mode** — run batch pipeline from directory or device

### Pull from device

```bash
./apk-pipeline.sh pull --list                    # List installed packages
./apk-pipeline.sh pull --pkg com.example.app     # Pull specific package
./apk-pipeline.sh pull --all                     # Pull all third-party APKs
./apk-pipeline.sh pull --split com.example.app   # Pull split APKs (AAB)
```

### Single APK

```bash
./apk-pipeline.sh decompile app.apk              # Decompile only
./apk-pipeline.sh analyze output/app/decompile   # Analyze only
./apk-pipeline.sh report output/app/decompile    # Report only
./apk-pipeline.sh full app.apk                   # Everything
```

### Batch mode

```bash
./apk-pipeline.sh batch ./apks/                  # Sequential
./apk-pipeline.sh batch ./apks/ 4                # 4 workers
echo -e "app1.apk\napp2.apk" > list.txt
./apk-pipeline.sh batch list.txt
```

## Output Structure

```
output/
└── <app_name>/
    └── decompile/
        ├── manifest.json          # Metadata
        ├── REPORT.md              # Final report
        ├── jadx_sources/          # Java/Kotlin code
        ├── apktool_smali/         # Smali + resources
        ├── dex2jar/               # JAR files
        ├── urls/                  # Extracted URLs, IPs, domains
        ├── native_libs/           # Extracted .so files
        ├── metadata/              # aapt, exiftool, ssdeep
        └── analysis/
            ├── yara_hits.txt
            ├── permissions.txt
            ├── secrets.txt
            ├── crypto.txt
            ├── network.txt
            ├── sensitive_data.txt
            ├── smali_patterns.txt
            └── native_strings.txt
```

## Tools Used

| Tool | Purpose |
|------|---------|
| [jadx](https://github.com/skylot/jadx) | Java/Kotlin decompiler with deobfuscation |
| [apktool](https://apktool.org/) | Smali disassembly + resource decoding |
| [apk2url](https://github.com/n0mi1k/apk2url) | URL/domain/IP extraction |
| [radare2](https://r2.re/) | Native binary analysis |
| [frida](https://frida.re/) | Dynamic instrumentation |
| [yara](https://virustotal.github.io/yara/) | Pattern matching rules |
| [androguard](https://github.com/androguard/androguard) | Python APK analysis |
| [aapt](https://developer.android.com/studio/command-line/aapt) | Android asset tool |
| [ssdeep](https://ssdeep-project.org/) | Fuzzy hashing |

## Requirements

- Linux (tested on Kali)
- Java 11+ (for jadx, apktool)
- Android SDK tools (aapt, adb, apksigner, zipalign)
- Python 3.10+ (androguard, frida-tools)

Run `setup.sh` to install everything: `sudo bash setup.sh`
