#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement


# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/conf.sh"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/init.sh"
source "$SCRIPT_DIR/export/mail.sh"
source "$SCRIPT_DIR/export/discord.sh"

# Initialisation de variables
FORCE_UPDATE="false"
UPDATE_TAG="false"

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
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
if [[ $# -eq 0 ]]; then
    clear
    echo "======================================="
    echo "     🚀  Rclone Homelab Manager"
    echo "======================================="
    echo
    echo "1) Lancer tous les jobs"
    echo "2) Lister les jobs configurés"
    echo "3) Afficher les logs du dernier run"
    echo "4) Quitter"
    echo
    read -rp "Votre choix [1-4] : " choice

    case "$choice" in
        1)
            echo ">> Lancement de tous les jobs..."
            # Ici tu rappelles ton script en interne
            exec "$0" --run-all
            ;;
        2)
            echo ">> Liste des jobs :"
            for idx in "${!JOBS_LIST[@]}"; do
                job="${JOBS_LIST[$idx]}"
                IFS='|' read -r src dst <<< "$job"
                printf "  [%02d] %s → %s\n" "$((idx+1))" "$src" "$dst"
            done
            exit 0
            ;;
        3)
            echo ">> Derniers logs :"
            tail -n 50 "$LOG_FILE_INFO"
            exit 0
            ;;
        4)
            echo "Bye 👋"
            exit 0
            ;;
        *)
            echo "Choix invalide."
            exit 1
            ;;
    esac
fi


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

# Activation dry-run si demandé
$DRY_RUN && RCLONE_OPTS+=(--dry-run)

# Affiche le logo/bannière uniquement si on n'est pas en mode "automatique"
[[ "$LAUNCH_MODE" != "automatique" ]] && print_logo

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && email_check "$MAIL_TO"

# Vérif rclone
check_rclone
check_rclone_config

# Vérif msmtp (seulement si mail)
if [[ -n "$MAIL_TO" ]]; then
    check_msmtp
    check_msmtp_config
fi

# Création des répertoires nécessaires
if [[ ! -d "$TMP_RCLONE" ]]; then
    if ! mkdir -p "$TMP_RCLONE" 2>/dev/null; then
        print_fancy --theme "error" "$MSG_TMP_RCLONE_CREATE_FAIL : $TMP_RCLONE" >&2
        echo
        ERROR_CODE=1
        exit $ERROR_CODE
    fi
fi

#Vérification de la présence du répertoire temporaire
if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        print_fancy --theme "error" "$MSG_LOG_DIR_CREATE_FAIL : $LOG_DIR" >&2
        echo
        ERROR_CODE=2
        exit $ERROR_CODE
    fi
fi

# Vérifications initiales
if [[ ! -f "$JOBS_FILE" ]]; then
    print_fancy --theme "error" "$MSG_FILE_NOT_FOUND : $JOBS_FILE" >&2
    echo
    ERROR_CODE=3
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    print_fancy --theme "error" "$MSG_FILE_NOT_READ : $JOBS_FILE" >&2
    echo
    ERROR_CODE=4
    exit $ERROR_CODE
fi
if [[ ! -d "$TMP_RCLONE" ]]; then
    print_fancy --theme "error" "$MSG_TMP_NOT_FOUND : $TMP_RCLONE" >&2
    echo
    ERROR_CODE=5
    exit $ERROR_CODE
fi


###############################################################################
# 3. Exécution des jobs rclone
# Sourcing
###############################################################################

source "$SCRIPT_DIR/functions/jobs_functions.sh"
source "$SCRIPT_DIR/jobs.sh"


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
