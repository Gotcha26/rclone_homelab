#!/usr/bin/env bash

set -uo pipefail

# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################


# === Initialisation minimale ===

# --- GARDE-FOU getcwd + détection dossier script ---
cd / 2>/dev/null || true   # si PWD invalide, se placer dans un répertoire sûr
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")" || exit 1

source "$SCRIPT_DIR/bootstrap.sh" # Source tout le reste avec configuration local incluse





echo "DEBUG: SCRIPT_DIR=$SCRIPT_DIR"
echo "DEBUG: DIR_CONF_LOCAL_FILE=$DIR_CONF_LOCAL_FILE"
echo "DEBUG: VARS_TO_VALIDATE=${VARS_TO_VALIDATE[*]}"
declare -p DIR_CONF_LOCAL_FILE DIR_CONF_DEV_FILE DIR_SECRET_FILE VARS_TO_VALIDATE 2>/dev/null













# Valeurs par défaut si les variables ne sont pas définies
: "${DEBUG_INFOS:=false}"
: "${DEBUG_MODE:=false}"
: "${DISPLAY_MODE:=soft}"
: "${ACTION_MODE:=auto}"

# Mise à jour des modes si nécessaire (DEBUG)
[[ "$DEBUG_INFOS" == true || "$DEBUG_MODE" == true ]] && DISPLAY_MODE="hard"
[[ "$DEBUG_MODE" == true ]] && ACTION_MODE="manu"

TMP_JOBS_DIR=$(mktemp -d)    # Dossier temporaire effémère. Il est supprimé à la fermeture.

# === Tableau récatitulatif des variables locale avec correction

print_table_vars VARS_TO_VALIDATE
# [[ "$DEBUG_INFOS" == true ]] && print_table_vars VARS_TO_VALIDATE
read -p "⏸ Pause : appuie sur Entrée pour continuer..." _
control_local_config

# === Initialisation du dispositif d'affichage ===

print_logo                   # Affichage du logo/bannière suivi de la version installée
print_fancy --align "right" "$(get_current_version)"

set_validation_vars          # Mise en tableau des variables en vue de leur examen
make_scripts_executable      # Rendre le script update/standalone_updater.sh exécutable

# --- ↓ DEBUG ↓ ---

if [[ "$DEBUG_INFOS" == "true" || "$DEBUG_MODE" == "true" ]]; then
    show_debug_header
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
        --verbose)
            LAUNCH_MODE="verbose"
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
        --discord-url=*)
            DISCORD_WEBHOOK_URL="${1#*=}"
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
    MENU_RESULT=$?
    if [[ $MENU_RESULT -eq 99 ]]; then
        echo
        echo "👋  Bonne journée à vous. 👋"
        echo
        exit 0
    else
        scroll_down             # Pas de clear
        [[ "${DEBUG_INFOS:-}" == "true" ]] && print_fancy --theme "debug_info" "Poursuite post-menu"
        add_rclone_opts         # Ajouter des options à rclone (dry-run)
    fi
fi

load_optional_configs   # Rappel des configurations locales (surcharge après le menu et/ou pour le mode full auto)

###############################################################################
# 4. Vérifications fonctionnelles
###############################################################################

# Correction arbitraire des variables utilisateurs (locales) par défaut
validate_vars VARS_TO_VALIDATE[@]

# Vérification du mail fourni + msmtp dans ce cas.
check_mail_bundle

# Vérif rclone
check_rclone_installed
check_rclone_configured

# Création des répertoires nécessaires
# Vérification de la présence du répertoire temporaire
# Vérifications initiales
create_temp_dirs
check_jobs_file hard


###############################################################################
# 5. Exécution des jobs rclone
###############################################################################

source "$SCRIPT_DIR/jobs.sh"


###############################################################################
# 6. Traitement des emails
###############################################################################

[[ -n "$MAIL_TO" ]] && send_email_if_needed "$GLOBAL_HTML_BLOCK"


###############################################################################
# 7. Suite des opérations
###############################################################################

# Purge inconditionnel des fichiers anciens (sous-dossiers inclus)
find "$DIR_TMP" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

print_summary_table

exit $ERROR_CODE