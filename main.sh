#!/usr/bin/env bash

set -uo pipefail

# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################


# === Initialisation minimale ===

#  GARDE-FOU getcwd + détection dossier script
cd / 2>/dev/null || true   # si PWD invalide, se placer dans un répertoire sûr
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")" || exit 1

source "$SCRIPT_DIR/bootstrap.sh" # Source tout le reste avec configuration local incluse

# ===

# Tableau associatif : varaibles locales utilisateur avec les règles
VARS_TO_VALIDATE=(
    "DRY_RUN:bool:false"
    "MAIL_TO:''"
    "DISCORD_WEBHOOK_URL:''"
    "FORCE_UPDATE:bool:false"
    "FORCE_BRANCH:''"
    "ACTION_MODE:auto|manu:auto"
    "DISPLAY_MODE:soft|verbose|hard:soft"
    "TERM_WIDTH_DEFAULT:80-120:80"
    "LOG_RETENTION_DAYS:1-15:14"
    "LOG_LINE_MAX:100-10000:1000"
    "EDITOR:nano|micro:nano"
    "DEBUG_INFOS:bool:false"
    "DEBUG_MODE:bool:false"
)

# SECURITE - Arbitraire - Valeurs par défaut si les variables ne sont pas définies (avant le contrôle/correction)
: "${DEBUG_INFOS:=false}"
: "${DEBUG_MODE:=false}"
: "${DISPLAY_MODE:=soft}"
: "${ACTION_MODE:=auto}"

# Association des modes si nécessaire (DEBUG)
[[ "$DEBUG_INFOS" == true || "$DEBUG_MODE" == true ]] && DISPLAY_MODE="hard"
[[ "$DEBUG_MODE" == true ]] && ACTION_MODE="manu"

TMP_JOBS_DIR=$(mktemp -d)    # Dossier temporaire effémère. Il est supprimé à la fermeture.

# === Initialisation du dispositif d'affichage ===

print_banner  # Affichage du logo/bannière suivi de la version installée
print_fancy --align right --style italic "$(get_current_version)"

# Menu/infod DEBUG
if [[ "$DEBUG_INFOS" == "true" || "$DEBUG_MODE" == "true" ]]; then
    show_debug_header
fi

# Validation des variables locale
if ! [[ $ACTION_MODE == "manu" ]]; then
    validate_vars VARS_TO_VALIDATE   # Menu de correction (si détecté comme étant nécessaire)
else
    control_local_config             # Processus de correction automatique
fi

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
            ACTION_MODE="auto"
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