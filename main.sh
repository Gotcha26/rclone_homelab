#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement


# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# Initialisation de variables. Elles sont écrasé par la configuration personnalisée si présente.
FORCE_UPDATE="false"
UPDATE_TAG="false"
DRY_RUN=false
LAUNCH_MODE=""

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/conf.sh"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/init.sh"
source "$SCRIPT_DIR/export/mail.sh"
source "$SCRIPT_DIR/export/discord.sh"

# Création du dossier logs si absent
mkdir -p "$LOG_DIR"
# --- DEBUG ---
# TMP_JOBS_DIR="$SCRIPT_DIR/tmp_jobs_debug"
# mkdir -p "$TMP_JOBS_DIR"
# --- DEBUG ---

# On créait un dossier temporaire de manière temporaire
TMP_JOBS_DIR=$(mktemp -d)

# ---- Journal log général (sauf rclone qui a un log dédié) ----

# Redirige toute la sortie du script
# - stdout vers tee (console + fichier) [standard]
# - stderr aussi redirigé [sortie des erreurs]
exec > >(tee -a "$LOG_FILE_SCRIPT") 2>&1

# Initialise et informe de la branch en cours utilisée
detect_branch

# Sourcing pour les updates
source "$SCRIPT_DIR/update/updater.sh"


###############################################################################
# 2. Parsing complet des arguments
# Lecture des options du script
###############################################################################
# Drpeau
INTERACTIVE_MODE=false
[[ $# -eq 0 ]] && INTERACTIVE_MODE=true

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

###############################################################################
# 3. Vérifications dépendantes des arguments
###############################################################################

# Définition arbitraire pour le résultat des MAJ à faire ou non
update_check_result=0

# Gestion des mises à jour selon les options passées
if [[ "$FORCE_UPDATE" == true ]]; then
    if update_force_branch; then
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
elif [[ "$UPDATE_TAG" == true ]]; then
    update_to_latest_tag  # appel explicite
else
    update_check  # juste informer
fi

update_check_result=$?  # récupère le code de retour de update_check

# Inscription de l'option dry-run (rclone) si demandée
$DRY_RUN && RCLONE_OPTS+=(--dry-run)

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && email_check "$MAIL_TO"

# Vérif msmtp (seulement si mail)
if [[ -n "$MAIL_TO" ]]; then
    check_msmtp
    check_msmtp_config
fi

# Affiche le logo/bannière uniquement si on n'est pas en mode "automatique"
[[ "$LAUNCH_MODE" != "automatique" ]] && print_logo


###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
RUN_ALL_FROM_MENU=false

# --- Détection des dépendances ---
MISSING_RCLONE=false
MISSING_MSMTP=false

command -v rclone >/dev/null 2>&1 || MISSING_RCLONE=true
command -v msmtp >/dev/null 2>&1 || MISSING_MSMTP=true

# --- Construction dynamique du menu ---
MENU_OPTIONS=()
MENU_ACTIONS=()

# Fonction pour ajouter des options
add_option() {
    MENU_OPTIONS+=("$1")
    MENU_ACTIONS+=("$2")
}

if rclone_configured; then
    add_option "Afficher la configuration rclone" "show_rclone_config"
fi

if msmtp_configured; then
    add_option "Afficher la configuration msmtp" "show_msmtp_config"
fi


if jobs_configured; then
    add_option "Lancer tous les jobs (sans plus attendre ni options)" "run_all_jobs"
    add_option "Lister les jobs configurés" "list_jobs"
fi

if [[ "$MISSING_RCLONE" == true || "$MISSING_MSMTP" == true ]]; then
    add_option "Installer les dépendances manquantes (rclone/msmtp)" "install_missing_deps"
fi

if [[ "$update_check_result" -eq 1 ]]; then
    if [[ "$BRANCH" == "main" ]]; then
        add_option "Mettre à jour vers la dernière release (tag)" "update_to_latest_tag"
    else
        add_option "Mettre à jour la branche '$BRANCH' (force branch)" "update_force_branch"
    fi
fi

add_option "Afficher les logs du dernier run" "show_logs"
add_option "Afficher l'aide" "show_help"
add_option "Quitter" "exit_script"

# --- option invisible : init config locale ---
if [[ ! -f "$SCRIPT_DIR/config/config.dev.sh" ]]; then
    MENU_ACTIONS+=("init_config_local")  # ajout à la liste des actions, pas d'affichage
fi

# --- Affichage du menu ---
echo
echo "======================================="
echo "     🚀  Rclone Homelab Manager"
echo "======================================="
echo

for i in "${!MENU_OPTIONS[@]}"; do
    echo "$((i+1))) ${MENU_OPTIONS[$i]}"
done

echo
read -rp "Votre choix [1-${#MENU_OPTIONS[@]}] : " choice

# --- Validation et exécution ---
if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#MENU_OPTIONS[@]} )); then
    action="${MENU_ACTIONS[$((choice-1))]}"
    case "$action" in
        RUN_ALL_FROM_MENU=true)
            RUN_ALL_FROM_MENU=true
            ;;
        list_jobs)
            list_jobs
            exit 0
            ;;
        show_logs)
            tail -n 50 "$LOG_FILE_INFO" > /dev/tty
            exit 0
            ;;    # Redirection vers stdout uniquement
        show_rclone_config)
            [[ -f "$RCLONE_CONF" ]] && cat "$RCLONE_CONF" || echo "⚠️ Fichier rclone introuvable ($RCLONE_CONF)"
            exit 0
            ;;
        show_msmtp_config)
            [[ -f "$MSMTP_CONF" ]] && cat "$MSMTP_CONF" || echo "⚠️ Fichier msmtp introuvable ($MSMTP_CONF)"
            exit 0
            ;;
        show_help)
            show_help
            exit 0
            ;;
        install_missing_deps)
            install_missing_deps
            exit 0
            ;;
        update_to_latest_tag)
            update_to_latest_tag
            exit 0
            ;;
        update_force_branch)
            update_force_branch
            exit 0
            ;;
        exit_script)
            echo "Bye 👋"
            exit 0
            ;;
        init_config_local)
            init_config_local;
            exit 0
            ;;     # option invisible
        *)
            echo "Choix invalide."
            exit 5
            ;;
    esac
else
    echo "Choix invalide."
    exit 5
fi


###############################################################################
# 4. Vérifications fonctionnelles
###############################################################################

if [[ "$RUN_ALL_FROM_MENU" == true ]]; then
    # Drapeau
    echo ">> Mode interactif : exécution directe des jobs"
fi

# Vérif rclone
check_rclone
check_rclone_config

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