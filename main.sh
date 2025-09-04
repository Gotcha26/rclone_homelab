#!/usr/bin/env bash

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement


# ###############################################################################
# 1. Initialisation par défaut
# ###############################################################################

# Résoudre le chemin réel du script (suivi des symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Sourcing global
source "$SCRIPT_DIR/conf.sh"
source "$SCRIPT_DIR/functions.sh"
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
    if force_update_branch; then
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
    check_update  # juste informer
fi

# Activation dry-run si demandé
$DRY_RUN && RCLONE_OPTS+=(--dry-run)

# Affiche le logo/bannière uniquement si on n'est pas en mode "automatique"
[[ "$LAUNCH_MODE" != "automatique" ]] && print_logo

# Vérifie l’email seulement si l’option --mailto est fournie
[[ -n "$MAIL_TO" ]] && check_email "$MAIL_TO"

# Vérification de la présence de rclone
if ! command -v rclone >/dev/null 2>&1; then
    echo
    echo "⚠️  rclone n'est pas installé sur votre système Debian/Ubuntu."
    
    read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
    REPLY=${REPLY,,}  # convertit en minuscule

    if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
        echo "Installation de rclone en cours..."
        sudo apt update && sudo apt install rclone -y
        if [[ $? -eq 0 ]]; then
            echo "✅ rclone a été installé avec succès !"
        else
            echo >&2 "❌ Une erreur est survenue lors de l'installation de rclone."
            ERROR_CODE=11
            exit $ERROR_CODE
        fi
    else
        echo >&2 "❌ rclone n'est toujours pas installé. Le script va s'arrêter."
        ERROR_CODE=11
        exit $ERROR_CODE
    fi
fi

# Vérification que rclone est configuré
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_DIR:-$HOME/.config/rclone/rclone.conf}"

if [[ ! -f "$RCLONE_CONFIG_FILE" || ! -s "$RCLONE_CONFIG_FILE" ]]; then
    echo
    echo "⚠️  rclone est installé mais n'est pas configuré."
    echo "Vous devez configurer rclone avant de poursuivre."
    echo "Pour configurer, vous pouvez exécuter : rclone config"
    echo

    read -rp \
    "Voulez-vous éditer directement le fichier de configuration rclone ? [y/N] : " \
    EDIT_REPLY

    EDIT_REPLY=${EDIT_REPLY,,}

    if [[ "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        ${EDITOR:-nano} "$RCLONE_CONFIG_FILE"
        echo "Fichier de configuration édité. Relancez le script après avoir sauvegardé."
    else
        echo "Le script va s'arrêter. Configurez rclone et relancez le script."
    fi

    ERROR_CODE=12
    exit $ERROR_CODE
fi

# Vérification de MSMTP seulement si --mailto est défini
if [[ -n "$MAIL_TO" ]]; then
    # Vérification que msmtp est installé
    if ! command -v msmtp >/dev/null 2>&1; then
        echo
        echo "⚠️  msmtp n'est pas installé sur votre système Debian/Ubuntu."
        
        read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
        REPLY=${REPLY,,}

        if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
            echo "Installation de msmtp en cours..."
            sudo apt update && sudo apt install msmtp msmtp-mta -y
            if [[ $? -eq 0 ]]; then
                echo "✅ msmtp a été installé avec succès !"
            else
                echo "❌ Une erreur est survenue lors de l'installation de msmtp."
                ERROR_CODE=21
                exit $ERROR_CODE
            fi
        else
            echo "❌ msmtp n'est toujours pas installé. Le script va s'arrêter."
            ERROR_CODE=21
            exit $ERROR_CODE
        fi
    fi

    # Vérification du fichier de configuration
    MSMTP_CONFIG_FILE="${MSMTP_CONFIG_FILE:-$HOME/.msmtprc}"
    if [[ ! -f "$MSMTP_CONFIG_FILE" || ! -s "$MSMTP_CONFIG_FILE" ]]; then
        echo
        echo "⚠️  msmtp est installé mais n'est pas configuré."
        echo "Vous devez configurer msmtp avant de poursuivre."
        echo "Pour configurer, vous pouvez exécuter : msmtp --configure"
        echo "Ou éditer le fichier suivant :"
        echo "    $MSMTP_CONFIG_FILE"
        echo

        read -rp \
        "Voulez-vous éditer directement le fichier de configuration msmtp ? [y/N] : " \
        EDIT_REPLY

        EDIT_REPLY=${EDIT_REPLY,,}

        if [[ "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
            ${EDITOR:-nano} "$MSMTP_CONFIG_FILE"
            echo "Fichier de configuration édité. Relancez le script après avoir sauvegardé."
        else
            echo "Le script va s'arrêter. Configurez msmtp et relancez le script."
        fi

        ERROR_CODE=22
        exit $ERROR_CODE
    fi
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
