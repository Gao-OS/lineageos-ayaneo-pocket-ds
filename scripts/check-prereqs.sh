#!/usr/bin/env bash
set -euo pipefail

# check-prereqs.sh — Verify the build environment is properly configured
# Run this before starting a LineageOS build to catch missing dependencies early.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { printf "${GREEN}[OK]${RESET}   %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${RESET} %s\n" "$*"; FAILED=$((FAILED + 1)); }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; WARNINGS=$((WARNINGS + 1)); }
info() { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }

FAILED=0
WARNINGS=0

echo ""
printf "${BOLD}LineageOS 21 — Ayaneo Pocket DS Build Prerequisites Check${RESET}\n"
echo "──────────────────────────────────────────────────────────"
echo ""

# ── 1. Nix devenv shell ───────────────────────────────────────────────────────
info "Checking devenv shell..."
if [[ -n "${DEVENV_ROOT:-}" ]]; then
    ok "Running inside devenv shell (DEVENV_ROOT=$DEVENV_ROOT)"
else
    warn "Not inside devenv shell — run 'devenv shell' first for reproducible builds"
fi

# ── 2. Java ───────────────────────────────────────────────────────────────────
info "Checking Java..."
if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1)
    if echo "$java_ver" | grep -q "17\|openjdk 17"; then
        ok "Java 17: $java_ver"
    else
        warn "Java version may not be 17: $java_ver (Android 14 requires JDK 17)"
    fi
else
    fail "java not found — install JDK 17 or run inside devenv shell"
fi

if [[ -n "${JAVA_HOME:-}" ]]; then
    ok "JAVA_HOME=$JAVA_HOME"
else
    fail "JAVA_HOME not set — Android build requires JAVA_HOME"
fi

# ── 3. Android repo tool ──────────────────────────────────────────────────────
info "Checking repo..."
if command -v repo &>/dev/null; then
    ok "repo: $(repo --version 2>&1 | head -1 || echo 'found')"
else
    fail "repo not found — install via devenv or: pip install repo"
fi

# ── 4. Core build tools ───────────────────────────────────────────────────────
info "Checking core build tools..."
REQUIRED=(git git-lfs python3 make curl zip unzip bc rsync xxd xmlstarlet jq)
for tool in "${REQUIRED[@]}"; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool: $(command -v "$tool")"
    else
        fail "$tool: not found"
    fi
done

# ── 5. Android-specific tools ────────────────────────────────────────────────
info "Checking Android build tools..."
ANDROID_TOOLS=(adb fastboot simg2img)
for tool in "${ANDROID_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool: $(command -v "$tool")"
    else
        warn "$tool: not found (optional for build, required for flash/firmware ops)"
    fi
done

# ── 6. AOSP-sourced tools (built after repo sync) ────────────────────────────
info "Checking AOSP-sourced tools (available after repo sync + m)..."
AOSP_TOOLS=(mkbootimg unpackbootimg lpunpack lpmake)
for tool in "${AOSP_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool: $(command -v "$tool")"
    else
        warn "$tool: not found — build with: m mkbootimg unpack_bootimg lpunpack lpmake"
    fi
done

# ── 7. Compression tools (for firmware analysis) ─────────────────────────────
info "Checking compression tools..."
COMPRESS_TOOLS=(cpio gzip lz4 lzop zstd xz)
for tool in "${COMPRESS_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool: found"
    else
        fail "$tool: not found"
    fi
done

# ── 8. ccache ─────────────────────────────────────────────────────────────────
info "Checking ccache..."
if command -v ccache &>/dev/null; then
    ok "ccache: $(ccache --version | head -1)"
    if [[ -n "${CCACHE_EXEC:-}" ]]; then
        ok "CCACHE_EXEC=$CCACHE_EXEC"
    else
        warn "CCACHE_EXEC not set — ccache may not be used during build"
    fi
else
    warn "ccache: not found (optional but strongly recommended for faster builds)"
fi

# ── 9. Build environment variables ───────────────────────────────────────────
info "Checking build environment variables..."
ENV_REQUIRED=(LC_ALL ALLOW_MISSING_DEPENDENCIES USE_CCACHE)
for var in "${ENV_REQUIRED[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        ok "$var=${!var}"
    else
        warn "$var not set (should be set by devenv shell)"
    fi
done

# ── 10. Script linting ────────────────────────────────────────────────────────
info "Checking script linting tools..."
if command -v shellcheck &>/dev/null; then
    ok "shellcheck: $(shellcheck --version | head -1)"
else
    warn "shellcheck: not found — run inside devenv shell for lint support"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────────────────"
if [[ $FAILED -gt 0 ]]; then
    printf "${RED}${BOLD}FAILED: %d error(s), %d warning(s)${RESET}\n" "$FAILED" "$WARNINGS"
    printf "${RED}Fix the errors above before starting a build.${RESET}\n"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    printf "${YELLOW}${BOLD}PASS with warnings: %d warning(s)${RESET}\n" "$WARNINGS"
    printf "${YELLOW}Build may succeed, but check warnings above.${RESET}\n"
else
    printf "${GREEN}${BOLD}ALL CHECKS PASSED${RESET}\n"
fi
echo ""
