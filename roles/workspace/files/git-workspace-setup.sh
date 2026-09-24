#!/usr/bin/env bash
#
# git-workspace-setup.sh - Prepare the immo-facile git workspace for the current
# user. Clones the repositories, initializes git-flow and syncs the dev env.
#
# This script is meant to be run AS THE TARGET USER (it uses their SSH key and
# their ~/git tree). It is idempotent: existing clones are left as-is and only
# missing steps are performed, so it is safe to re-run.
#
# PREREQUISITE — SSH key access:
#   git access uses the user's SSH key over ssh://git@gitlab.immo-facile.com.
#   That key (generated during provisioning, ~/.ssh/id_ed25519.pub) MUST be
#   added to the user's GitLab account first. If it is not, this script detects
#   it, prints instructions and exits WITHOUT error so it can simply be re-run
#   later once the key is registered.
#
# Usage:
#   git-workspace-setup

set -euo pipefail

readonly GIT_HOST="gitlab.immo-facile.com"
readonly GIT_PORT="10022"
readonly GIT_BASE="ssh://git@${GIT_HOST}:${GIT_PORT}/immofacile"
readonly WORKSPACE_DIR="$HOME/git/immofacile"
readonly PUBKEY="$HOME/.ssh/id_ed25519.pub"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
err()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; }

# --- Guard rails -------------------------------------------------------------

require_tools() {
    local missing=0
    for tool in git rsync ssh ssh-keyscan; do
        command -v "$tool" >/dev/null 2>&1 || { err "'$tool' is required but not installed."; missing=1; }
    done
    command -v git-flow >/dev/null 2>&1 || git flow version >/dev/null 2>&1 \
        || { err "git-flow is required but not installed."; missing=1; }
    [ "$missing" -eq 0 ]
}

# Make sure the GitLab host key is trusted (avoids the interactive prompt).
ensure_known_host() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/known_hosts"
    if ! ssh-keygen -F "[${GIT_HOST}]:${GIT_PORT}" >/dev/null 2>&1; then
        log "Adding ${GIT_HOST}:${GIT_PORT} to known_hosts..."
        ssh-keyscan -p "$GIT_PORT" "$GIT_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    fi
}

# Verify the SSH key is accepted by GitLab. GitLab answers an SSH auth attempt
# with a welcome banner and closes the connection (exit 0/1 but with output).
check_ssh_access() {
    local out
    # BatchMode: never prompt for a password; fail fast if the key is refused.
    out="$(ssh -p "$GIT_PORT" -o BatchMode=yes -o ConnectTimeout=10 \
        "git@${GIT_HOST}" 2>&1 || true)"

    if printf '%s' "$out" | grep -qiE 'welcome|authenticated|gitlab'; then
        return 0
    fi

    err "Cannot authenticate to ${GIT_HOST} with your SSH key."
    warn "Your SSH public key is not (yet) registered on GitLab. To fix this:"
    warn "  1. Copy your public key:"
    if [ -f "$PUBKEY" ]; then
        printf '\n%s\n\n' "$(cat "$PUBKEY")"
    else
        warn "     (expected at $PUBKEY — not found; generate it first)"
    fi
    warn "  2. Add it in GitLab: https://${GIT_HOST}/-/user_settings/ssh_keys"
    warn "  3. Re-run this script: git-workspace-setup"
    return 1
}

# --- Workspace steps (each idempotent) ---------------------------------------

clone_repo() {
    # $1 = repo name, $2 = branch
    local name="$1" branch="$2" dest="$WORKSPACE_DIR/$1"
    if [ -d "$dest/.git" ]; then
        log "Repo '$name' already cloned, skipping."
        return 0
    fi
    log "Cloning '$name' (branch $branch)..."
    git clone -b "$branch" --recursive "${GIT_BASE}/${name}.git" "$dest"
}

# git flow init is idempotent enough with -d/-f; guard on an existing config.
init_git_flow() {
    local dir="$1"; shift
    if git -C "$dir" config --get gitflow.branch.develop >/dev/null 2>&1; then
        log "git-flow already initialized in '$dir', skipping."
        return 0
    fi
    log "Initializing git-flow in '$dir'..."
    ( cd "$dir" && git flow init "$@" )
}

sync_dev_env() {
    local src="$WORKSPACE_DIR/logiciel/env-development"
    if [ ! -d "$src" ]; then
        warn "No env-development directory in logiciel, skipping rsync."
        return 0
    fi
    log "Syncing logiciel/env-development/* into the workspace..."
    ( cd "$WORKSPACE_DIR" && rsync -avc logiciel/env-development/config-dev/ ./config/ )
}

# --- Main --------------------------------------------------------------------

main() {
    require_tools || exit 1
    mkdir -p "$WORKSPACE_DIR"
    ensure_known_host
    check_ssh_access || exit 0   # not an error: just re-run once the key is set

    clone_repo "logiciel" "develop-web"
    clone_repo "office"   "develop"

    init_git_flow "$WORKSPACE_DIR/logiciel" \
        -p "feature-web/" -r "release-web/" -b "bugfix-web/" \
        -x "hotfix-web/" -s "support-web/" -d
    init_git_flow "$WORKSPACE_DIR/office" -d

    sync_dev_env

    log "immo-facile workspace ready in $WORKSPACE_DIR."
}

main "$@"
