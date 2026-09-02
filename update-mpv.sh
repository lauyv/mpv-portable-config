#!/usr/bin/env bash
# update-mpv.sh — Download / update mpv on macOS from nightly builds
# Source: https://nightly.link/mpv-player/mpv/workflows/build/master
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
NIGHTLY_PAGE="https://nightly.link/mpv-player/mpv/workflows/build/master"
INSTALL_DIR="${MPV_INSTALL_DIR:-/Applications}"
# State file lives inside the installed app bundle — no extra directories needed
STATE_FILE="${INSTALL_DIR}/mpv.app/Contents/last_build_url"

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'
  YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERR ]${NC}  $*" >&2; exit 1; }

# ── Detect platform ───────────────────────────────────────────────────────────
ARCH=$(uname -m)
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)

if [[ "$ARCH" == "arm64" ]]; then
  # Prefer exact macOS-version build; fall back in order
  PLATFORM_PREF="macos-${MACOS_MAJOR}-arm"
  PLATFORM_FALLBACKS=("macos-15-arm" "macos-14-arm")
else
  PLATFORM_PREF="macos-15-intel"
  PLATFORM_FALLBACKS=()
fi

info "System: macOS ${MACOS_MAJOR} on ${ARCH}"

# ── Fetch nightly.link page (HTML) ────────────────────────────────────────────
info "Checking latest nightly build …"
PAGE_HTML=$(curl -fsSL --max-time 30 "$NIGHTLY_PAGE") \
  || die "Failed to reach nightly.link — check your network connection."

# ── Pick download URL ─────────────────────────────────────────────────────────
find_url() {
  local platform="$1"
  echo "$PAGE_HTML" \
    | grep -oE "https://nightly\.link/[^ \"'<>]+${platform}\.zip" \
    | head -1
}

DOWNLOAD_URL=$(find_url "$PLATFORM_PREF" || true)

if [[ -z "$DOWNLOAD_URL" ]]; then
  for fb in "${PLATFORM_FALLBACKS[@]}"; do
    warn "Build for '${PLATFORM_PREF}' not found, trying '${fb}' …"
    DOWNLOAD_URL=$(find_url "$fb" || true)
    [[ -n "$DOWNLOAD_URL" ]] && { PLATFORM_PREF="$fb"; break; }
  done
fi

[[ -n "$DOWNLOAD_URL" ]] \
  || die "No macOS artifact found on nightly.link. Check the page manually:\n  ${NIGHTLY_PAGE}"

info "Platform : ${PLATFORM_PREF}"
info "Build URL: ${DOWNLOAD_URL}"

# ── Version check (skip if already installed) ─────────────────────────────────
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$DOWNLOAD_URL" ]]; then
  ok "mpv is already up to date (same nightly build)."
  exit 0
fi

# ── Installed version info (informational) ────────────────────────────────────
INSTALLED_APP="${INSTALL_DIR}/mpv.app"
if [[ -d "$INSTALLED_APP" ]]; then
  CUR_VER=$(defaults read "${INSTALLED_APP}/Contents/Info" \
    CFBundleShortVersionString 2>/dev/null || echo "unknown")
  info "Currently installed: mpv ${CUR_VER}"
else
  info "mpv not found in ${INSTALL_DIR} — fresh install."
fi

# ── Download ──────────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

info "Downloading …"
info "Saving to: ${WORK_DIR}/mpv.zip"
curl -L --progress-bar --max-time 300 -o "${WORK_DIR}/mpv.zip" "$DOWNLOAD_URL" \
  || die "Download failed."

# ── Extract ───────────────────────────────────────────────────────────────────
info "Extracting …"
unzip -q "${WORK_DIR}/mpv.zip" -d "${WORK_DIR}/step1" \
  || die "Extraction failed — the archive may be corrupt."

# The ZIP contains a mpv.tar.gz; extract that too
INNER_TARBALL=$(find "${WORK_DIR}/step1" -maxdepth 2 -name "*.tar.gz" | head -1)
if [[ -n "$INNER_TARBALL" ]]; then
  info "Inner archive: $(basename "$INNER_TARBALL")"
  mkdir -p "${WORK_DIR}/step2"
  tar -xzf "$INNER_TARBALL" -C "${WORK_DIR}/step2" \
    || die "tar extraction failed."
  SEARCH_DIR="${WORK_DIR}/step2"
else
  SEARCH_DIR="${WORK_DIR}/step1"
fi

APP_BUNDLE=$(find "$SEARCH_DIR" -maxdepth 3 -name "*.app" | head -1)
[[ -n "$APP_BUNDLE" ]] \
  || die "No .app bundle found inside the archive."

info "Bundle  : $(basename "$APP_BUNDLE")"

# ── Install ───────────────────────────────────────────────────────────────────
if [[ ! -w "$INSTALL_DIR" ]]; then
  warn "${INSTALL_DIR} is not writable — will use sudo."
  SUDO="sudo"
else
  SUDO=""
fi

info "Installing to ${INSTALL_DIR} …"
[[ -d "$INSTALLED_APP" ]] && $SUDO rm -rf "$INSTALLED_APP"
$SUDO cp -R "$APP_BUNDLE" "$INSTALLED_APP"

# Remove quarantine flag so macOS doesn't block the binary
xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null \
  && info "Quarantine attribute removed." || true

# ── Save state & report ───────────────────────────────────────────────────────
# Re-resolve STATE_FILE after install (the old app was replaced).
# Use $SUDO when writing so it works even if /Applications is root-owned.
STATE_FILE="${INSTALL_DIR}/mpv.app/Contents/last_build_url"
echo "$DOWNLOAD_URL" | $SUDO tee "$STATE_FILE" > /dev/null

NEW_VER=$(defaults read "${INSTALLED_APP}/Contents/Info" \
  CFBundleShortVersionString 2>/dev/null || echo "unknown")
ok "mpv ${NEW_VER} installed → ${INSTALLED_APP}"
