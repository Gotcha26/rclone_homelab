#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement


# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# === Initialisation minimale ===

source "$SCRIPT_DIR/bootstrap.sh"

# ===

# Affichage du logo/bannière
print_logo

# On créait un dossier temporaire de manière temporaire. Il est supprimé à la fermeture.
TMP_JOBS_DIR=$(mktemp -d)

# Mise en tableau des variables locales
set_validation_vars

# Rendre le script update/standalone_updater.sh exécutable
make_scripts_executable

# --- ↓ DEBUG ↓ ---

if [[ "$DEBUG_INFOS" == "true" || "$DEBUG_MODE" == "true" ]]; then
    show_debug_header
fi

# --- ↑ DEBUG ↑ ---

# === Mises à jour ===

# Exécuter directement l’analyse (affichage immédiat au lancement)
fetch_git_info || { echo "⚠️ Impossible de récupérer l'état Git"; }
analyze_update_status

# Appel de la fonction de validation des variables locales
if ! print_table_vars_invalid VARS_TO_VALIDATE; then
    # Problème
    echo

    # Arrête le script si invalide ET si DEBUG_INFOS == "false"
    if [[ "$DEBUG_INFOS" == "false" ]]; then
        die 30 "Erreur : Configuration invalide. Vérifiez les variables (locales)."
    else
        print_fancy --theme "error" "Configuration invalide. Vérifiez les variables (locales)."
        echo
        read -p "⏸ Pause : appuie sur Entrée pour continuer..." _
    fi
else
    # Pas de soucis
    if [[ "$DEBUG_INFO" == "true" || "$DEBUG_MODE" == "true" ]]; then
        echo
        print_fancy --theme "ok" "Les variables locales sont validées"
    fi
fi



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
    fi
fi


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

print_summary_table

exit $ERROR_CODE