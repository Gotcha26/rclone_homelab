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

TMP_JOBS_DIR=$(mktemp -d)    # Dossier temporaire effémère. Il est supprimé à la fermeture.

# === Initialisation du dispositif d'affichage ===

print_banner  # Affichage du logo/bannière suivi de la version installée
check_update || display_msg "soft|verbose|hard" --theme warning "Impossible de récupérer l'état Git";


# Menu/info DEBUG
if [[ "$DEBUG_INFOS" == "true" || "$DEBUG_MODE" == "true" ]]; then
    show_debug_header
fi

# Validation des variables locale
if [[ $ACTION_MODE == "auto" ]]; then
    self_validation_local_variables VARS_TO_VALIDATE    # Processus de correction automatique
else                                                    # Menu de correction (si détecté comme étant nécessaire)
    if ! menu_validation_local_variables VARS_TO_VALIDATE; then 
        display_msg "verbose|hard" --theme info "Configuration des variables locale : passée."
    fi
fi


###############################################################################
# 2. Parsing complet des arguments
# Lecture des options du script
###############################################################################

ORIG_ARGS=("$@")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            ACTION_MODE="auto"
            shift
            ;;
        --mailto=*)
            MAIL_TO="${1#*=}"
            if [[ -z "$MAIL_TO" ]]; then
                print_fancy --theme error "Option --mailto= fournie mais vide."
                die 12 "Mauvaise formation de l'argument --mailto="
            fi
            shift
            ;;
        --mailto)
            print_fancy --theme error "Option --mailto requiert une adresse email (syntaxe: --mailto=adresse@domaine)."
            die 12 "Mauvaise formation de l'argument --mailto="
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
if [[ ${#ORIG_ARGS[@]} -eq 0 ]]; then
    source "$SCRIPT_DIR/menu.sh"
    MENU_RESULT=$?
    if [[ $MENU_RESULT -eq 99 ]]; then
        echo
        echo "👋  Bonne journée à vous. 👋"
        echo
        exit 0
    else
        scroll_down             # Pas de clear
        [[ $DEBUG_INFOS == true ]] && print_fancy --theme "debug_info" "Poursuite post-menu"
        load_optional_configs   # Rappel des configurations locales (surcharge après le menu et/ou pour le mode full auto)
        self_validation_local_variables VARS_TO_VALIDATE   # Processus de correction automatique
        ACTION_MODE="auto" # On oblige à passer en mode auto lorceque issue du menu interractif pour ne plus avoir d'interactions.
    fi
else
    display_msg "verbose|hard" --theme info "Pas d'appel au menu interactif."
fi


###############################################################################
# 4. Vérifications fonctionnelles, pre-traitement
###############################################################################

create_temp_dirs
check_and_prepare_email "$MAIL_TO"
check_rclone
check_jobs_file


###############################################################################
# 5. Exécution des jobs rclone
###############################################################################

source "$SCRIPT_DIR/jobs.sh"


###############################################################################
# 6. Traitement des emails
###############################################################################

[[ -n "$MAIL_TO" ]] && send_email "$GLOBAL_HTML_BLOCK"


###############################################################################
# 7. Suite des opérations
###############################################################################

# Purge inconditionnel des fichiers anciens (sous-dossiers inclus)
find "$DIR_TMP" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

print_summary_table

exit $ERROR_CODE
