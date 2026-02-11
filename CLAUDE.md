# CLAUDE.md — Contexte projet rclone_homelab

## Description

**rclone_homelab** est un wrapper Bash autour de `rclone` pour automatiser la synchronisation de dossiers locaux vers des remotes cloud (OneDrive, Google Drive, SFTP...). Conçu pour tourner sur **Debian / Proxmox LXC**. Interface interactive (menu) + mode autonome (`--auto` pour cron). Notifications par email (msmtp) et Discord (webhook).

## Langue

L'interface utilisateur, les commentaires et les messages sont en **français**. Le code (noms de variables, fonctions) est en anglais.

## Architecture des fichiers

```
rclone_homelab/
├── main.sh                    # Point d'entrée — parse CLI, lance menu ou jobs
├── menu.sh                    # Menu interactif (sourcé par main.sh si pas d'args)
├── jobs.sh                    # Boucle d'exécution des jobs rclone
├── bootstrap.sh               # Init : source toutes les libs/config, déclare VARS_TO_VALIDATE
├── install.sh                 # Installateur du projet
├── config/
│   └── global.conf            # Configuration par défaut (toutes les variables)
├── functions/
│   ├── core.sh                # Fonctions centrales (help, config, rclone checks, validation, purge)
│   ├── menu_f.sh              # Helpers menu (add_option, print_menu, init_file, dev_install/uninstall)
│   ├── cron_f.sh              # Gestion des tâches cron (sous-menu, wizard, list, remove)
│   ├── jobs_f.sh              # Parsing/validation des jobs, generate_job_id()
│   ├── debug.sh               # Fonctions debug (show_debug_header)
│   └── updater.sh             # Mise à jour git (fetch_git_info, update_to_latest_tag/branch)
├── libs/
│   └── lib_gotcha.sh          # Bibliothèque affichage : print_fancy(), display_msg(), print_table(), scroll_down()
├── export/
│   ├── mail.sh                # Email HTML via msmtp (check_mail_format, send_email)
│   └── discord.sh             # Notification Discord via webhook + jq
├── local/                     # Fichiers utilisateur (gitignored)
│   ├── config.local.conf      # Surcharges config utilisateur
│   ├── config.dev.conf        # Surcharges branche dev
│   ├── jobs.conf              # Liste des jobs : source_path|remote:dest_path
│   └── secrets.env            # Secrets (mdp, tokens)
├── exemples_files/            # Templates pour les fichiers locaux
│   ├── config.main.txt
│   ├── jobs.txt
│   └── secrets.txt
├── logs/                      # Logs générés (gitignored via local/*)
├── tmps/                      # Fichiers temporaires
├── maintenance/               # Scripts de maintenance (manuels)
│   ├── pre-release.sh
│   ├── standalone_updater.sh
│   ├── reset-history.sh
│   └── local-cleaning.sh
└── doc/                       # Documentation
```

## Flux d'exécution

```
main.sh
  ├─ source bootstrap.sh (charge libs + config + fonctions + surcharges locales)
  ├─ Parse CLI (--auto, --dry-run, --mailto=, --discord-url=, --force-update, -h)
  ├─ Si aucun arg → source menu.sh (menu interactif en boucle)
  │   └─ Retour menu : recharge configs, passe en ACTION_MODE=auto
  ├─ Vérifications : rclone installé/configuré, jobs.conf valide, email
  ├─ source jobs.sh (exécute tous les jobs rclone)
  ├─ Envoi email si MAIL_TO défini
  ├─ Purge vieux logs
  ├─ Résumé final (print_summary_table)
  └─ exit $ERROR_CODE
```

## Chaîne de sourcing

```
main.sh → bootstrap.sh → lib_gotcha.sh, global.conf, core.sh, debug.sh, updater.sh, mail.sh, discord.sh
                        → load_optional_configs() → config.local.conf, config.dev.conf, secrets.env
menu.sh → menu_f.sh, cron_f.sh (sourcés spécifiquement pour le menu)
```

## Système de configuration

**Hiérarchie (chaque niveau surcharge le précédent) :**
1. `config/global.conf` — valeurs par défaut
2. `local/config.local.conf` — préférences utilisateur
3. `local/config.dev.conf` — surcharges dev (branche != main seulement)
4. `local/secrets.env` — données sensibles

**Variables principales :**

| Variable | Type/Valeurs | Défaut |
|----------|-------------|--------|
| `DRY_RUN` | bool | false |
| `MAIL_TO` | string (email) | "" |
| `DISCORD_WEBHOOK_URL` | string (URL) | "" |
| `FORCE_UPDATE` | bool | false |
| `ACTION_MODE` | auto\|manu | manu |
| `DISPLAY_MODE` | soft\|verbose\|hard | soft |
| `TERM_WIDTH_DEFAULT` | 80-120 | 80 |
| `LOG_RETENTION_DAYS` | 1-15 | 15 |
| `LOG_LINE_MAX` | 100-10000 | 1000 |
| `EDITOR` | nano\|micro | nano |
| `DEBUG_INFOS` | bool | false |
| `DEBUG_MODE` | bool | false |

**Validation** via `VARS_TO_VALIDATE` (tableau associatif dans bootstrap.sh) avec format `"type:default"` — types : `bool`, `enum1|enum2`, `min-max`, `*`.

## Système de menu

Le menu (menu.sh) utilise un pattern dynamique :
- `add_option(label, action_id)` → remplit `MENU_OPTIONS[]` et `MENU_ACTIONS[]`
- `add_separator_if_needed()` → séparateur visuel `────────`
- `print_menu(options, actions, choice_map, num)` → affiche et numérote
- Lecture choix : `read -e -rp "..." choice </dev/tty`
- Dispatch : `case "$action" in menu_xxx) ... ;;`
- Sous-menus : implémentés comme fonctions avec leur propre boucle `while true; do ... done`

**Convention d'action :**
```bash
menu_xxx)
    scroll_down
    # ... action ...
    echo "✅  ... message retour > retour au menu."
    ;;
```

## API d'affichage

### print_fancy [OPTIONS] "texte"
Options : `--fg`, `--bg`, `--fill`, `--align` (left|center|right), `--style` (bold|italic|underline, combinables avec `|`), `--highlight`, `--theme` (success|error|warning|info|ok|flash|follow|debug_info), `--icon`, `-n`, `--raw`

### display_msg "modes" [print_fancy_options] "texte"
Affichage conditionnel selon `$DISPLAY_MODE`. Modes : `soft`, `verbose`, `hard` (combinables avec `|`).

### Autres
- `scroll_down()` — fait défiler l'écran (lib_gotcha.sh)
- `print_table()` / `print_table_auto()` → `_print_table_core()` — tableaux formatés
- `die CODE "message"` — affiche erreur + exit

## Conventions de code

- **Bash** : `set -uo pipefail`, pas de `set -e`
- **Shebang** : `#!/usr/bin/env bash` pour les fichiers exécutables (main.sh, install.sh). Pas de shebang pour les fichiers sourcés.
- **Blocs commentaires** : chaque fonction précédée de `###...###` avec `# Fonction :` header
- **Nommage** : fonctions internes préfixées `_` (ex: `_cron_ask_hour`), fonctions publiques descriptives
- **Prompts interactifs** : toujours `read -e -rp "..." var </dev/tty` (le `</dev/tty` est critique pour la compat cron/pipe)
- **Confirmation** : pattern `[OoYy]` pour oui, vide = valeur par défaut
- **Variables globales** : SCREAMING_SNAKE_CASE
- **Variables locales** : déclarées avec `local`
- **Erreurs** : `print_fancy --theme error "message"` ou `die CODE "message"`
- **Namerefs** : `local -n` utilisés dans print_menu et quelques fonctions de lib_gotcha.sh
- **Tableaux associatifs** : `declare -A` (bash 4+)
- **Sortie tty** : certaines fonctions utilisent `>/dev/tty` pour afficher même quand stdout est capturé

## Chemins importants (variables globales)

| Variable | Valeur |
|----------|--------|
| `SCRIPT_PATH` | Chemin absolu vers main.sh |
| `SCRIPT_DIR` | Répertoire du projet |
| `DIR_LOCAL` | `$SCRIPT_DIR/local` |
| `DIR_TMP` | `$SCRIPT_DIR/tmps` |
| `DIR_LOG` | `$SCRIPT_DIR/logs` |
| `DIR_EXEMPLES` | `$SCRIPT_DIR/exemples_files` |
| `DIR_JOBS_FILE` | `$DIR_LOCAL/jobs.conf` |
| `DIR_CONF_LOCAL_FILE` | `$DIR_LOCAL/config.local.conf` |
| `DIR_CONF_DEV_FILE` | `$DIR_LOCAL/config.dev.conf` |
| `DIR_SECRET_FILE` | `$DIR_LOCAL/secrets.env` |
| `BACKUP_DIR` | `$DIR_LOCAL/backups` |

## Options CLI

| Option | Format | Rôle |
|--------|--------|------|
| `--auto` | flag | Mode non-interactif (cron) |
| `--dry-run` | flag | Simulation (passé à rclone) |
| `--mailto` | `--mailto=addr@domain` | Email de rapport |
| `--discord-url` | `--discord-url=URL` | Webhook Discord |
| `--force-update` | `--force-update [branche]` | Forcer MAJ, opt. switch branche |
| `-h` / `--help` | flag | Aide |
| `*` (autres) | passthrough | Transmis directement à rclone |

## Codes de sortie notables

| Code | Origine | Signification |
|------|---------|---------------|
| 0 | Normal | Succès |
| 5-6 | main.sh | Impossible créer tmp/log dir |
| 7-9 | check_jobs_file | Jobs file absent/illisible/vide |
| 10-13 | core.sh | rclone/msmtp install/config errors |
| 20-26 | mail.sh | Email format/msmtp errors |
| 31-32 | core.sh | rclone config errors |
| 90-92 | jobs_f.sh | Source dir/remote missing/expired |
| 99 | menu.sh | Quit menu |

## Format des jobs (local/jobs.conf)

```
# Commentaire
/chemin/source|remote:chemin/destination
```
Un job par ligne, `#` pour commentaires, lignes vides ignorées.

## Git

- **Branche principale** : `main`
- **Branche dev** : `dev`
- Le menu adapte ses options selon la branche courante
- Auto-update via tags (main) ou derniers commits (dev/autres)

## Cibles

- **OS** : Debian (Proxmox LXC principalement)
- **Bash** : 4.4+ (tableaux associatifs, namerefs)
- **Dépendances** : rclone (obligatoire), msmtp (optionnel), jq (optionnel, pour Discord), curl (pour GitHub API)
