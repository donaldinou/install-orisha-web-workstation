# install-orisha-web-workstation

Automated post-installation of an Ubuntu workstation using Ansible.

This repository configures a freshly installed Ubuntu machine by running several
Ansible roles: system update, base tools, development tools (Git, Docker, VS
Code) and desktop applications (VLC, GIMP, Google Chrome, Slack, Discord).

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
./bootstrap.sh
```

The script asks for the `sudo` password (`--ask-become-pass`) then runs the
playbook. When it finishes, **log out and back in** so the `docker` group
membership takes effect.

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
├── bootstrap.sh          # Bootstrap script (installs Ansible then runs the playbook)
├── local.yml             # Main playbook (localhost, local connection)
├── requirements.yml      # Required Ansible collections (community.general)
└── roles/
    ├── system/           # System update + base system tools
    ├── dev_tools/        # Git, CLI tools, Docker, VS Code
    └── desktop/          # VLC, GIMP, Google Chrome, Slack, Discord
```

## Roles

| Role        | Tag         | Contents                                                                |
|-------------|-------------|-------------------------------------------------------------------------|
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

## Development conventions

This project follows the **SOLID** and **DRY** principles. See
`.kiro/steering/principles.md` for the rules applied to the Ansible roles and
shell scripts.
