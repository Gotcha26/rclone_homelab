#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement
export GIT_PAGER=cat


# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# Initialisation de variables.
# Elles peuvent être écrasées par la configuration personnalisée, si présente.
ERROR_CODE=0
EXECUTED_JOBS=0

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/conf.sh"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/init.sh"
source "$SCRIPT_DIR/export/mail.sh"
source "$SCRIPT_DIR/export/discord.sh"
source "$SCRIPT_DIR/update/updater.sh"

# Initialise (sourcing) et informe de la branch en cours utilisée
# (basé sur la seule présence du fichier config/config.xxx.sh)
detect_config

# Affichage du logo/bannière
print_logo

# Création du dossier logs si absent
mkdir -p "$LOG_DIR"

# --- ↓ DEBUG ↓ ---
if [[ "$DEBUG_MODE" == "true" ]]; then 
    TMP_JOBS_DIR="$SCRIPT_DIR/tmp_jobs_debug"
    mkdir -p "$TMP_JOBS_DIR"
fi 

if [[ "$DEBUG_INFOS" == "true" ]]; then 
    print_fancy --theme "info" --fg "black" --bg "white" "DEBUG: LOG_FILE_SCRIPT = $LOG_FILE_SCRIPT"
fi 
# --- ↑ DEBUG ↑ ---

# --- Journal log général (sauf rclone qui a un log dédié par job - temporaires) ---

# Sauvegarde stdout et stderr originaux
exec 3>&1 4>&2

# Redirige toute la sortie du script
# - stdout vers tee (console + fichier) [standard]
# - stderr aussi redirigé [sortie des erreurs]
exec > >(tee -a "$LOG_FILE_SCRIPT") 2>&1

# --- Mises à jour ---

# Exécuter directement l’analyse (affichage immédiat au lancement)
fetch_git_info || { echo "⚠️ Impossible de récupérer l'état Git"; }
analyze_update_status

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
            RCLONE_OPTS+=(--dry-run)
            shift
            ;;
        --update-forced)
            FORCE_UPDATE=true
            shift
            # Si une branche est fournie juste après, on la prend (switch)
            [[ $# -gt 0 && ! "$1" =~ ^-- ]] && FORCE_BRANCH="$1" && shift
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


###############################################################################
# 3. Actions dépendantes des arguments
###############################################################################

# Gestion des mises à jour selon les options passées
if [[ "$FORCE_UPDATE" == true ]]; then
    if update_to_latest_branch; then
        # --- Une mise à jour a été effectuée → relance du script ---
        # On reconstruit les arguments pour s'assurer que --mailto est conservé
        NEW_ARGS=()

        # Conserver spécifiquement l'option mail si elle est définie (sinon elle est perdue...)
        [[ -n "$MAIL_TO" ]] && NEW_ARGS+=(--mailto="$MAIL_TO")

        # Conserver toutes les autres options initiales
        for arg in "$@"; do
            # On évite de doubler --mailto si déjà présent
            [[ "$arg" == --mailto=* ]] && continue
            NEW_ARGS+=("$arg")
        done

        # Relance propre du script avec tous les arguments reconstruits
        exec "$0" "${NEW_ARGS[@]}"
    fi
fi

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && email_check "$MAIL_TO"

# Vérif msmtp (seulement si mail_to est défini)
if [[ -n "$MAIL_TO" ]]; then
    if ! check_msmtp_installed; then
        die 10 "❌ msmtp n'est pas installé."
    fi

    if ! check_msmtp_configured >/dev/null; then
        die 22 "❌ msmtp est requis mais aucune configuration valide n'a été trouvée."
    fi
fi

# Si aucun argument → menu interactif
if [[ $# -eq 0 ]]; then
    source "$SCRIPT_DIR/menu.sh"
fi


###############################################################################
# 4. Vérifications fonctionnelles
###############################################################################

# Vérif rclone
check_rclone
check_rclone_config

# On créait un dossier temporaire de manière temporaire
TMP_JOBS_DIR=$(mktemp -d)

# Création des répertoires nécessaires
if [[ ! -d "$TMP_RCLONE" ]]; then
    if ! mkdir -p "$TMP_RCLONE" 2>/dev/null; then
        die 1 "$MSG_TMP_RCLONE_CREATE_FAIL : $TMP_RCLONE"
    fi
fi

#Vérification de la présence du répertoire temporaire
if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        die 2 "$MSG_LOG_DIR_CREATE_FAIL : $LOG_DIR"
    fi
fi

# Vérifications initiales
if [[ ! -f "$JOBS_FILE" ]]; then
    die 3 "$MSG_FILE_NOT_FOUND : $JOBS_FILE"
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    die 4 "$MSG_FILE_NOT_READ : $JOBS_FILE"
fi


###############################################################################
# 5. Exécution des jobs rclone
# Sourcing
###############################################################################

source "$SCRIPT_DIR/functions/jobs_functions.sh"
source "$SCRIPT_DIR/jobs.sh"


###############################################################################
# 6. Traitement des emails
###############################################################################

if [[ -n "$MAIL_TO" ]]; then
    send_email_if_needed "$GLOBAL_HTML_BLOCK"
fi


###############################################################################
# 7. Suite des opérations
###############################################################################

# Purge inconditionnel des fichiers anciens (sous-dossiers inclus)
find "$TMP_RCLONE" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

# Affichage récapitulatif à la sortie
trap 'print_summary_table' EXIT

exit $ERROR_CODE