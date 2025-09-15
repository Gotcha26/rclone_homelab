#!/usr/bin/env bash

###############################################################################
# Fonction help (aide)
###############################################################################

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options :
  --auto             Lance le script en mode automatique (A DEFINIR).
  --mailto=ADRESSE   Envoie un rapport par e-mail à l'adresse fournie.
  --dry-run          Simule la synchronisation sans transférer ni supprimer de fichiers.
  -h, --help         Affiche cette aide et quitte.
  --force-update     Mettre à jour automatiquement sur la branche en cours. Accèpte l'argument "branche"
  --update-tag       Mettre à jour automatiquement sur la release (version) disponnible.

Description :
  Ce script lit la liste des jobs à exécuter depuis le fichier :
      $DIR_JOBS_FILE
  Chaque ligne doit contenir :
      chemin_source|remote:chemin_destination
  Les lignes vides ou commençant par '#' sont ignorées.

  Exemple de ligne :
      /home/user/Documents|OneDrive:Backups/Documents

Fonctionnement :
  - Vérifie et teste les pré-requis au bon déroulement des opérations.
  - Lance 'rclone sync' pour chaque job avec les options par défaut
  - Affiche la sortie colorisée dans le terminal
  - Génère un fichier log INFO dans : $DIR_LOG
  - Si --mailto est fourni et msmtp est configuré, envoie un rapport HTML
EOF
}


###############################################################################
# Fonction charge dans l'ordre main > local > dev
###############################################################################
detect_config() {
    local display_mode="${DISPLAY_MODE:-simplified}"  # verbose / simplified / none

    CONFIGURATION="config.main.conf"
    source "$SCRIPT_DIR/config/config.main.conf"
    if [[ "$display_mode" == "verbose" ]]; then
        print_fancy --theme "info" --align "center" --bg "green" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION STANDARD – Fichier de configuration = $CONFIGURATION ℹ️ "
    fi

    if [[ -f "$DIR_FILE_CONF_LOCAL" ]]; then
        CONFIGURATION="$FILE_CONF_LOCAL"
        source "$DIR_FILE_CONF_LOCAL"
        [[ "$display_mode" == "verbose" ]] && print_fancy --theme "warning" --align "center" --bg "yellow" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION LOCALE ACTIVÉE – Fichier de configuration = $CONFIGURATION ⚠️ "
    fi

    if [[ -f "$DIR_FILE_CONF_DEV" ]]; then
        CONFIGURATION="$FILE_CONF_DEV"
        source "$DIR_FILE_CONF_DEV"
        print_fancy --theme "warning" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION DEV ACTIVÉE – Fichier de configuration = $CONFIGURATION ⚠️ "
    fi
}


###############################################################################
# Fonction : Vérifier l’existence, la lisibilité et le contenu du fichier jobs
###############################################################################
check_jobs_file() {
    # Vérifier existence
    if [[ ! -f "$DIR_JOBS_FILE" ]]; then
        if [[ "${BATCH_EXEC:-false}" == "false" ]]; then
            die 3 "$MSG_FILE_NOT_FOUND : $DIR_JOBS_FILE"
        fi
        return 1
    fi

    # Vérifier lisibilité
    if [[ ! -r "$DIR_JOBS_FILE" ]]; then
        if [[ "${BATCH_EXEC:-false}" == "false" ]]; then
            die 4 "$MSG_FILE_NOT_READ : $DIR_JOBS_FILE"
        fi
        return 1
    fi

    # Vérifier qu’il contient au moins une ligne valide
    if ! grep -qE '^[[:space:]]*[^#[:space:]]' "$DIR_JOBS_FILE"; then
        if [[ "${BATCH_EXEC:-false}" == "false" ]]; then
            die 31 "❌ Aucun job valide trouvé dans $DIR_JOBS_FILE"
        fi
        return 1
    fi

    return 0
}


###############################################################################
# Fonction : Vérifier si rclone est installé
# Renvoie 0 si installé, sinon die 11
###############################################################################
check_rclone_installed() {
    if ! command -v rclone >/dev/null 2>&1; then
        die 11 "❌  rclone n'est pas installé. Le script va s'arrêter."
    fi
}


###############################################################################
# Fonction : Installer rclone (sans confirmation)
###############################################################################
install_rclone() {
    echo "📦  Installation de rclone en cours..."
    if sudo apt update && sudo apt install -y rclone; then
        echo "✅  rclone a été installé avec succès !"
    else
        die 11 "❌  Une erreur bloquante est survenue lors de l'installation de rclone."
    fi
}


###############################################################################
# Fonction : Vérification interactive (si absent propose l'installation)
###############################################################################
prompt_install_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        echo "⚠️  rclone n'est pas installé."
        read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
        REPLY=${REPLY,,}
        if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
            install_rclone
        else
            die 11 "❌  rclone est requis mais n'a pas été installé."
        fi
    fi
}


###############################################################################
# Fonction : Vérifie la configuration initiale de rclone
# Renvoie die 12 si fichier manquant ou vide
###############################################################################
check_rclone_configured() {
    local conf_file="${RCLONE_CONFIG_DIR:-$HOME/.config/rclone/rclone.conf}"

    if [[ ! -f "$conf_file" || ! -s "$conf_file" ]]; then
        die 12 "❌  rclone est installé mais n'est pas configuré. Veuillez exécuter : rclone config"
    fi
}


###############################################################################
# Fonction : Vérifier si msmtp est installé
# Renvoie 0 si installé, sinon die 10
###############################################################################
check_msmtp_installed() {
    if ! command -v msmtp >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}


###############################################################################
# Fonction : Vérification interactive (si absent propose l'installation)
###############################################################################
prompt_install_msmtp() {
    echo "⚠️  msmtp n'est pas installé."
    read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
        install_msmtp
    else
        die 10 "❌  msmtp est requis mais n'a pas été installé."
    fi
}


###############################################################################
# Fonction : Installer msmtp (sans confirmation)
###############################################################################
install_msmtp() {
    echo "📦  Installation de msmtp en cours..."
    if sudo apt update && sudo apt install -y msmtp msmtp-mta; then
        echo "✅  msmtp a été installé avec succès !"
    else
        die 10 "❌  Une erreur est survenue lors de l'installation de msmtp."
    fi
}


###############################################################################
# Fonction : Vérifie la configuration initiale de msmtp
###############################################################################
check_msmtp_configured() {
    local conf_file=""

    # 1. Vérifie d'abord le fichier utilisateur (ex: /root/.msmtprc ou $MSMTPRC)
    conf_file="${MSMTPRC:-$HOME/.msmtprc}"
    if [[ -f "$conf_file" && -s "$conf_file" && -r "$conf_file" ]]; then
        echo "$conf_file"
        return 0
    fi

    # 2. Sinon, vérifie le fichier système (/etc/msmtprc)
    conf_file="/etc/msmtprc"
    if [[ -f "$conf_file" && -s "$conf_file" && -r "$conf_file" ]]; then
        echo "$conf_file"
        return 0
    fi

    # Aucun fichier valide trouvé
    echo "❌  Aucun fichier de configuration msmtp valide trouvé." >&2
    return 1
}


###############################################################################
# Fonction : Vérifie la présence de jobs.txt et initialise à partir de jobs.txt.exemple si absent
###############################################################################
init_jobs_file() {

    # Si jobs.conf existe, rien à faire
    if [[ -f "$DIR_JOBS_FILE" ]]; then
        print_fancy --theme "info" "Fichier $JOBS_FILE déjà présent"
        return 0
    fi

    # Sinon, on tente de copier le fichier exemple
    if [[ -f "$DIR_EXEMPLE_JOBS_FILE" ]]; then
        mkdir -p "$(dirname "$DIR_JOBS_FILE")"
        cp "$DIR_EXEMPLE_JOBS_FILE" "$DIR_JOBS_FILE"
        print_fancy --theme "success" "Copie de $EXEMPLE_JOBS_FILE → $JOBS_FILE réalisée"
        return 0
    else
        print_fancy --theme "error" "Erreur dans la copie de $EXEMPLE_JOBS_FILE → $JOBS_FILE"
        return 1
    fi
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
    START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "INFOS"
    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    print_aligned_table "Date / Heure début" "$START_TIME"
    print_aligned_table "Date / Heure fin" "$END_TIME"
    print_aligned_table "Mode de lancement" "$LAUNCH_MODE"
    print_aligned_table "Nb. de jobs traités" "${EXECUTED_JOBS} / ${#JOBS_LIST[@]}"
    print_aligned_table "Code erreur" "$ERROR_CODE"
    print_aligned_table "Dossier" "${DIR_LOG}/"
    print_aligned_table "Log script" "$LOG_FILE_SCRIPT"
    print_aligned_table "Log mail" "$LOG_FILE_MAIL"
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


###############################################################################
# Fonction : Initialiser config.local.sh si absent
###############################################################################
init_config_local() {
    local main_conf="$SCRIPT_DIR/config/config.main.conf"
    local conf_file="$DIR_FILE_CONF_LOCAL"

    echo
    echo
    print_fancy --style "underline" "⚙️  Création de config.local.sh"
    print_fancy --theme "info" "Vous êtes sur le point de créer un fichier personnalisable de configuration."
    print_fancy --fg "blue" -n "Fichier d'origine : ";
     print_fancy "$main_conf"
    print_fancy --fg "blue" -n "Fichier à créer   : ";
     print_fancy "$conf_file"
    echo
    read -rp "❓  Voulez-vous créer ce fichier ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        echo "ℹ️  Création ignorée pour : $conf_file"
        return 1
    fi

    mkdir -p "$(dirname "$conf_file")" || die 21 "Impossible de créer le dossier cible $(dirname "$conf_file")"
    cp "$main_conf" "$conf_file"       || die 20 "Impossible de copier $main_conf vers $conf_file"
    echo "✅  Fichier installé : $conf_file"
}


###############################################################################
# Fonction : éditer le fichier de config local
###############################################################################
edit_config_local() {
    # Vérifier l'existence du fichier
    if [[ ! -f "$DIR_FILE_CONF_LOCAL" ]]; then
        echo "⚠️  Aucun fichier de configuration local trouvé : $DIR_FILE_CONF_LOCAL"
        return 1
    fi

    echo
    echo "ℹ️  Fichier existant : $DIR_FILE_CONF_LOCAL"
    prompt="❓  Voulez-vous éditer $(print_fancy --style bold "$DIR_FILE_CONF_LOCAL") avec nano ? [y/N] : "
    read -rp "$prompt" REPLY
    REPLY=${REPLY,,}

    if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
        nano "$DIR_FILE_CONF_LOCAL"
        echo "✅  Édition terminée : $DIR_FILE_CONF_LOCAL"
    else
        echo "ℹ️  Édition ignorée pour : $DIR_FILE_CONF_LOCAL"
    fi
}


###############################################################################
# Fonction : Récupérer le log précédent afin de l'afficher via le menu
###############################################################################
get_last_log() {
    # Tous les logs triés par date décroissante
    local logs=("$DIR_LOG"/*.log)

    # Aucun log ?
    [[ ${#logs[@]} -eq 0 ]] && echo "" && return

    # Exclure le log actuel
    local previous=""
    for log in "${logs[@]}"; do
        [[ "$log" == "$LOG_FILE_INFO" ]] && continue
        previous="$log"
        break
    done

    echo "$previous"
}


###############################################################################
# Fonction : Création des répertoires temporaires nécessaires
###############################################################################
create_temp_dirs() {
    # DIR_TMP
    if [[ ! -d "$DIR_TMP" ]]; then
        mkdir -p "$DIR_TMP" 2>/dev/null || die 1 "$MSG_DIR_TMP_CREATE_FAIL : $DIR_TMP"
    fi

    # DIR_LOG
    if [[ ! -d "$DIR_LOG" ]]; then
        mkdir -p "$DIR_LOG" 2>/dev/null || die 2 "$MSG_DIR_LOG_CREATE_FAIL : $DIR_LOG"
    fi
}


###############################################################################
# Fonction : Vérifications générales post-initialisation
###############################################################################
post_init_checks() {
    create_temp_dirs
    chech_jobs_file
}


