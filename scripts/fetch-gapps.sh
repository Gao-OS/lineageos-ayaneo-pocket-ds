#!/usr/bin/env bash
set -euo pipefail

# Fetch/verify MindTheGapps for LineageOS 21 (arm64)
# Usually synced via repo sync with local_manifests/gapps.xml
# This script is a fallback for manual setup

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GAPPS_DIR="$ROOT_DIR/vendor/gapps"

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $(basename "$0")"
    echo "Fetches MindTheGapps if not already synced via repo."
    exit 0
fi

if [[ -f "$GAPPS_DIR/arm64/arm64-vendor.mk" ]]; then
    ok "MindTheGapps already present at $GAPPS_DIR"
    exit 0
fi

info "MindTheGapps not found. Cloning..."
mkdir -p "$(dirname "$GAPPS_DIR")"
git clone --depth 1 -b 14 https://gitlab.com/nicholaschum/mindthegapps.git "$GAPPS_DIR"

if [[ -f "$GAPPS_DIR/arm64/arm64-vendor.mk" ]]; then
    ok "MindTheGapps fetched successfully"
else
    die "MindTheGapps clone completed but arm64-vendor.mk not found"
fi
