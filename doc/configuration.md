# Configuration

> [Retour au README](../README.md) · [Installation](installation.md) · [Utilisation](utilisation.md) · [Notifications](notifications.md) · [Mise à jour et debug](mise-a-jour.md)

---

## Table des matières

- [Hiérarchie de configuration](#hiérarchie-de-configuration)
- [Fichiers locaux](#fichiers-locaux)
- [Variables configurables](#variables-configurables)
- [Options rclone](#options-rclone)
- [Fichier secrets](#fichier-secrets)
- [Validation automatique](#validation-automatique)

---

## Hiérarchie de configuration

La configuration suit un système de **surcharge par couches**. Chaque niveau écrase les valeurs du précédent :

```
1. config/global.conf          ← Valeurs par défaut (ne pas modifier)
2. local/config.local.conf     ← Vos préférences personnelles
3. local/config.dev.conf       ← Surcharges développeur (branche dev uniquement)
4. local/secrets.env           ← Données sensibles (mots de passe, tokens)
```

Le dossier `local/` est **ignoré par git** : vos fichiers ne seront jamais écrasés par une mise à jour.

---

## Fichiers locaux

```
local/
├── jobs.conf              # Liste des jobs rclone (obligatoire)
├── config.local.conf      # Vos surcharges de configuration (optionnel)
├── config.dev.conf        # Surcharges dev (optionnel, branche dev uniquement)
├── secrets.env            # Identifiants, tokens, webhooks (optionnel)
└── backups/               # Sauvegardes automatiques lors des montées de version
```

### Créer un fichier local

Le menu interactif propose de créer chaque fichier à partir d'un template pré-rempli. Le template s'ouvre automatiquement dans l'éditeur configuré.

Manuellement, copiez les exemples :
```bash
cp exemples_files/config.main.txt local/config.local.conf
cp exemples_files/jobs.txt local/jobs.conf
cp exemples_files/secrets.txt local/secrets.env
```

### Montée de version des fichiers locaux

Quand un fichier exemple change après une mise à jour, le script :
1. Détecte les différences entre l'ancienne et la nouvelle version de référence
2. Affiche un diff coloré des changements
3. Propose une montée de version automatique qui **préserve vos valeurs** tout en intégrant les nouveautés
4. Crée une sauvegarde horodatée avant toute modification

---

## Variables configurables

Toutes ces variables peuvent être définies dans `local/config.local.conf` :

### Comportement du script

| Variable | Valeurs | Défaut | Description |
|----------|---------|--------|-------------|
| `DRY_RUN` | `true` / `false` | `false` | Simulation sans transfert |
| `ACTION_MODE` | `auto` / `manu` | `manu` | Mode automatique (cron) ou interactif |
| `DISPLAY_MODE` | `soft` / `verbose` / `hard` | `soft` | Niveau de verbosité |

### Notifications

| Variable | Valeurs | Défaut | Description |
|----------|---------|--------|-------------|
| `MAIL_TO` | adresse email | `""` | Adresse pour le rapport HTML |
| `DISCORD_WEBHOOK_URL` | URL webhook | `""` | Webhook Discord pour les notifications |

### Technique

| Variable | Valeurs | Défaut | Description |
|----------|---------|--------|-------------|
| `TERM_WIDTH_DEFAULT` | `80` à `120` | `80` | Largeur du terminal pour l'affichage |
| `LOG_RETENTION_DAYS` | `1` à `15` | `15` | Durée de conservation des logs (jours) |
| `LOG_LINE_MAX` | `100` à `10000` | `1000` | Nombre max de lignes dans les rapports email |
| `EDITOR` | `nano` / `micro` | `nano` | Éditeur pour la modification des fichiers |

### Mise à jour

| Variable | Valeurs | Défaut | Description |
|----------|---------|--------|-------------|
| `FORCE_UPDATE` | `true` / `false` | `false` | Forcer la mise à jour automatique |
| `FORCE_BRANCH` | nom de branche | `""` | Branche cible pour `--force-update` |

### Debug

| Variable | Valeurs | Défaut | Description |
|----------|---------|--------|-------------|
| `DEBUG_INFOS` | `true` / `false` | `false` | Affiche les informations de debug au démarrage |
| `DEBUG_MODE` | `true` / `false` | `false` | Active le mode debug complet |

### Exemple de fichier config.local.conf

```bash
# Mes préférences
DRY_RUN=false
MAIL_TO=admin@monserveur.local
ACTION_MODE=auto
DISPLAY_MODE=verbose

# Technique
TERM_WIDTH_DEFAULT=100
LOG_RETENTION_DAYS=7
EDITOR=micro
```

---

## Options rclone

Les options rclone sont définies dans le tableau `RCLONE_OPTS` de votre configuration locale :

```bash
RCLONE_OPTS=(
    --temp-dir "${DIR_TMP:-}"
    --exclude '*.tmp'
    --exclude '*.lock'
    --exclude 'node_modules/'
    --log-level INFO
    --stats-log-level NOTICE
    --stats=0
)
```

Les valeurs par défaut (dans `config/global.conf`) incluent déjà :
- Exclusion des caractères Windows interdits (`*<*`, `*>*`, `*:*`, etc.)
- Exclusion des fichiers cachés (`.*`) et `Thumbs.db`
- Niveaux de log raisonnables

Consultez la [documentation rclone](https://rclone.org/flags/) pour toutes les options disponibles.

---

## Fichier secrets

Le fichier `local/secrets.env` permet de stocker des données sensibles séparément :

```bash
# Identifiants msmtp
MSMTP_PASSWORD=monmotdepasse

# Webhook Discord
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123456/abcdef
```

Ce fichier est sourcé après les autres configurations, il peut donc surcharger n'importe quelle variable.

---

## Validation automatique

Au démarrage, le script valide toutes les variables configurables selon des règles strictes :

| Type de règle | Format | Exemple |
|---------------|--------|---------|
| Booléen | `bool:défaut` | `DRY_RUN` → doit être `true` ou `false` |
| Énumération | `val1\|val2:défaut` | `EDITOR` → doit être `nano` ou `micro` |
| Plage numérique | `min-max:défaut` | `TERM_WIDTH_DEFAULT` → entre `80` et `120` |
| Libre | `*:défaut` | `MAIL_TO` → toute valeur acceptée |

En **mode interactif** (`manu`) : le script propose un menu de correction si des valeurs sont invalides.

En **mode automatique** (`auto`) : les valeurs invalides sont silencieusement remplacées par leur valeur par défaut.
