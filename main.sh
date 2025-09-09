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

# Affiche le logo/bannière uniquement si on n'est pas en mode "automatique"
[[ "$LAUNCH_MODE" != "automatique" ]] && print_logo


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

# Inscription de l'option dry-run (rclone) si demandée
$DRY_RUN && RCLONE_OPTS+=(--dry-run)

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && email_check "$MAIL_TO"

# Vérif msmtp (seulement si mail)
if [[ -n "$MAIL_TO" ]]; then
    check_msmtp
    check_msmtp_config
fi

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
RUN_ALL_FROM_MENU=false

if [[ "$INTERACTIVE_MODE" == true ]]; then
    echo
    echo "======================================="
    echo "     🚀  Rclone Homelab Manager"
    echo "======================================="
    echo
    echo "1) Lancer tous les jobs (sans plus attendre ni options)"
    echo "2) Lister les jobs configurés"
    echo "3) Afficher les logs du dernier run"
    echo "4) Afficher la configuration rclone"
    echo "5) Afficher la configuration msmtp"
    echo "6) Afficher l'aide"
    echo "7) Installer les dépendances (rclone + msmtp)"
    echo "8) Mettre à jour Rclone Homelab (si release disponible)"
    echo "9) "
    echo "0) Quitter"
    echo
    echo "A part le choix #1 toutes les autres options fermeront ce menu."
    echo
    read -rp "Votre choix [0-8] : " choice

    case "$choice" in
        1)
            echo
            echo ">> Lancement de tous les jobs..."
            RUN_ALL_FROM_MENU=true
            ;;
        2)
            echo
            echo ">> Liste des jobs :"
            for idx in "${!JOBS_LIST[@]}"; do
                job="${JOBS_LIST[$idx]}"
                IFS='|' read -r src dst <<< "$job"
                printf "  [%02d] %s → %s\n" "$((idx+1))" "$src" "$dst"
            done
            exit 0
            ;;
        3)
            echo
            echo ">> Derniers logs :"
            tail -n 50 "$LOG_FILE_INFO"
            exit 0
            ;;
        4)
            echo
            echo ">> Configuration rclone :"
            if [[ -f "$RCLONE_CONF" ]]; then
                cat "$RCLONE_CONF"
            else
                echo "⚠️  Fichier de configuration rclone introuvable ($RCLONE_CONF)"
            fi
            exit 0
            ;;
        5)
            echo
            echo ">> Configuration msmtp :"
            if [[ -f "$MSMTP_CONF" ]]; then
                cat "$MSMTP_CONF"
            else
                echo "⚠️  Fichier de configuration msmtp introuvable ($MSMTP_CONF)"
            fi
            exit 0
            ;;
        6)
            echo
            show_help
            exit 0
            ;;
        7)
            echo
            echo ">> Installation des dépendances..."
            echo
            echo
            echo "Installation de rclone"
            echo
            if command -v rclone >/dev/null 2>&1; then
                echo "✅ rclone est déjà installé ($(rclone version | head -n1))"
            else
                sudo apt-get update && sudo apt-get install -y rclone
                if command -v rclone >/dev/null 2>&1; then
                    echo "🎉 rclone installé avec succès ($(rclone version | head -n1))"
                else
                    echo "❌ Échec de l'installation de rclone"
                fi
            fi
            echo
            echo
            echo "Installation de msmtp..."
            if command -v msmtp >/dev/null 2>&1; then
                echo "✅ msmtp est déjà installé ($(msmtp --version | head -n1))"
            else
                sudo apt-get update && sudo apt-get install -y msmtp msmtp-mta
                if command -v msmtp >/dev/null 2>&1; then
                    echo "🎉 msmtp installé avec succès ($(msmtp --version | head -n1))"
                else
                    echo "❌ Échec de l'installation de msmtp"
                fi
            fi
            echo
            exit 0
            ;;
        8)
            echo
            echo ">> Mise à jour vers la dernière release"
            echo
            [[ "$UPDATE_TAG" == true ]]
            update_to_latest_tag  # appel explicite
            exit 0
            ;;
        0)
            echo
            echo "Bye 👋"
            exit 0
            ;;
        *)
            echo
            echo "Choix invalide."
            exit 1
            ;;
    esac


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