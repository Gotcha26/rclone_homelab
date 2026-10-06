# Utilisation

> [Retour au README](../README.md) · [Installation](installation.md) · [Configuration](configuration.md) · [Notifications](notifications.md) · [Mise à jour et debug](mise-a-jour.md)

---

## Table des matières

- [Menu interactif](#menu-interactif)
- [Arguments en ligne de commandes](#arguments-en-ligne-de-commandes)
- [Jobs rclone](#jobs-rclone)
- [Planification Cron](#planification-cron)
- [Exemples d'utilisation](#exemples-dutilisation)

---

## Menu interactif

Lancez le script sans argument pour accéder au menu :

```bash
rclone_homelab
```

Le menu propose les actions suivantes (affichées dynamiquement selon l'état de votre installation) :

| Catégorie | Options possibles |
|-----------|-------------------|
| **Mise à jour** | Mettre à jour vers la dernière release / branche (si disponible) |
| **Lancement** | Lancer tous les jobs immédiatement |
| **Jobs** | Créer / éditer le fichier des jobs rclone |
| **Rclone** | Installer / configurer / éditer la configuration rclone |
| **msmtp** | Installer / configurer / éditer msmtp (envoi d'emails) |
| **Cron** | Ajouter / modifier / lister / supprimer une tâche planifiée |
| **Configuration** | Éditer la config locale, la config dev, le fichier secrets |
| **Composants** | Installer / désinstaller des composants (branche dev) |
| **Aide** | Afficher l'aide intégrée |

Le menu s'adapte automatiquement :
- Les options d'installation n'apparaissent que si le composant est absent
- L'option de mise à jour n'apparaît que si une nouvelle version est détectée
- Les options dev ne s'affichent que sur les branches de développement

---

## Arguments en ligne de commandes

```bash
rclone_homelab [OPTIONS] [OPTIONS_RCLONE]
```

### Options du script

| Argument | Format | Description |
|----------|--------|-------------|
| `-h`, `--help` | flag | Affiche l'aide |
| `--auto` | flag | Mode non-interactif (idéal pour cron) : affichage minimal, aucune interaction sauf erreurs bloquantes |
| `--dry-run` | flag | Mode simulation : aucun transfert ni suppression de fichiers. L'option est transmise à rclone |
| `--mailto=` | `--mailto=adresse@domaine.com` | Envoie un rapport HTML par email à l'adresse indiquée (nécessite msmtp) |
| `--discord-url=` | `--discord-url=URL_WEBHOOK` | Envoie les rapports sur un salon Discord via webhook |
| `--force-update` | `--force-update [branche]` | Force la mise à jour. Optionnel : spécifier une branche |

### Passthrough rclone

Tout argument non reconnu par rclone_homelab est transmis directement à rclone :

```bash
# Accélérer les transferts
rclone_homelab --auto --transfers 8 --fast-list

# Limiter la bande passante
rclone_homelab --auto --bwlimit 10M

# Verbose rclone
rclone_homelab --auto --log-level DEBUG
```

Consultez la [documentation rclone](https://rclone.org/flags/) pour la liste complète des options disponibles.

---

## Jobs rclone

Les jobs définissent **quoi synchroniser et vers où**. Ils sont stockés dans le fichier `local/jobs.conf`.

### Format

```
# Ceci est un commentaire
/chemin/source|remote:chemin/destination
```

- **1 ligne = 1 job**
- Les lignes vides et les commentaires (`#`) sont ignorés
- Le séparateur est le pipe `|`
- Le premier champ est le **dossier source** (chemin absolu local)
- Le second champ est la **destination** au format rclone : `nom_du_remote:chemin/distant`

### Exemples

```bash
# Sauvegarder les documents vers OneDrive
/home/user/Documents|OneDrive:/Backups/Documents

# Sauvegarder un site web vers Google Drive
/var/www/monsite|gdrive:/Archives/Website

# Sauvegarder vers un serveur SFTP
/mnt/data|serveur_sftp:/backups/data
```

### Créer le fichier de jobs

Le plus simple : utilisez le menu interactif. Le script vous propose de créer le fichier à partir d'un template pré-rempli avec des exemples commentés.

Vous pouvez aussi le créer manuellement :
```bash
nano /opt/rclone_homelab/local/jobs.conf
```

### Vérifications automatiques

Avant chaque exécution, le script vérifie pour chaque job :
- Le dossier source existe et est accessible
- Le remote rclone est configuré et joignable
- Le token d'accès n'est pas expiré (OneDrive, Google Drive...)
- Le mode `--dry-run` est compatible avec le type de destination

---

## Planification Cron

### Via le menu interactif (recommandé)

Le menu principal propose l'option **Gérer le Crontab**. Le sous-menu offre quatre actions :

- **Ajouter** — un assistant en 7 étapes crée une nouvelle tâche
- **Modifier** — sélectionnez une tâche existante et reparcourez le même wizard avec les valeurs actuelles pré-remplies (Entrée = conserver)
- **Lister** — affiche toutes les tâches rclone_homelab présentes dans le crontab
- **Supprimer** — supprime une tâche spécifique

Les 7 étapes du wizard (création et modification) :

1. **Jour** : tous les jours ou un jour précis de la semaine
2. **Heure** (0-23)
3. **Minute** (0-59)
4. **--dry-run** : activer ou non le mode simulation
5. **--mailto** : adresse email pour le rapport (pré-remplie depuis votre config)
6. **--discord-url** : webhook Discord (pré-rempli depuis votre config)
7. **Options rclone supplémentaires** : texte libre

L'assistant affiche un résumé complet et la ligne cron résultante avant d'appliquer les changements.

### Manuellement

```bash
crontab -e
```

Exemple — exécution tous les jours à 4h00 avec rapport par email :
```
0 4 * * * PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /opt/rclone_homelab/main.sh --auto --mailto=admin@monserveur.local # rclone_homelab
```

Points importants :
- Toujours utiliser `--auto` (mode non-interactif)
- Utiliser le **chemin absolu** vers `main.sh` (pas le symlink)
- Ajouter `PATH=...` pour que rclone, msmtp, jq et curl soient trouvés
- Le commentaire `# rclone_homelab` en fin de ligne permet au script d'identifier ses propres tâches

---

## Exemples d'utilisation

### Utilisation interactive quotidienne
```bash
rclone_homelab
```

### Tester avant de synchroniser pour de vrai
```bash
rclone_homelab --dry-run
```

### Automatisation complète avec rapport
```bash
rclone_homelab --auto --mailto=admin@monserveur.local
```

### Automatisation avec notifications Discord
```bash
rclone_homelab --auto --discord-url=https://discord.com/api/webhooks/123456/abcdef
```

### Combinaison complète
```bash
rclone_homelab --auto --dry-run --mailto=admin@monserveur.local --discord-url=https://discord.com/api/webhooks/... --transfers 4
```

### Forcer une mise à jour
```bash
# Dernière release stable
rclone_homelab --force-update

# Derniers commits de la branche dev
rclone_homelab --force-update dev
```
