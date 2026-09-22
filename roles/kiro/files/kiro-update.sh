#!/usr/bin/env bash
#
# kiro-update.sh - Install or update the Kiro IDE from the official download
# server, using the official .deb package (clean APT install, dependencies
# resolved, proper uninstall). Idempotent: only downloads and installs when the
# latest published version differs from the one currently installed.
#
# NOTE: Since 2026-08-18 the Kiro IDE has a working built-in auto-updater, so
# routine updates no longer require this script. It is kept for MANUAL use
# (initial install, forced re-install, or environments where the built-in
# updater is disabled). Run as root:
#
#   sudo kiro-update
#
# It relies on Kiro's official stable .deb metadata endpoint to discover the
# latest version and package URL, so there is no hardcoded version.

set -euo pipefail

readonly METADATA_URL="https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-deb-stable.json"
readonly PACKAGE_NAME="kiro"

log() { printf 'kiro-update: %s\n' "$1"; }

# Only x86-64 .deb packages are published for Linux; skip quietly otherwise.
if [ "$(uname -m)" != "x86_64" ]; then
    log "unsupported architecture $(uname -m), skipping."
    exit 0
fi

for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log "required tool '$tool' not found, skipping."
        exit 0
    fi
done

# Discover the latest version and the .deb URL from the official metadata.
metadata="$(curl -fsSL "$METADATA_URL")" || { log "cannot reach metadata, skipping."; exit 0; }
latest_version="$(printf '%s' "$metadata" | jq -r '.currentRelease')"
deb_url="$(printf '%s' "$metadata" \
    | jq -r '.releases[].updateTo.url | select(endswith(".deb"))' \
    | head -n1)"

if [ -z "$latest_version" ] || [ -z "$deb_url" ]; then
    log "could not determine latest version/URL, skipping."
    exit 0
fi

# Compare with the installed package version; nothing to do if already current.
installed_version="$(dpkg-query -W -f='${Version}' "$PACKAGE_NAME" 2>/dev/null || true)"

if [ -n "$installed_version" ] && printf '%s' "$installed_version" | grep -q "$latest_version"; then
    log "already up to date (version $installed_version)."
    exit 0
fi

log "installing/updating Kiro to '$latest_version' (installed: '${installed_version:-none}')..."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL -o "$tmp_dir/kiro.deb" "$deb_url"

# apt install resolves dependencies for the local .deb file.
DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_dir/kiro.deb"

log "Kiro $latest_version installed."
