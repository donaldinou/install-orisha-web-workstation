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

In both cases (created or pre-existing), the account's **global Git identity**
is configured in its own `~/.gitconfig`:

- `user.name` = the original first and last name (e.g. `Jean-Pierre Le Goff`).
- `user.email` = the derived (or overridden) email (e.g. `jp.legoff@orisha.com`).

Ansible runs this as the target user (`become_user`), so `git config --global`
writes to that account's home, not the installer's.

### SSH key

An **ed25519 SSH key without passphrase** is generated in the account's
`~/.ssh/id_ed25519` (commented with the email), for use with GitHub, GitLab and
other forges. Generation is idempotent: an existing key is **never** regenerated
or overwritten, so a key already registered on a forge stays valid. The public
key is printed at the end of the run so it can be added to the forges.

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
| `user_account` | `user_account` | Derives the identity, creates/updates the target admin account, sets its global Git identity, and generates an ed25519 SSH key. |
| `system`    | `system`    | `apt update` + `upgrade dist`, then base tools: curl, wget, htop, build-essential, archive tools (zip/unzip/unrar, exfatprogs), network shares (smbclient, cifs-utils), OpenVPN (classic + NetworkManager) and OpenVPN 3 (official repo), gnupg, openssh, etc. |
| `dev_tools` | `dev_tools` | Git & friends from the **git-core PPA** (git, git-extras, git-flow, git-lfs); DevOps/network CLI (jq, nmap, net-tools, traceroute, sshfs, mussh, gdebi...); Python stack (python3, python3-dev, virtualenv, pip, pipx); build/dev tools (gcc, make, autoconf, meld, imagemagick, adb...); dev libraries (`-dev` headers) and iOS device support; Docker CE + Compose v2 (official repo); VS Code (classic Snap). |
| `desktop`   | `desktop`   | VLC, Inkscape, GIMP, FileZilla (APT); Google Chrome, Brave, Opera, Microsoft Edge, Firefox, Vivaldi (APT repos); Slack, Discord, Chromium (Snap); Tor Browser (Flatpak). |

Each role is configurable through its `roles/<role>/defaults/main.yml` file
(package lists, URLs, etc.).

## Docker

Docker is installed from the **official Docker repository**, not from the Ubuntu
packages. Compose v2 is provided via `docker-compose-plugin`, so the command is
`docker compose` (not `docker-compose`). The current user is added to the
`docker` group.

## VPN (OpenVPN classic + OpenVPN 3)

Two VPN clients are installed by the `system` role:

- **Classic OpenVPN** (`openvpn`) with NetworkManager integration
  (`network-manager-openvpn`, `network-manager-openvpn-gnome`) for importing and
  managing `.ovpn` profiles from the GNOME UI.
- **OpenVPN 3** (`openvpn3`), the vendor's next-gen CLI client, installed from
  **OpenVPN's official APT repository** (key + repo, per the
  [official tutorial](https://openvpn.net/cloud-docs/tutorials/configuration-tutorials/connectors/operating-systems/linux/tutorial--learn-to-install-and-control-the-openvpn-3-client.html)).
  Toggle with `system_install_openvpn3`.

Note on the repository suite: OpenVPN publishes per-LTS suites and may lag just
after a brand-new Ubuntu release. The repo suite defaults to the machine's own
codename (`system_openvpn3_distro`); override it to the latest supported LTS if
the repository has no suite for the running release yet.

## Git (git-core PPA)

Git and its companions (`git-extras`, `git-flow`, `git-lfs`) are installed from
the **`ppa:git-core/ppa`** rather than the Ubuntu repositories, because the PPA
tracks newer Git releases. The PPA is added before Git is installed.

## Development libraries & iOS support

The `dev_tools` role installs two extra groups (ported from a legacy 20.04 dev
workstation, names verified against Ubuntu 24.04):

- `dev_tools_build_libs` — `-dev` headers commonly needed to build native
  extensions and C projects (`libssl-dev`, `libcurl4-openssl-dev`, `libzip-dev`,
  `libbz2-dev`, `liblzma-dev`, `libicu-dev`, `libxslt1-dev`, `libmcrypt-dev`).
  `libmcrypt-dev` is kept for legacy PHP (< 7.2).
- `dev_tools_ios_packages` — iOS device debugging support (`usbmuxd`,
  `libimobiledevice-utils`/`-dev`, `libplist-dev`, `libplist++-dev`,
  `libusb-1.0-0-dev`). Toggle with `dev_tools_install_ios_support` (default
  `true`). These live in **universe** (enabled by default on Ubuntu Desktop).

Dropped from the original list: `libc-dev` (virtual, already pulled by
`build-essential`) and `libusb-dev` (legacy libusb 0.1, superseded by
`libusb-1.0-0-dev`).

## Package name compatibility (24.04 / 26.04)

Package names are chosen to be valid on Ubuntu 24.04 (noble) and 26.04. A few
names from older setups were adjusted:

- `exfat-utils` → `exfatprogs` (the old package was removed in 20.04+).
- `gnupg2` dropped (transitional to `gnupg`).
- `android-tools-adb` → `adb` on recent Ubuntu.
- `git-extras` (with an `s`), `mussh`, `findutils` are the correct package names.
- `build-dep` was removed from the list: it is an `apt` subcommand, not a package.

Note: `unrar` lives in the **multiverse** component. The `system` role enables
the components listed in `system_apt_components` (multiverse by default) before
installing packages, so `unrar` installs cleanly. The step is idempotent: a
component already enabled is left untouched.

## Installer options (third-party drivers & media codecs)

The `system` role reproduces the two Ubuntu installer checkboxes, so the result
is the same whether or not they were ticked during setup:

- **Third-party drivers (graphics & Wi-Fi)** — installs `ubuntu-drivers-common`
  and `linux-firmware`, then runs `ubuntu-drivers autoinstall`, which detects
  and installs the right proprietary driver for the actual hardware. Toggle with
  `system_install_third_party_drivers`.
- **Additional media formats** — installs `ubuntu-restricted-extras` (codecs,
  Microsoft fonts). The Microsoft fonts EULA is pre-accepted non-interactively
  via `debconf`. Toggle with `system_install_restricted_extras`. Requires
  multiverse (enabled above).

These install **proprietary** drivers, codecs and fonts (Microsoft EULA), just
like ticking the boxes in the Ubuntu installer.

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
