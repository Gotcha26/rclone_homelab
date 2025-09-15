#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement

export GIT_PAGER=cat

# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# === Initialisation minimale ===

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/config/config.main.conf"
source "$SCRIPT_DIR/config/global.conf"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/core.sh"
source "$SCRIPT_DIR/update/updater.sh"

# Surchage la configuration local
load_optional_configs

# ===

# Informe de la surchage locale prise en compte
show_optional_configs

# Sourcing intermédiaire
source "$SCRIPT_DIR/export/mail.sh"
source "$SCRIPT_DIR/export/discord.sh"

# Logger uniquement les erreurs stderr
# Création du dossier logs si absent
# mkdir -p "$DIR_LOG"
# exec 2> >(tee -a "$DIR_LOG_FILE_SCRIPT" >&2)

# Affichage du logo/bannière
print_logo

# On créait un dossier temporaire de manière temporaire. Il est supprimé à la fermeture.
TMP_JOBS_DIR=$(mktemp -d)

# --- ↓ DEBUG ↓ ---
if [[ "$DEBUG_MODE" == "true" ]]; then 
    TMP_JOBS_DIR="$SCRIPT_DIR/tmp_jobs_debug"
    mkdir -p "$TMP_JOBS_DIR"
fi 

if [[ "$DEBUG_INFOS" == "true" ]]; then 
    print_fancy --theme "info" --fg "black" --bg "white" "DEBUG: DIR_LOG_FILE_SCRIPT = $DIR_LOG_FILE_SCRIPT"
fi 
# --- ↑ DEBUG ↑ ---

# === Mises à jour ===

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
        --force-update)
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

# Si aucun argument → menu interactif
if [[ $# -eq 0 ]]; then
    bash "$SCRIPT_DIR/menu.sh"
fi


###############################################################################
# 4. Vérifications fonctionnelles
###############################################################################

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

# Vérif rclone
check_rclone_installed
check_rclone_configured

# Création des répertoires nécessaires
#Vérification de la présence du répertoire temporaire
# Vérifications initiales
post_init_checks


###############################################################################
# 5. Exécution des jobs rclone
# Sourcing
###############################################################################

source "$SCRIPT_DIR/functions/jobs_f.sh"
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
find "$DIR_TMP" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

# Affichage récapitulatif à la sortie seulement si exécution éffective
if [[ "${BATCH_EXEC:-false}" == true ]]; then
    print_summary_table
fi

exit $ERROR_CODE