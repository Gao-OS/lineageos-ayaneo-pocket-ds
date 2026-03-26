#!/usr/bin/env bash
set -euo pipefail

# Fetch/update gsmlg-apps prebuilt APKs
# Downloads latest releases from github.com/gsmlg-app org

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PREBUILT_DIR="$ROOT_DIR/packages/gsmlg-apps/prebuilt"

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Downloads/updates gsmlg-app prebuilt APKs from GitHub releases."
    echo ""
    echo "APKs are placed in packages/gsmlg-apps/prebuilt/"
    echo "Edit the APPS array in this script to add/remove apps."
    exit 0
fi

command -v curl &>/dev/null || die "curl is required"

mkdir -p "$PREBUILT_DIR"

# Define apps to fetch: "org/repo APK_NAME"
# Add new gsmlg-apps here as they become available
APPS=(
    # Format: "github_org/repo output_filename"
    # Example: "gsmlg-app/example ExampleApp.apk"
)

if [[ ${#APPS[@]} -eq 0 ]]; then
    info "No gsmlg-apps configured for download yet."
    info "Edit scripts/fetch-gsmlg-apps.sh to add apps."
    info "KernelSU Manager is fetched by scripts/patch-kernelsu.sh instead."
    exit 0
fi

for app_entry in "${APPS[@]}"; do
    local repo apk_name
    read -r repo apk_name <<< "$app_entry"

    info "Fetching latest release of $repo..."
    local release_url
    release_url=$(curl -sL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": "[^"]*\.apk"' \
        | head -1 \
        | cut -d'"' -f4)

    if [[ -z "$release_url" ]]; then
        warn "No APK found in latest release of $repo"
        continue
    fi

    info "Downloading: $release_url"
    curl -sL -o "$PREBUILT_DIR/$apk_name" "$release_url"
    ok "Saved: $PREBUILT_DIR/$apk_name"
done

ok "gsmlg-apps fetch complete"
