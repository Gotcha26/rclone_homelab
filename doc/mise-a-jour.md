# Mise à jour et debug

> [Retour au README](../README.md) · [Installation](installation.md) · [Utilisation](utilisation.md) · [Configuration](configuration.md) · [Notifications](notifications.md)

---

## Table des matières

- [Système de mise à jour](#système-de-mise-à-jour)
- [Outil de mise à jour standalone](#outil-de-mise-à-jour-standalone)
- [Mettre à jour rclone](#mettre-à-jour-rclone)
- [Codes d'erreur](#codes-derreur)
- [Logs](#logs)
- [Recommandations](#recommandations)

---

## Système de mise à jour

Rclone Homelab Manager intègre un système de détection et d'application des mises à jour via Git.

### Détection automatique

Au lancement, le menu interactif vérifie :
- **Branche main** : compare votre version installée avec le dernier tag/release publié
- **Branche dev** : compare votre HEAD local avec le dernier commit du remote

Si une mise à jour est disponible, une option apparaît en haut du menu.

### Mise à jour via le menu

Sélectionnez l'option de mise à jour dans le menu. Après application, le script vous demande de le relancer pour prendre en compte les changements.

### Mise à jour en ligne de commandes

```bash
# Mettre à jour vers la dernière release stable
rclone_homelab --force-update

# Mettre à jour vers les derniers commits d'une branche
rclone_homelab --force-update dev
rclone_homelab --force-update main
```

La mise à jour est effectuée **après** l'exécution des jobs (si combinée avec `--auto`) pour éviter tout problème de fichiers en cours de traitement.

### Ce qui est préservé

Lors d'une mise à jour, le dossier `local/` (vos configurations, jobs, secrets) est **toujours préservé**. Les dossiers `logs/` et `tmps/` peuvent être nettoyés.

Si un fichier exemple a changé entre les versions, le script propose une montée de version assistée de vos fichiers locaux (voir [Configuration](configuration.md#montée-de-version-des-fichiers-locaux)).

---

## Outil de mise à jour standalone

Un script de mise à jour indépendant est disponible pour les cas d'urgence (script principal cassé, corruption...) :

```bash
# Via le symlink
rclone_homelab-updater

# Ou directement
/opt/rclone_homelab/maintenance/standalone_updater.sh
```

Avec l'option `--force`, il effectue une **réinstallation complète** (suppression + re-clonage) :

```bash
rclone_homelab-updater --force
```

> `--force` remplace tout le répertoire d'installation **sauf** les dossiers `local/`, `logs/` et `tmps/`.

L'outil détecte automatiquement votre branche courante pour réinstaller la même.

---

## Mettre à jour rclone

***rclone_homelab*** ne met pas à jour ***rclone*** lui-même : c'est à faire de temps en temps, à la main.

### Pourquoi c'est important

Les fournisseurs cloud (OneDrive en tête) font évoluer leur API. Une version ancienne de rclone finit par produire des erreurs incompréhensibles côté distant, par exemple :

```text
invalidRequest: The provided drive id appears to be malformed, or does not represent a valid drive.
```

Or le paquet de la distribution (`apt install rclone`) est souvent **très en retard** : Debian 12 fournit la v1.60, qui date de 2022.

> Repère : si des erreurs OneDrive/Google Drive apparaissent sans que rien n'ait changé chez vous, vérifiez d'abord la version de rclone (`rclone version`).

### Procédure recommandée (paquet officiel vérifié)

À lancer en root dans le conteneur où tourne ***rclone_homelab*** :

```bash
# 1. Sauvegarder la configuration rclone (remotes, tokens)
cp -a "$(rclone config file | tail -1)" /root/rclone.conf.backup_$(date +%F)

# 2. Télécharger la dernière version officielle et sa liste d'empreintes
VER=$(curl -fsS https://downloads.rclone.org/version.txt | awk '{print $2}')
cd /tmp
curl -fsSLO "https://downloads.rclone.org/${VER}/rclone-${VER}-linux-amd64.deb"
curl -fsSLO "https://downloads.rclone.org/${VER}/SHA256SUMS"

# 3. Vérifier l'empreinte (doit afficher : OK)
grep " rclone-${VER}-linux-amd64.deb$" SHA256SUMS | sha256sum -c -

# 4. Installer par-dessus la version existante
dpkg -i "rclone-${VER}-linux-amd64.deb"
rm -f "rclone-${VER}-linux-amd64.deb" SHA256SUMS

# 5. Contrôler
rclone version
rclone lsd mon_remote:
```

- Remplacez `amd64` par `arm64` ou `arm` sur un Raspberry Pi ou un autre système ARM (`uname -m` pour vérifier).
- La configuration (`~/.config/rclone/rclone.conf`) n'est pas modifiée par la mise à jour.
- Un `apt upgrade` ne reviendra pas à l'ancienne version : celle de la distribution est plus ancienne.

### Si un remote refuse la connexion après la mise à jour

Les remotes OAuth (OneDrive, Google Drive) peuvent demander une nouvelle autorisation :

```bash
rclone config reconnect mon_remote:
```

L'autorisation passe par un navigateur. Sur un conteneur sans interface graphique, rclone indique la commande `rclone authorize` à lancer sur un poste qui en a un.

### Alternative : la mise à jour intégrée

Une fois la version officielle installée, rclone sait se mettre à jour seul :

```bash
rclone selfupdate
```

---

## Codes d'erreur

### Erreurs d'infrastructure (bloquantes)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 4 | `write_version_file()` | Impossible de créer le dossier `local/` |
| 5 | `create_temp_dirs()` | Impossible de créer le dossier `tmps/` |
| 6 | `create_temp_dirs()` | Impossible de créer le dossier `logs/` |

### Erreurs de jobs (bloquantes)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 7 | `check_jobs_file()` | Fichier `jobs.conf` introuvable |
| 8 | `check_jobs_file()` | Fichier `jobs.conf` non lisible |
| 9 | `check_jobs_file()` | Fichier vide ou aucun job valide trouvé |

### Erreurs d'installation (bloquantes)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 10 | `install_rclone()` | Erreur lors de l'installation de rclone |
| 11 | `install_rclone()` | Installation refusée par l'utilisateur |
| 12 | Parseur CLI | `--mailto` fourni mais vide |
| 13 | Parseur CLI | `--mailto` mal formé (syntaxe `=` manquante) |
| 14 | `install_msmtp()` | Erreur lors de l'installation de msmtp |
| 15 | `main.sh` | Une autre instance est déjà en cours d'exécution (verrou) |

### Erreurs email (bloquantes)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 20 | `check_and_prepare_email()` | Adresse email non validée (format incorrect) |
| 21 | `check_and_prepare_email()` | msmtp absent et non installé |
| 22 | `check_and_prepare_email()` | Installation de msmtp refusée |
| 23-26 | `check_and_prepare_email()` | Configuration msmtp absente/vide/refusée |

### Erreurs de notification (non bloquantes, signalées en fin d'exécution)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 27 | `send_email()` | Échec de l'envoi du mail par msmtp |
| 28 | `send_discord_notification()` | Échec de la notification Discord (webhook, réseau ou jq absent) |

### Erreurs de validation

| Code | Fonction | Cause |
|:----:|----------|-------|
| 89 | `menu_validation_local_variables()` | Variable invalide, correction refusée par l'utilisateur |

### Erreurs de jobs (non bloquantes)

| Code | Fonction | Cause |
|:----:|----------|-------|
| 90 | `check_src()` | Dossier source du job non trouvé |
| 91 | `check_remotes()` | Remote rclone manquant/inconnu/injoignable |
| 92 | `check_remotes()` | Token expiré (OneDrive/Google, lecture seule) |
| 93 | `check_remotes()` | `--dry-run` incompatible avec le type de remote (CIFS/SMB/local) |

### Codes spéciaux

| Code | Signification |
|:----:|---------------|
| 0 | Succès |
| 99 | Quit menu (utilisateur a quitté le menu interactif) |

---

## Logs

Les logs sont conservés pendant la durée configurée par `LOG_RETENTION_DAYS` (défaut : 15 jours) puis purgés automatiquement.

### Fichiers de logs

```
logs/
├── main_YYYYMMDD_HHMMSS.log      # Sortie complète du terminal
├── rclone_YYYYMMDD_HHMMSS.log    # Log rclone (niveau INFO)
└── msmtp__YYYYMMDD_HHMMSS.log    # Log msmtp (paramètres d'envoi)
```

- **main_*.log** : capture tout ce qui s'affiche dans le terminal (sauf les éditions de fichiers)
- **rclone_*.log** : contient le résultat détaillé de chaque job rclone
- **msmtp_*.log** : trace les paramètres et le résultat de l'envoi d'email

---

## Recommandations

### Proxmox / homelab

- Ne pas exécuter de scripts à la racine d'un noeud Proxmox. Privilégiez un conteneur LXC ou une VM
- Utilisez les sauvegardes Proxmox avant toute modification : facile à faire et à restaurer
- Isolez vos tâches de sauvegarde dans un LXC dédié

### Bonnes pratiques

- Testez toujours avec `--dry-run` avant de lancer une synchronisation pour de vrai
- Configurez un rapport email ou Discord pour être informé des résultats
- Vérifiez régulièrement que vos tokens cloud ne sont pas expirés (OneDrive, Google Drive)
- Conservez vos fichiers `local/` dans un endroit sûr (ou sauvegardez-les indépendamment)
