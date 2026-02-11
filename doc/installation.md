# Installation

> [Retour au README](../README.md) · [Utilisation](utilisation.md) · [Configuration](configuration.md) · [Notifications](notifications.md) · [Mise à jour et debug](mise-a-jour.md)

---

## Pré-requis

| Composant | Obligatoire | Notes |
|-----------|:-----------:|-------|
| **Debian** (ou dérivé) | Oui | Testé sur Proxmox LXC, compatible toute distribution Debian |
| **Bash 4.4+** | Oui | Fourni par défaut sur Debian 10+ |
| **Git** | Oui | Pour le clonage et les mises à jour |
| **curl** | Oui | Pour l'installation et la vérification des MAJ |
| **rclone** | Oui | Proposé à l'installation si absent |
| **msmtp** | Non | Nécessaire uniquement pour l'envoi d'emails |
| **jq** | Non | Nécessaire uniquement pour les notifications Discord |

## Installation automatique (recommandée)

```bash
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh)
```

Le script d'installation :
1. Clone le dépôt dans `/opt/rclone_homelab`
2. Rend les scripts exécutables
3. Crée un symlink `rclone_homelab` dans `/usr/local/bin`
4. Crée un symlink `rclone_homelab-updater` pour l'outil de mise à jour
5. Propose l'installation de rclone si absent

## Installation manuelle (pas à pas)

### 1. Créer le dossier d'installation

```bash
mkdir -p /opt/rclone_homelab
```

### 2. Cloner le dépôt

```bash
cd /opt/rclone_homelab
git clone https://github.com/Gotcha26/rclone_homelab.git .
```

> Le `.` final clone directement dans le dossier courant sans créer de sous-dossier.

### 3. Rendre les scripts exécutables

```bash
chmod +x /opt/rclone_homelab/main.sh
chmod +x /opt/rclone_homelab/maintenance/standalone_updater.sh
```

### 4. Créer les symlinks

```bash
ln -sf /opt/rclone_homelab/main.sh /usr/local/bin/rclone_homelab
ln -sf /opt/rclone_homelab/maintenance/standalone_updater.sh /usr/local/bin/rclone_homelab-updater
```

### 5. Vérifier l'installation

```bash
which rclone_homelab
# /usr/local/bin/rclone_homelab

rclone_homelab --help
```

## Installer rclone

Si rclone n'est pas déjà présent, il sera proposé automatiquement au premier lancement.

Installation manuelle :
```bash
apt install rclone -y
```

Il s'installe dans `/usr/bin/rclone`. Pour configurer vos remotes :
```bash
rclone config
```

Consultez la [documentation officielle rclone](https://rclone.org/docs/) pour configurer vos fournisseurs cloud (OneDrive, Google Drive, SFTP, S3, etc.).

## Utilisation de l'éditeur micro (optionnel)

Le script propose `nano` par défaut. Si vous préférez `micro`, vous pouvez le sélectionner via le menu interactif (branche dev) ou dans votre [configuration locale](configuration.md).

Raccourcis clavier micro : [doc.ubuntu-fr.org/micro](https://doc.ubuntu-fr.org/micro)

## Structure du projet

```
rclone_homelab/
├── main.sh                    # Point d'entrée
├── menu.sh                    # Menu interactif
├── jobs.sh                    # Exécution des jobs rclone
├── bootstrap.sh               # Initialisation (sourcing config + fonctions)
├── install.sh                 # Installateur
├── config/
│   └── global.conf            # Configuration par défaut
├── functions/                 # Fonctions métier
│   ├── core.sh                # Fonctions centrales
│   ├── menu_f.sh              # Helpers du menu
│   ├── cron_f.sh              # Gestion des tâches cron
│   ├── jobs_f.sh              # Parsing et validation des jobs
│   ├── debug.sh               # Fonctions debug
│   └── updater.sh             # Mise à jour via git
├── libs/
│   └── lib_gotcha.sh          # Bibliothèque affichage (couleurs, tableaux)
├── export/
│   ├── mail.sh                # Envoi d'emails via msmtp
│   └── discord.sh             # Notifications Discord
├── local/                     # Vos fichiers personnels (jamais écrasés)
├── exemples_files/            # Templates pour les fichiers locaux
├── logs/                      # Logs générés
├── maintenance/               # Scripts de maintenance
└── doc/                       # Documentation
```
