# install-orisha-web-workstation

Automated post-installation of an Ubuntu workstation using Ansible.

This repository configures a freshly installed Ubuntu machine by running several
Ansible roles: target user account, system update, base tools, development tools
(Git, Docker, VS Code) and desktop applications (browsers, media, chat).

The workstation is typically provisioned **for a third party**: you run the
installer from an account that has `sudo`, provide the target user's first and
last name, and the tooling creates their admin account and derives their
identity (email, LDAP id).

## Requirements

- Ubuntu (or a Debian/APT-based distribution).
- A user with `sudo` privileges (do not run as root).
- Internet access.

Ansible does not need to be installed beforehand: the `bootstrap.sh` script
takes care of it.

## Quick start

```bash
git clone https://github.com/donaldinou/install-orisha-web-workstation.git
cd install-orisha-web-workstation
./bootstrap.sh --firstname Jacques-Yves --lastname Haury
```

The script prompts for anything missing (first/last name, and confirmation of
the derived email and LDAP id), asks for the `sudo` password
(`--ask-become-pass`) and the Vault password, then runs the playbook. When it
finishes, the new account **must change its password at first login**, and you
should **log out and back in** so the `docker` group membership takes effect.

Fully non-interactive run:

```bash
./bootstrap.sh --firstname Jean --lastname Dupont --yes
```

## Target user identity

From the first and last name, the installer derives three identifiers:

| Value             | Rule                                            | Example (`Jacques-Yves Haury`) |
|-------------------|-------------------------------------------------|--------------------------------|
| Email             | `{first-name initials}.{lastname}@orisha.com`   | `jy.haury@orisha.com`          |
| LDAP id           | `{firstname}.{lastname}`                        | `jacques-yves.haury`           |
| Local account     | `{first-name initials}{lastname}`               | `jyhaury`                      |

Rules of derivation:

- Names are normalized: lowercased, accents stripped (`Zoé` → `zoe`),
  apostrophes removed.
- First-name initials take one letter per component, split on hyphens or
  spaces: `Jacques-Yves` → `jy`.
- Hyphens are kept in the LDAP first name (`jacques-yves`) but dropped in the
  account name and last name.

Email and LDAP id are shown as editable defaults: press Enter to accept, or type
a new value (or pass `--email` / `--ldap`). The local account name is always
derived and not editable.

### The created account

- If the account does **not** exist, it is created with the shell `/bin/bash`,
  added to the `sudo` group, and its password is set (see Vault below) with a
  forced change at first login.
- If the account **already** exists, it is not recreated; it is only granted
  admin rights (added to `sudo`). The existing password is left untouched.

### `bootstrap.sh` options

| Option                | Description                                             |
|-----------------------|---------------------------------------------------------|
| `-f`, `--firstname`   | Target user's first name (required).                    |
| `-l`, `--lastname`    | Target user's last name (required).                     |
| `-e`, `--email`       | Override the derived email address.                     |
| `--ldap`              | Override the derived LDAP identifier.                   |
| `-y`, `--yes`         | Non-interactive: accept all derived defaults.           |
| `-h`, `--help`        | Show help and exit.                                     |

Any other option (`--check`, `--tags`, ...) is forwarded to `ansible-playbook`.

## Password & Ansible Vault

The initial account password is stored **hashed (SHA-512)** and **encrypted with
Ansible Vault** in `group_vars/all/vault.yml`, so the secret can live in Git
safely. The account is forced to change it at first login.

- The Vault password is **not** stored in the repository. Provide it at runtime:
  - place it in a `.vault_pass` file at the repo root (git-ignored), or
  - let `bootstrap.sh` prompt for it (`--ask-vault-pass`).
- To view or edit the secret:

  ```bash
  ansible-vault view group_vars/all/vault.yml
  ansible-vault edit group_vars/all/vault.yml
  ```

- To change the stored password, generate a new SHA-512 hash and re-encrypt:

  ```bash
  openssl passwd -6 'new-password'          # produces the $6$... hash
  ansible-vault edit group_vars/all/vault.yml
  ```

## What does `bootstrap.sh` do?

1. Checks the environment (APT-based distribution, non-root, `sudo` present).
2. Installs Ansible and Git if missing (via the official Ansible PPA).
3. Installs the required Ansible collections from `requirements.yml`.
4. Runs the `local.yml` playbook.

Any extra option passed to `bootstrap.sh` is forwarded to `ansible-playbook`.
Examples:

```bash
./bootstrap.sh --check              # dry-run, applies nothing
./bootstrap.sh --tags dev_tools     # run a single role (see "Selective runs")
```

## Selective runs (tags)

Each role is associated with a tag (`system`, `dev_tools`, `desktop`), which
lets you run only part of the configuration:

```bash
./bootstrap.sh --tags dev_tools              # development tools only
./bootstrap.sh --tags system,dev_tools       # system + development tools
./bootstrap.sh --skip-tags desktop           # everything except desktop apps
```

The same works directly with `ansible-playbook`:

```bash
ansible-playbook local.yml --ask-become-pass --tags dev_tools
```

## Project structure

```
.
├── bootstrap.sh          # Bootstrap script (identity prompts, installs Ansible, runs the playbook)
├── local.yml             # Main playbook (localhost, local connection)
├── requirements.yml      # Required Ansible collections (community.general)
├── group_vars/
│   └── all/
│       └── vault.yml     # Vault-encrypted secrets (hashed account password)
└── roles/
    ├── user_account/     # Creates/updates the target admin account, derives identity
    ├── system/           # System update + base system tools
    ├── dev_tools/        # Git, CLI tools, Docker, VS Code
    └── desktop/          # Browsers, media and chat applications
```

> `.vault_pass` (the Vault password file) is git-ignored and must never be
> committed.

## Roles

| Role           | Tag            | Contents                                                             |
|----------------|----------------|----------------------------------------------------------------------|
| `user_account` | `user_account` | Derives the identity and creates/updates the target admin account.   |
| `system`    | `system`    | `apt update` + `upgrade dist`, then curl, wget, htop, build-essential, unzip, etc. |
| `dev_tools` | `dev_tools` | git, jq, tree; Docker CE + Compose v2 (official repo); VS Code (classic Snap). |
| `desktop`   | `desktop`   | VLC, GIMP, Google Chrome, Brave, Opera, Microsoft Edge, Firefox, Vivaldi (APT); Slack, Discord, Chromium (Snap); Tor Browser (Flatpak). |

Each role is configurable through its `roles/<role>/defaults/main.yml` file
(package lists, URLs, etc.).

## Docker

Docker is installed from the **official Docker repository**, not from the Ubuntu
packages. Compose v2 is provided via `docker-compose-plugin`, so the command is
`docker compose` (not `docker-compose`). The current user is added to the
`docker` group.

## Web browsers

The following browsers are installed from their **official APT repositories**
and then update automatically via APT: Google Chrome, Brave, Opera, Microsoft
Edge, Firefox (Mozilla repository) and Vivaldi.

Browsers are defined declaratively in `desktop_apt_browsers`
(`roles/desktop/defaults/main.yml`): each entry carries its GPG key, repository
and package. Adding another APT-based browser is just one more list entry, no
task change required.

Notes:

- Most repositories are `amd64`-only. Mozilla's Firefox repository is
  multi-arch, so it is not restricted to `amd64`.
- Firefox declares an optional `pin`: Ubuntu's default `firefox` package is a
  transitional stub that installs the Snap, so an APT preference file pins
  Mozilla's repository above it. Any other browser needing the same treatment
  just adds a `pin` field.
- Chromium has no official vendor APT repository (the Ubuntu APT package is a
  Snap wrapper), so it is installed via **Snap** (`chromium`).
- Tor Browser has no reliable official Snap, so it is installed via **Flatpak**
  from Flathub (`org.torproject.torbrowser-launcher`). Flatpak and the Flathub
  remote are set up automatically by the `desktop` role.

## Running manually (Ansible already installed)

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook local.yml --ask-become-pass
```

## Development

Ansible is only needed here to validate the project (end users get it installed
automatically by `bootstrap.sh`). To validate locally:

```bash
ansible-galaxy collection install -r requirements.yml
# Syntax check the whole playbook (Vault + a sample identity)
ansible-playbook local.yml --syntax-check \
  --vault-password-file .vault_pass \
  --extra-vars '{"user_firstname": "Jean-Pierre", "user_lastname": "Le Goff"}'
```

Identity values are always passed to Ansible as a **JSON** `--extra-vars` object
so that names containing spaces (e.g. `Le Goff`) or apostrophes (e.g. `D'Arc`)
are not split. The playbook is the single source of truth for the derived
email / LDAP id / account name.

This project follows the **SOLID** and **DRY** principles. See
`.kiro/steering/principles.md` for the rules applied to the Ansible roles and
shell scripts.
