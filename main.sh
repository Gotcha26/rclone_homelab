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

# SECURITE - Arbitraire - Valeurs par défaut si les variables ne sont pas définies (avant le contrôle/correction)
: "${DEBUG_INFOS:=false}"
: "${DEBUG_MODE:=false}"
: "${DISPLAY_MODE:=soft}"
: "${ACTION_MODE:=manu}"

# Association des modes si nécessaire (DEBUG)
[[ "$DEBUG_INFOS" == true || "$DEBUG_MODE" == true ]] && DISPLAY_MODE="hard"
[[ "$DEBUG_MODE" == true ]] && ACTION_MODE="manu"

TMP_JOBS_DIR=$(mktemp -d)    # Dossier temporaire effémère. Il est supprimé à la fermeture.

# === Initialisation du dispositif d'affichage ===

print_banner  # Affichage du logo/bannière suivi de la version installée
print_fancy --align right --style italic "$(get_current_version)"

# Menu/info DEBUG
if [[ "$DEBUG_INFOS" == "true" || "$DEBUG_MODE" == "true" ]]; then
    show_debug_header
fi

# Validation des variables locale
if [[ $ACTION_MODE == "auto" ]]; then
    self_validation_local_variables VARS_TO_VALIDATE   # Processus de correction automatique
else
    menu_validation_local_variables VARS_TO_VALIDATE   # Menu de correction (si détecté comme étant nécessaire)
fi

# === Mises à jour ===

# Exécuter directement l’analyse (affichage immédiat au lancement)
update_check || display_msg "soft|verbose|hard" --theme warning "Impossible de récupérer l'état Git"


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
if [[ ${#ORIG_ARGS[@]} -eq 0 ]]; then
    bash "$SCRIPT_DIR/menu.sh"
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
    fi
else
    display_msg "verbose|hard" theme info "Pas d'appel au menu interactif."
fi


###############################################################################
# 4. Vérifications fonctionnelles
###############################################################################

# Boucle pour email
if [[ -n "$MAIL_TO" ]]; then
    display_msg "verbose|hard" "☛  Adresse email détectée, envoie d'un mail requis !"
    
    display_msg "verbose|hard" "☞  1/x Contrôle d'intégritation adresse email"
    if check_mail_format; then
        display_msg "soft" --theme ok "Email non validé."
        display_msg "verbose|hard" --theme error "L'adresse email saisie ne satisfait pas aux exigences et est rejetée."
        die 12 "Adresse email saisie invalide : $MAIL_TO"
    else
        display_msg "soft|verbose|hard" --theme ok "Email validé."

        display_msg "verbose|hard" "☞  2a/x Contrôle présence msmtp"
        if ! check_msmtp; then
            if [[ $ACTION_MODE == auto ]]; then
                display_msg "soft" --theme error "msmtp absent."
                display_msg "verbose|hard" --theme error "L'outil msmtp est obligatoire mais n'est pas détecté comme étant installé sur le système."
                die 13 "L'outil msmtp obligatoire mais détecté absent..."
            else
                display_msg "soft|verbose|hard" --theme warning "msmtp absent, proposition d'installation"

                display_msg "verbose|hard" "☞  2b/x Installation onlive de msmtp"
                echo
                read -e -rp "Voulez-vous installer msmtp maintenant (requis) ? [y/N] : " REPLY
                REPLY=${REPLY,,}
                if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
                    install_msmtp
                else
                    die 15 "msmtp est requis mais n'a pas été installé."
                fi
            fi
        else
            display_msg "soft|verbose|hard" --theme ok "L'outil msmtp est installé."

            display_msg "verbose|hard" "☞  3/x Lecture configuration msmtp"
            display_msg "verbose|hard" --theme warning "Ne garanti pas que le contenu soit correct !!!"
            if check_msmtp_configured; then
                if [[ $ACTION_MODE == auto ]]; then
                    display_msg "soft" --theme error "msmtp non ou mal configuré."
                    display_msg "verbose|hard" --theme error "L'outil msmtp semble être mal configuré ou son fichier de configuration absent/vide."
                    die 14 "L'outil msmtp non ou mal configuré."
                else
                    display_msg "soft|verbose|hard" --theme warning "msmtp absent, proposition de configuration"
                    configure_msmtp
                fi
            else
                display_msg "soft|verbose|hard" --theme ok "L'outil msmtp est configuré."
            fi
        fi
    fi
else
    display_msg "verbose|hard" --theme info "Aucun email fourni : pas besoin d'en envoyer un !"
fi
        

    



check_rclone_installed
check_rclone_configured
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