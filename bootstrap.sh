#!/usr/bin/env bash
#
# bootstrap.sh - Bootstraps the post-installation of an Ubuntu workstation.
#
# This script:
#   1. checks the environment (APT-based distribution, non-root, sudo present);
#   2. installs Ansible and Git if missing;
#   3. installs the required Ansible collections (requirements.yml);
#   4. runs the local.yml playbook locally.
#
# Usage:
#   ./bootstrap.sh                    # full installation
#   ./bootstrap.sh --check            # dry-run
#   ./bootstrap.sh --tags dev_tools   # options forwarded to ansible-playbook
#
# Any extra option is forwarded as-is to ansible-playbook.

set -euo pipefail

# --- Configuration ----------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLAYBOOK="local.yml"
readonly REQUIREMENTS="requirements.yml"
readonly ANSIBLE_PPA="ppa:ansible/ansible"

# --- Logging helpers --------------------------------------------------------

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$1"
}

err() {
    printf '\033[1;31mError:\033[0m %s\n' "$1" >&2
}

# --- Steps (one function = one responsibility) ------------------------------

# Ensure the machine and the user meet the prerequisites.
check_environment() {
    if ! command -v apt-get >/dev/null 2>&1; then
        err "apt-get not found. This script targets Ubuntu / Debian."
        return 1
    fi

    if [ "$(id -u)" -eq 0 ]; then
        err "Do not run this script as root. Use a user with sudo privileges."
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        err "sudo is required but not found."
        return 1
    fi
}

# Install Ansible and Git if Ansible is missing.
install_ansible() {
    if command -v ansible-playbook >/dev/null 2>&1; then
        log "Ansible already present: $(ansible --version | head -1)"
        return 0
    fi

    log "Ansible missing, installing via APT..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y "$ANSIBLE_PPA"
    sudo apt-get update
    sudo apt-get install -y ansible git
}

# Install the Ansible collections declared in requirements.yml.
install_collections() {
    if [ ! -f "$REQUIREMENTS" ]; then
        log "No $REQUIREMENTS found, skipping this step."
        return 0
    fi

    log "Installing Ansible collections from $REQUIREMENTS..."
    ansible-galaxy collection install -r "$REQUIREMENTS"
}

# Run the playbook, forwarding the arguments received by the script.
run_playbook() {
    log "Running the $PLAYBOOK playbook..."
    ansible-playbook "$PLAYBOOK" --ask-become-pass "$@"
}

# --- Entry point ------------------------------------------------------------

main() {
    cd "$SCRIPT_DIR"
    check_environment
    install_ansible
    install_collections
    run_playbook "$@"
    log "Done. Log out and back in to apply the docker group membership."
}

main "$@"
