#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement


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

# ---- Journal log général (sauf rclone qui a un log dédié) ----

# Création du dossier logs si absent
mkdir -p "$LOG_DIR"

# Redirige toute la sortie du script
# - stdout vers tee (console + fichier) [standard]
# - stderr aussi redirigé [sortie des erreurs]
exec > >(tee -a "$LOG_FILE_SCRIPT") 2>&1

# --- Vérification de la version du script ---

VERSION="v2.2.0"
REPO="Gotcha26/rclone_homelab"
latest=""
FORCE_UPDATE=false
FORCE_BRANCH=""     # Dois reserter vide pour prendre en compte "main" par défaut.
UPDATE_TAG=""

# Exécution des mises à jour si demandé
if $FORCE_UPDATE; then
    force_update_branch
    exit 0
fi

if $UPDATE_TAG; then
    update_to_latest_tag
    exit 0
fi

# Sinon, on continue le script normalement
check_update  # juste pour signaler la dispo d'une nouvelle release


###############################################################################
# 2. Parsing complet des arguments
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
        --update-forced)
            FORCE_UPDATE=true
            shift
            # Si une branche est fournie juste après, on la prend
            [[ $# -gt 0 && ! "$1" =~ ^-- ]] && FORCE_BRANCH="$1" && shift
            ;;
        --update-tag)
            UPDATE_TAG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            RCLONE_OPTS+=("$1")
            shift
            ;;
    esac
done

# Activation dry-run si demandé
$DRY_RUN && RCLONE_OPTS+=(--dry-run)

# Affiche le logo/bannière uniquement si on n'est pas en mode "automatique"
[[ "$LAUNCH_MODE" != "automatique" ]] && print_logo

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && check_email "$MAIL_TO"

# Vérification de la présence de rclone installé
if ! command -v rclone >/dev/null 2>&1; then
    echo "${RED}$MSG_RCLONE_FAIL${RESET}" >&2
    echo
    ERROR_CODE=10
    exit $ERROR_CODE
fi

# Création des répertoires nécessaires
if [[ ! -d "$TMP_RCLONE" ]]; then
    if ! mkdir -p "$TMP_RCLONE" 2>/dev/null; then
        echo "${RED}$MSG_TMP_RCLONE_CREATE_FAIL : $TMP_RCLONE${RESET}" >&2
        echo
        ERROR_CODE=1
        exit $ERROR_CODE
    fi
fi

if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        echo "${RED}$MSG_LOG_DIR_CREATE_FAIL : $LOG_DIR${RESET}" >&2
        echo
        ERROR_CODE=2
        exit $ERROR_CODE
    fi
fi

# Vérifications initiales
if [[ ! -f "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_FOUND : $JOBS_FILE" >&2
    echo
    ERROR_CODE=3
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_READ : $JOBS_FILE" >&2
    echo
    ERROR_CODE=4
    exit $ERROR_CODE
fi
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "$MSG_TMP_NOT_FOUND : $TMP_RCLONE" >&2
    echo
    ERROR_CODE=5
    exit $ERROR_CODE
fi


###############################################################################
# 3. Exécution des jobs rclone
# Sourcing
###############################################################################

source "$SCRIPT_DIR/rclone_sync_jobs.sh"


###############################################################################
# 4. Traitement des emails
###############################################################################

if [[ -n "$MAIL_TO" ]]; then
    send_email_if_needed "$GLOBAL_HTML_BLOCK"
fi


###############################################################################
# 4. Suite des opérations
###############################################################################

# Purge inconditionnel des fichiers anciens (sous-dossiers inclus)
find "$TMP_RCLONE" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

# Affichage récapitulatif à la sortie
trap 'print_summary_table' EXIT

exit $ERROR_CODE
