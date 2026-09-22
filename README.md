# install-orisha-web-workstation

Post-installation automatisée d'un poste de travail Ubuntu à l'aide d'Ansible.

Ce dépôt configure une machine Ubuntu fraîchement installée en enchaînant
plusieurs rôles Ansible : mise à jour du système, outils de base, outils de
développement (Git, Docker, VS Code) et applications desktop (VLC, GIMP, Slack,
Discord).

## Prérequis

- Ubuntu (ou une distribution basée sur Debian/APT).
- Un utilisateur disposant des droits `sudo` (ne pas lancer en root).
- Un accès Internet.

Ansible n'a pas besoin d'être installé au préalable : le script `bootstrap.sh`
s'en charge.

## Installation rapide

```bash
git clone https://github.com/donaldinou/install-orisha-web-workstation.git
cd install-orisha-web-workstation
./bootstrap.sh
```

Le script demande le mot de passe `sudo` (`--ask-become-pass`) puis exécute le
playbook. À la fin, **déconnectez-vous puis reconnectez-vous** pour que
l'appartenance au groupe `docker` prenne effet.

## Que fait `bootstrap.sh` ?

1. Vérifie l'environnement (distribution APT, non-root, `sudo` présent).
2. Installe Ansible et Git s'ils sont absents (via le PPA officiel Ansible).
3. Installe les collections Ansible requises depuis `requirements.yml`.
4. Lance le playbook `local.yml`.

Toute option supplémentaire passée à `bootstrap.sh` est transmise à
`ansible-playbook`. Exemples :

```bash
./bootstrap.sh --check              # simulation (dry-run), n'applique rien
./bootstrap.sh --tags dev_tools     # n'exécute qu'un rôle (voir « Exécution sélective »)
```

## Exécution sélective (tags)

Chaque rôle est associé à un tag (`system`, `dev_tools`, `desktop`), ce qui
permet de n'exécuter qu'une partie de la configuration :

```bash
./bootstrap.sh --tags dev_tools              # uniquement les outils de dev
./bootstrap.sh --tags system,dev_tools       # système + outils de dev
./bootstrap.sh --skip-tags desktop           # tout sauf les applis desktop
```

La même chose fonctionne directement avec `ansible-playbook` :

```bash
ansible-playbook local.yml --ask-become-pass --tags dev_tools
```

## Structure du projet

```
.
├── bootstrap.sh          # Script d'amorçage (installe Ansible puis lance le playbook)
├── local.yml             # Playbook principal (localhost, connection local)
├── requirements.yml      # Collections Ansible requises (community.general)
└── roles/
    ├── system/           # Mise à jour + outils système de base
    ├── dev_tools/        # Git, outils CLI, Docker, VS Code
    └── desktop/          # VLC, GIMP, Slack, Discord
```

## Les rôles

| Rôle        | Tag         | Contenu                                                                 |
|-------------|-------------|-------------------------------------------------------------------------|
| `system`    | `system`    | `apt update` + `upgrade dist`, puis curl, wget, htop, build-essential, unzip, etc. |
| `dev_tools` | `dev_tools` | git, jq, tree ; Docker CE + Compose v2 (dépôt officiel) ; VS Code (Snap classic). |
| `desktop`   | `desktop`   | VLC, GIMP, Google Chrome (APT) ; Slack, Discord (Snap).                 |

Chaque rôle est configurable via son fichier `roles/<rôle>/defaults/main.yml`
(listes de paquets, URLs, etc.).

## Docker

Docker est installé depuis le **dépôt officiel Docker**, pas depuis les paquets
Ubuntu. Compose v2 est fourni via `docker-compose-plugin` : la commande est donc
`docker compose` (et non `docker-compose`). L'utilisateur courant est ajouté au
groupe `docker`.

## Lancer manuellement (Ansible déjà installé)

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook local.yml --ask-become-pass
```

## Conventions de développement

Ce projet suit les principes **SOLID** et **DRY**. Voir
`.kiro/steering/principles.md` pour le détail des règles appliquées aux rôles
Ansible et aux scripts shell.
