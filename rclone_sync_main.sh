#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement

# Résoudre le chemin réel du script (suivi des symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

source "$SCRIPT_DIR/rclone_sync_conf.sh"
source "$SCRIPT_DIR/rclone_sync_functions.sh"
source "$SCRIPT_DIR/rclone_sync_jobs.sh"

###############################################################################
# Création des répertoires nécessaires
###############################################################################
mkdir -p "$LOG_DIR"
mkdir -p "$TMP_RCLONE"

###############################################################################
# Vérifications initiales
###############################################################################
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
# **Vérification ajoutée pour TMP_RCLONE**
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "$MSG_TMP_NOT_FOUND : $TMP_RCLONE" >&2
    ERROR_CODE=7
    exit $ERROR_CODE
fi

# Charger la liste des remotes configurés dans rclone
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

###############################################################################
# Lecture des options du script
###############################################################################
DRY_RUN=false

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

# Vérification si --mailto est fourni
if [[ -z "$MAIL_TO" ]]; then
    echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    SEND_MAIL=false
else
    SEND_MAIL=true
fi

# === Vérification non bloquante si --mail activé sans --mailto ===
if $SEND_MAIL && [[ -z "$MAIL_TO" ]]; then
    echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    SEND_MAIL=false
fi

###############################################################################
# Purge inconditionnel des logs anciens (tous fichiers du dossier)
###############################################################################
find "$LOG_DIR" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

exit $ERROR_CODE

###############################################################################
# Affichage récapitulatif à la sortie
###############################################################################
trap 'print_summary_table' EXIT
