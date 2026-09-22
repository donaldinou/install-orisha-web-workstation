#!/usr/bin/env bash
#
# bootstrap.sh - Amorce la post-installation d'un poste Ubuntu.
#
# Ce script :
#   1. verifie l'environnement (distribution APT, non-root, sudo present) ;
#   2. installe Ansible et Git si absents ;
#   3. installe les collections Ansible requises (requirements.yml) ;
#   4. lance le playbook local.yml en local.
#
# Usage :
#   ./bootstrap.sh                    # installation complete
#   ./bootstrap.sh --check            # simulation (dry-run)
#   ./bootstrap.sh --tags dev_tools   # options transmises a ansible-playbook
#
# Toute option supplementaire est transmise telle quelle a ansible-playbook.

set -euo pipefail

# --- Configuration ----------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLAYBOOK="local.yml"
readonly REQUIREMENTS="requirements.yml"
readonly ANSIBLE_PPA="ppa:ansible/ansible"

# --- Helpers de log ---------------------------------------------------------

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$1"
}

err() {
    printf '\033[1;31mErreur:\033[0m %s\n' "$1" >&2
}

# --- Etapes (une fonction = une responsabilite) -----------------------------

# Verifie que la machine et l'utilisateur remplissent les prerequis.
check_environment() {
    if ! command -v apt-get >/dev/null 2>&1; then
        err "apt-get introuvable. Ce script cible Ubuntu / Debian."
        return 1
    fi

    if [ "$(id -u)" -eq 0 ]; then
        err "Ne pas lancer ce script en root. Utilisez un utilisateur avec les droits sudo."
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        err "sudo est requis mais introuvable."
        return 1
    fi
}

# Installe Ansible et Git si Ansible est absent.
install_ansible() {
    if command -v ansible-playbook >/dev/null 2>&1; then
        log "Ansible deja present : $(ansible --version | head -1)"
        return 0
    fi

    log "Ansible absent, installation via APT..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y "$ANSIBLE_PPA"
    sudo apt-get update
    sudo apt-get install -y ansible git
}

# Installe les collections Ansible declarees dans requirements.yml.
install_collections() {
    if [ ! -f "$REQUIREMENTS" ]; then
        log "Aucun $REQUIREMENTS trouve, etape ignoree."
        return 0
    fi

    log "Installation des collections Ansible depuis $REQUIREMENTS..."
    ansible-galaxy collection install -r "$REQUIREMENTS"
}

# Lance le playbook, en transmettant les arguments recus par le script.
run_playbook() {
    log "Lancement du playbook $PLAYBOOK..."
    ansible-playbook "$PLAYBOOK" --ask-become-pass "$@"
}

# --- Point d'entree ---------------------------------------------------------

main() {
    cd "$SCRIPT_DIR"
    check_environment
    install_ansible
    install_collections
    run_playbook "$@"
    log "Termine. Deconnectez-vous puis reconnectez-vous pour appliquer l'appartenance au groupe docker."
}

main "$@"
