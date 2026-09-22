#!/usr/bin/env bash
#
# bootstrap.sh - Bootstraps the post-installation of an Ubuntu workstation.
#
# This script:
#   1. checks the environment (APT-based distribution, non-root, sudo present);
#   2. collects the target user's identity (firstname / lastname) and derives
#      the email, LDAP id and local account name;
#   3. installs Ansible and Git if missing;
#   4. installs the required Ansible collections (requirements.yml);
#   5. runs the local.yml playbook locally.
#
# Usage:
#   ./bootstrap.sh --firstname Jacques-Yves --lastname Haury
#   ./bootstrap.sh --firstname Jean --lastname Dupont --yes
#   ./bootstrap.sh -f Jean -l Dupont --email custom@orisha.com
#
# Identity options:
#   -f, --firstname NAME   Target user's first name (required).
#   -l, --lastname NAME    Target user's last name (required).
#   -e, --email ADDR       Override the derived email address.
#       --ldap ID          Override the derived LDAP identifier.
#   -y, --yes              Non-interactive: accept all derived defaults.
#   -h, --help             Show this help and exit.
#
# Any other option (e.g. --check, --tags) is forwarded as-is to ansible-playbook.

set -euo pipefail

# --- Configuration ----------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLAYBOOK="local.yml"
readonly REQUIREMENTS="requirements.yml"
readonly ANSIBLE_PPA="ppa:ansible/ansible"
readonly EMAIL_DOMAIN="orisha.com"
readonly VAULT_PASS_FILE="$SCRIPT_DIR/.vault_pass"

# Identity state (populated by argument parsing / derivation / prompts).
FIRSTNAME=""
LASTNAME=""
EMAIL=""
LDAP=""
EMAIL_OVERRIDDEN=0
LDAP_OVERRIDDEN=0
ASSUME_YES=0
PASSTHROUGH_ARGS=()

# --- Logging helpers --------------------------------------------------------

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$1"
}

err() {
    printf '\033[1;31mError:\033[0m %s\n' "$1" >&2
}

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Identity helpers (one function = one responsibility) -------------------

# Normalize a string: lowercase, strip accents, remove apostrophes.
# $1 = input string. Spaces and hyphens are left untouched here; callers decide.
normalize() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null \
        | tr -d "'"
}

# First-name initials, one per component split on hyphen or space.
# "Jacques-Yves" -> "jy"
firstname_initials() {
    local norm
    norm="$(normalize "$1" | tr ' ' '-')"
    printf '%s' "$norm" | awk -F'-' '{for (i=1;i<=NF;i++) printf "%s", substr($i,1,1)}'
}

# Normalized first name keeping hyphens (for LDAP): "jacques-yves".
firstname_ldap() {
    normalize "$1" | tr ' ' '-'
}

# Normalized last name, no spaces/hyphens: "haury".
lastname_norm() {
    normalize "$1" | tr -d ' -'
}

# --- Steps ------------------------------------------------------------------

# Parse CLI arguments, splitting identity options from ansible passthrough.
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--firstname) FIRSTNAME="$2"; shift 2 ;;
            -l|--lastname)  LASTNAME="$2";  shift 2 ;;
            -e|--email)     EMAIL="$2"; EMAIL_OVERRIDDEN=1; shift 2 ;;
            --ldap)         LDAP="$2";  LDAP_OVERRIDDEN=1;  shift 2 ;;
            -y|--yes)       ASSUME_YES=1;   shift ;;
            -h|--help)      usage; exit 0 ;;
            *)              PASSTHROUGH_ARGS+=("$1"); shift ;;
        esac
    done
}

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

# Prompt for firstname/lastname if missing (unless --yes, where they are
# mandatory upfront).
collect_identity() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        if [ -z "$FIRSTNAME" ] || [ -z "$LASTNAME" ]; then
            err "--yes requires both --firstname and --lastname."
            return 1
        fi
        return 0
    fi

    while [ -z "$FIRSTNAME" ]; do
        read -r -p "First name: " FIRSTNAME
    done
    while [ -z "$LASTNAME" ]; do
        read -r -p "Last name: " LASTNAME
    done
}

# Derive email and LDAP defaults, then let the user confirm or override them
# (unless --yes). An empty answer keeps the derived default.
derive_and_confirm() {
    local initials firstln lastln default_email default_ldap answer

    initials="$(firstname_initials "$FIRSTNAME")"
    firstln="$(firstname_ldap "$FIRSTNAME")"
    lastln="$(lastname_norm "$LASTNAME")"

    default_email="${initials}.${lastln}@${EMAIL_DOMAIN}"
    default_ldap="${firstln}.${lastln}"

    # Only fall back to defaults when not explicitly provided on the CLI.
    [ -z "$EMAIL" ] && EMAIL="$default_email"
    [ -z "$LDAP" ]  && LDAP="$default_ldap"

    if [ "$ASSUME_YES" -eq 0 ]; then
        read -r -p "Email [$EMAIL]: " answer
        [ -n "$answer" ] && { EMAIL="$answer"; EMAIL_OVERRIDDEN=1; }
        read -r -p "LDAP id [$LDAP]: " answer
        [ -n "$answer" ] && { LDAP="$answer"; LDAP_OVERRIDDEN=1; }
    fi

    log "Identity summary:"
    printf '    Account : %s%s\n' "$initials" "$lastln"
    printf '    Email   : %s\n' "$EMAIL"
    printf '    LDAP    : %s\n' "$LDAP"
}

# Install Ansible and Git if Ansible is missing.
install_ansible() {
    if command -v ansible-playbook >/dev/null 2>&1; then
        log "Ansible already present."
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

# Build the --vault option, prompting for the vault password unless a
# .vault_pass file is present.
vault_option() {
    if [ -f "$VAULT_PASS_FILE" ]; then
        printf '%s' "--vault-password-file $VAULT_PASS_FILE"
    else
        printf '%s' "--ask-vault-pass"
    fi
}

# Escape a string so it can be embedded in a JSON double-quoted value.
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Build the identity extra-vars as a single JSON object. Passing JSON (rather
# than key=value) is required so that values containing spaces (e.g. a last name
# like "Le Goff") are not split by Ansible.
# firstname/lastname are always included; email/ldap only when overridden, so
# the playbook stays the single source of truth for the derived defaults.
build_extra_vars_json() {
    local json="{\"user_firstname\": \"$(json_escape "$FIRSTNAME")\""
    json+=", \"user_lastname\": \"$(json_escape "$LASTNAME")\""
    [ "$EMAIL_OVERRIDDEN" -eq 1 ] && json+=", \"user_email\": \"$(json_escape "$EMAIL")\""
    [ "$LDAP_OVERRIDDEN" -eq 1 ]  && json+=", \"user_ldap\": \"$(json_escape "$LDAP")\""
    json+="}"
    printf '%s' "$json"
}

# Run the playbook with the identity passed as JSON extra-vars.
run_playbook() {
    local vault_opt extra_vars_json
    vault_opt="$(vault_option)"
    extra_vars_json="$(build_extra_vars_json)"

    log "Running the $PLAYBOOK playbook..."
    # shellcheck disable=SC2086
    ansible-playbook "$PLAYBOOK" \
        --ask-become-pass \
        $vault_opt \
        --extra-vars "$extra_vars_json" \
        "${PASSTHROUGH_ARGS[@]}"
}

# --- Entry point ------------------------------------------------------------

main() {
    cd "$SCRIPT_DIR"
    parse_args "$@"
    check_environment
    collect_identity
    derive_and_confirm
    install_ansible
    install_collections
    run_playbook
    log "Done. The new account must change its password at first login."
    log "Also log out and back in to apply the docker group membership."
}

main "$@"
