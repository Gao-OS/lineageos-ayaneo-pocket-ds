#!/usr/bin/env bash
set -euo pipefail

# Run quality checks on the project
# Usage: ./scripts/lint.sh [--fix]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

ERRORS=0

step()    { printf "${BOLD}▶ %s${RESET}\n" "$*"; }
pass()    { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
fail()    { printf "  ${RED}✗${RESET} %s\n" "$*"; ERRORS=$((ERRORS + 1)); }
warn_msg(){ printf "  ${YELLOW}!${RESET} %s\n" "$*"; }

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0") [--fix]"
    echo "Run quality checks on shell scripts and project files."
    echo ""
    echo "Options:"
    echo "  --fix    Attempt to auto-fix issues (currently unused)"
    echo "  --help   Show this help"
    exit 0
fi

# --- Shellcheck ---
step "Running shellcheck on scripts/"
if command -v shellcheck &>/dev/null; then
    if shellcheck "${PROJECT_ROOT}"/scripts/*.sh 2>&1; then
        pass "All scripts pass shellcheck"
    else
        fail "shellcheck found issues in scripts/"
    fi
else
    warn_msg "shellcheck not found — run inside devenv shell"
fi

# --- Shellcheck on device tree scripts ---
step "Running shellcheck on device tree scripts"
device_scripts=()
while IFS= read -r -d '' f; do
    device_scripts+=("$f")
done < <(find "${PROJECT_ROOT}/device" -name "*.sh" -print0 2>/dev/null)

if [[ ${#device_scripts[@]} -gt 0 ]] && command -v shellcheck &>/dev/null; then
    if shellcheck "${device_scripts[@]}" 2>&1; then
        pass "All device tree scripts pass shellcheck"
    else
        fail "shellcheck found issues in device scripts"
    fi
fi

# --- XML validation ---
step "Validating XML files"
if command -v xmlstarlet &>/dev/null; then
    xml_ok=true
    while IFS= read -r -d '' xml; do
        if xmlstarlet val -q "$xml" 2>/dev/null; then
            pass "$(basename "$xml")"
        else
            fail "Invalid XML: $xml"
            xml_ok=false
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.xml" \
        -not -path "*/.git/*" \
        -not -path "*/.loki/*" \
        -not -path "*/out/*" \
        -not -path "*/.repo/*" \
        -print0 2>/dev/null)

    if $xml_ok; then
        pass "All XML files valid"
    fi
else
    warn_msg "xmlstarlet not found — run inside devenv shell"
fi

# --- Check for CRLF line endings ---
step "Checking for CRLF line endings"
crlf_files=()
while IFS= read -r f; do
    crlf_files+=("$f")
done < <(git -C "${PROJECT_ROOT}" grep -rlI $'\r' -- '*.sh' '*.mk' '*.xml' '*.nix' '*.prop' 2>/dev/null || true)

if [[ ${#crlf_files[@]} -gt 0 ]]; then
    for f in "${crlf_files[@]}"; do
        fail "CRLF detected: $f"
    done
else
    pass "No CRLF line endings found"
fi

# --- Check script executability ---
step "Checking script executable bits"
while IFS= read -r -d '' script; do
    if [[ ! -x "$script" ]]; then
        fail "Not executable: ${script#"${PROJECT_ROOT}"/}"
    fi
done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -print0 2>/dev/null)

while IFS= read -r -d '' script; do
    if [[ ! -x "$script" ]]; then
        fail "Not executable: ${script#"${PROJECT_ROOT}"/}"
    fi
done < <(find "${PROJECT_ROOT}/device" -name "*.sh" -print0 2>/dev/null)

pass "All .sh files have execute permission"

# --- Summary ---
echo ""
if [[ $ERRORS -gt 0 ]]; then
    printf "${RED}${BOLD}%d issue(s) found.${RESET}\n" "$ERRORS"
    exit 1
else
    printf '%b%bAll checks passed!%b\n' "${GREEN}" "${BOLD}" "${RESET}"
fi
