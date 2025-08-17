#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement

###############################################################################
# 0. Affiche le logo uniquement si on n'est pas en mode "automatique"
###############################################################################
if [[ "$LAUNCH_MODE" != "automatique" ]]; then
    print_logo
fi

# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# Résoudre le chemin réel du script (suivi des symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Sourcing global
source "$SCRIPT_DIR/rclone_sync_conf.sh"
source "$SCRIPT_DIR/rclone_sync_functions.sh"

# ---------------------------
# Création des répertoires nécessaires
# ---------------------------

if [[ ! -d "$TMP_RCLONE" ]]; then
    if ! mkdir -p "$TMP_RCLONE" 2>/dev/null; then
        echo "${RED}$MSG_TMP_RCLONE_CREATE_FAIL : $TMP_RCLONE${RESET}" >&2
        ERROR_CODE=8
        exit $ERROR_CODE
    fi
fi

if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        echo "${RED}$MSG_LOG_DIR_CREATE_FAIL : $LOG_DIR${RESET}" >&2
        ERROR_CODE=8
        exit $ERROR_CODE
    fi
fi

# ---------------------------
# Vérifications initiales
# ---------------------------

if [[ ! -f "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_FOUND : $JOBS_FILE" >&2
    ERROR_CODE=1
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_READ : $JOBS_FILE" >&2
    ERROR_CODE=2
    exit $ERROR_CODE
fi
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "$MSG_TMP_NOT_FOUND : $TMP_RCLONE" >&2
    ERROR_CODE=7
    exit $ERROR_CODE
fi

###############################################################################
# 2. Parsing complet des arguments
# Lecture des options du script
###############################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            LAUNCH_MODE="automatique"
            shift
            ;;
        --mailto=*)
            MAIL_TO="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Activation dry-run si demandé
if $DRY_RUN; then
    RCLONE_OPTS+=(--dry-run)
fi

# ---------------------------
# Charger la liste des remotes configurés dans rclone
# ---------------------------

mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

###############################################################################
# 3. Exécution des jobs rclone
# Sourcing
###############################################################################

source "$SCRIPT_DIR/rclone_sync_jobs.sh"

###############################################################################
# 4. Traitement des emails
# Sourcing
###############################################################################

# Vérification si --mailto est fourni
if [[ -z "$MAIL_TO" ]]; then
    echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    SEND_MAIL=false
else
    SEND_MAIL=true
    source "$SCRIPT_DIR/rclone_sync_mail.sh"
fi

###############################################################################
# 4. Suite des opérations
###############################################################################

# Purge inconditionnel des logs anciens (tous fichiers du dossier)
find "$LOG_DIR" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

# Affichage récapitulatif à la sortie
trap 'print_summary_table' EXIT

exit $ERROR_CODE
