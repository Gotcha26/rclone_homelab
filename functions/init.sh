#!/usr/bin/env bash

###############################################################################
# Fonction help (aide)
###############################################################################

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options :
  --auto             Lance le script en mode automatique (pas d'affichage du logo)
  --mailto=ADRESSE   Envoie un rapport par e-mail à l'adresse fournie
  --dry-run          Simule la synchronisation sans transférer ni supprimer de fichiers
  -h, --help         Affiche cette aide et quitte

Description :
  Ce script lit la liste des jobs à exécuter depuis le fichier :
      $JOBS_FILE
  Chaque ligne doit contenir :
      chemin_source|remote:chemin_destination
  Les lignes vides ou commençant par '#' sont ignorées.

  Exemple de ligne :
      /home/user/Documents|OneDrive:Backups/Documents

Fonctionnement :
  - Vérifie et teste les pré-requis au bon déroulement des opérations.
  - Lance 'rclone sync' pour chaque job avec les options par défaut
  - Affiche la sortie colorisée dans le terminal
  - Génère un fichier log INFO dans : $LOG_DIR
  - Si --mailto est fourni et msmtp est configuré, envoie un rapport HTML
EOF
}


###############################################################################
# Fonction qui corrige la branch de travail en cours
###############################################################################
detect_branch() {
    if [[ -f "$SCRIPT_DIR/config/config.local.sh" ]]; then
        BRANCH="local"
        source "$SCRIPT_DIR/config/config.local.sh"
        print_fancy --align "center" --bg "yellow" --fg "black" --highlight \
        "⚠️  MODE LOCAL ACTIVÉ – Branche = $BRANCH ⚠️ "
    elif [[ -f "$SCRIPT_DIR/config/config.dev.sh" ]]; then
        BRANCH="dev"
        source "$SCRIPT_DIR/config/config.dev.sh"
        print_fancy --align "center" --bg "yellow" --fg "black" --highlight \
        "⚠️  MODE DEV ACTIVÉ – Branche = $BRANCH ⚠️ "
    else
        BRANCH="main"
        source "$SCRIPT_DIR/config/config.main.sh"
    fi
}


###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################

print_logo() {
    echo
    echo
    local RED="$(get_fg_color red)"
    local RESET="$(get_fg_color reset)"

    # Règle "tout sauf #"
    sed -E "s/([^#])/${RED}\1${RESET}/g" <<'EOF'
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::'######:::::'#######:::'########:::'######:::'##::::'##:::::'###:::::::::
:::::'##... ##:::'##.... ##::... ##..:::'##... ##:: ##:::: ##::::'## ##::::::::
::::: ##:::..:::: ##:::: ##::::: ##::::: ##:::..::: ##:::: ##:::'##:. ##:::::::
::::: ##::'####:: ##:::: ##::::: ##::::: ##:::::::: #########::'##:::. ##::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##:::::::: ##.... ##:: #########::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##::: ##:: ##:::: ##:: ##.... ##::::::
:::::. ######::::. #######:::::: ##:::::. ######::: ##:::: ##:: ##:::: ##::::::
::::::......::::::.......:::::::..:::::::......::::..:::::..:::..:::::..:::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
    echo
    echo
}


###############################################################################
# Fonction : Vérifie la présence de l'installation de rclone
# Propose de l'installer si besoin
###############################################################################
check_rclone() {
    local force_install=${1:-false}

    if ! command -v rclone >/dev/null 2>&1 || [[ "$force_install" == true ]]; then
        echo
        echo "⚠️  rclone n'est pas installé ou installation forcée."

        if [[ "$force_install" != true ]]; then
            read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
            REPLY=${REPLY,,}  # met en minuscules
        else
            REPLY="y"
        fi

        if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
            echo "📦  Installation de rclone en cours..."
            sudo apt update && sudo apt install rclone -y
            if [[ $? -eq 0 ]]; then
                echo "✅  rclone a été installé avec succès !"
            else
                die 11 "Une erreur est survenue lors de l'installation de rclone."
            fi
        else
            die 11 "rclone n'est toujours pas installé. Le script va s'arrêter."
        fi
    fi
}


###############################################################################
# Fonction : Vérifie la configuration initiale de rclone
# Propose de l'éditer si besoin
###############################################################################
check_rclone_config() {
    local conf_file="${RCLONE_CONFIG_DIR:-$HOME/.config/rclone/rclone.conf}"

    if [[ ! -f "$conf_file" || ! -s "$conf_file" ]]; then
        echo
        echo "⚠️  rclone est installé mais n'est pas configuré."
        echo "Vous devez configurer rclone avant de poursuivre."
        echo "Pour configurer, vous pouvez exécuter : rclone config"
        echo

        read -rp "Voulez-vous éditer directement le fichier de configuration rclone ? [y/N] : " EDIT_REPLY
        EDIT_REPLY=${EDIT_REPLY,,}

        if [[ "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
            </dev/tty >/dev/tty 2>&1 ${EDITOR:-nano} "$conf_file"
            echo "Fichier de configuration édité. Relancez le script après avoir sauvegardé."
        else
            echo "Le script va s'arrêter. Configurez rclone et relancez le script."
        fi
        die 12 "rclone est installé mais n'est pas configuré. Veuillez exécuter : rclone config"
    fi
}


###############################################################################
# Fonction : Vérifie la présence de l'installation de msmtp
# Propose de l'installer si besoin
###############################################################################
check_msmtp() {
    local force_install=${1:-false}

    if ! command -v msmtp >/dev/null 2>&1 || [[ "$force_install" == true ]]; then
        echo
        echo "⚠️  msmtp n'est pas installé ou installation forcée."

        if [[ "$force_install" != true ]]; then
            read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
            REPLY=${REPLY,,}  # met en minuscules
        else
            REPLY="y"
        fi

        if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
            echo "📦  Installation de msmtp en cours..."
            sudo apt update && sudo apt install msmtp msmtp-mta -y
            if [[ $? -eq 0 ]]; then
                echo "✅  msmtp a été installé avec succès !"
            else
                die 10 "Une erreur est survenue lors de l'installation de msmtp."
            fi
        else
            die 10 "msmtp n'est toujours pas installé. Le script va s'arrêter."
        fi
    fi
}


###############################################################################
# Fonction : Vérifie la configuration initiale de msmtp
# Propose de l'éditer si besoin
###############################################################################
check_msmtp_config() {
    local conf_file=""

    if [[ -f "$HOME/.msmtprc" && -s "$HOME/.msmtprc" ]]; then
        conf_file="$HOME/.msmtprc"
    elif [[ -f "/etc/msmtprc" && -s "/etc/msmtprc" ]]; then
        conf_file="/etc/msmtprc"
    fi

    if [[ -z "$conf_file" ]]; then
        echo
        echo "⚠️  msmtp est installé mais n'est pas configuré."
        echo "Vous devez configurer msmtp avant de poursuivre."
        echo "Pour configurer, vous pouvez exécuter : msmtp --configure"
        echo "Ou éditer le fichier suivant :"
        echo "    ~/.msmtprc (perso) ou /etc/msmtprc (global)"
        echo

        read -rp "Voulez-vous éditer directement le fichier de configuration msmtp ? [y/N] : " EDIT_REPLY
        EDIT_REPLY=${EDIT_REPLY,,}

        if [[ "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
            </dev/tty >/dev/tty 2>&1 ${EDITOR:-nano} "$HOME/.msmtprc"
            echo "Fichier de configuration édité. Relancez le script après avoir sauvegardé."
        else
            echo "Le script va s'arrêter. Configurez msmtp et relancez le script."
        fi
        die 22 "msmtp est installé mais n'est pas configuré. Veuillez exécuter : msmtp --configure"
    fi
}


###############################################################################
# Fonctions de détection des configs
###############################################################################
rclone_configured() {
    [[ -f "$RCLONE_CONF" ]] && [[ -s "$RCLONE_CONF" ]]
}

msmtp_configured() {
    [[ -f "$MSMTP_CONF" ]] && [[ -s "$MSMTP_CONF" ]]
}


###############################################################################
# Fonction : Vérifier la présence de jobs configurés
###############################################################################
jobs_configured() {
    [[ -f "$JOBS_CONF" ]] && [[ -s "$JOBS_CONF" ]]
}


###############################################################################
# Fonction : Vérifier la présence de jobs configurés
###############################################################################
jobs_configured() {
    [[ -f "$JOBS_CONF" ]] && [[ -s "$JOBS_CONF" ]]
}


###############################################################################
# Fonction : Installer les dépendances manquantes (rclone / msmtp)
###############################################################################
install_missing_deps() {
    check_rclone true
    check_msmtp true
    echo "🎉 Dépendances installées."
}


###############################################################################
# Fonction d'affichage du tableau récapitulatif avec bordures
###############################################################################
print_aligned_table() {
    local label="$1"
    local value="$2"
    local label_width=20

    # Calcul de la longueur du label
    local label_len=${#label}
    local spaces=$((label_width - label_len))

    # Génère les espaces à ajouter après le label
    local padding=""
    if (( spaces > 0 )); then
        padding=$(printf '%*s' "$spaces" '')
    fi

    # Affiche la ligne avec label + padding + " : " + value
    printf "%s%s : %s\n" "$label" "$padding" "$value"
}


###############################################################################
# Fonction : Affiche le résumé de la tâche
###############################################################################
print_summary_table() {
    END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "INFOS"
    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    print_aligned_table "Date / Heure début" "$START_TIME"
    print_aligned_table "Date / Heure fin" "$END_TIME"
    print_aligned_table "Mode de lancement" "$LAUNCH_MODE"
    print_aligned_table "Nb. de jobs traités" "${EXECUTED_JOBS} / ${#JOBS_LIST[@]}"
    print_aligned_table "Code erreur" "$ERROR_CODE"
    print_aligned_table "Dossier" "${LOG_DIR}/"
    print_aligned_table "Log script" "$FILE_SCRIPT"
    print_aligned_table "Log mail" "$FILE_MAIL"
    print_aligned_table "Log rclone" "$FILE_INFO"

    if [[ -n "$MAIL_TO" ]]; then
        print_aligned_table "Email envoyé à" "$MAIL_TO"
        print_aligned_table "Sujet email" "$SUBJECT_RAW"
    fi

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_PROCESSED"
    else
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_ABORDED"
    fi

    [[ "$DRY_RUN" == true ]] && print_aligned_table "Simulation (dry-run)" "$MSG_DRYRUN"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    # Ligne finale avec couleur fond jaune foncé, texte noir, centrée
    print_fancy --bg "yellow" --fg "black" "$MSG_END_REPORT"
    echo
}