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
  --update-forced    Mettre à jour automatiquement sur la branche en cours. Accèpte l'argument "branche"
  --update-tag       Mettre à jour automatiquement sur la release (version) disponnible.

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

    # 1. Vérifie d'abord le fichier utilisateur (ex: /root/.msmtprc ou $MSMTPRC)
    local user_conf="${MSMTPRC:-$HOME/.msmtprc}"
    if [[ -f "$user_conf" ]] && [[ -s "$user_conf" ]]; then
        echo "$user_conf"
        return 0
    fi

    # 2. Sinon, vérifie le fichier système (/etc/msmtprc)
    local system_conf="/etc/msmtprc"
    if [[ -f "$system_conf" ]] && [[ -s "$system_conf" ]]; then
        echo "$system_conf"
        return 0
    fi

    # Aucun fichier valide trouvé
    echo "❌  Aucun fichier de configuration msmtp valide trouvé." >&2
    return 1
}


###############################################################################
# Fonction : Vérifier la présence de jobs configurés
###############################################################################
check_jobs_configured() {
    [[ -f "$JOBS_FILE" ]] && [[ -s "$JOBS_FILE" ]]
}


###############################################################################
# Fonction : Vérifie la présence de jobs.txt et initialise à partir de jobs.txt.exemple si absent
###############################################################################
init_jobs_file() {

    # Si jobs.txt existe, rien à faire
    if [[ -f "$JOBS_FILE" ]]; then
        echo "✅  Fichier jobs.txt déjà présent"
        return 0
    fi

    # Sinon, on tente de copier le fichier exemple
    if [[ -f "$EXEMPLE_FILE" ]]; then
        cp "$EXEMPLE_FILE" "$JOBS_FILE"
        echo "⚡  jobs.txt absent → copie de jobs.txt.exemple réalisée"
        return 0
    else
        echo "❌  Aucun fichier jobs.txt ni jobs.txt.exemple trouvé dans $SCRIPT_DIR"
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


###############################################################################
# Fonction : initialisation config locale/dev si absente + option édition
###############################################################################
init_config_local() {
    local main_conf="$SCRIPT_DIR/config/config.main.sh"
    local dev_conf="$SCRIPT_DIR/config/config.dev.sh"
    local local_conf="$SCRIPT_DIR/config/config.local.sh"

    # --- Création éventuelle de config.local.sh ---
    if [[ ! -f "$local_conf" ]]; then
        read -rp "Créer $local_conf à partir de $main_conf ? [y/N] : " REPLY
        REPLY=${REPLY,,}    # minuscule
        if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
            if cp "$main_conf" "$local_conf"; then
                echo "✅ $main_conf copié vers $local_conf"
            else
                die 20 "Impossible de copier $main_conf vers $local_conf"
            fi
        else
            echo "⚠️  $local_conf non créé"
        fi
    else
        echo "⚠️  $local_conf existe déjà, pas de copie nécessaire."
    fi

    # --- Création éventuelle de config.dev.sh ---
    if [[ ! -f "$dev_conf" ]]; then
        read -rp "Créer $dev_conf à partir de $local_conf ou $main_conf ? [l/m/N] : " REPLY
        REPLY=${REPLY,,}
        local source_file="$main_conf"
        [[ "$REPLY" == "l" ]] && source_file="$local_conf"
        if [[ "$REPLY" == "l" || "$REPLY" == "m" ]]; then
            if cp "$source_file" "$dev_conf"; then
                echo "✅ $source_file copié vers $dev_conf"
            else
                die 21 "Impossible de copier $source_file vers $dev_conf"
            fi
        else
            echo "⚠️  $dev_conf non créé"
        fi
    else
        echo "⚠️  $dev_conf existe déjà, pas de copie nécessaire."
    fi

    # --- Proposition d'édition pour chaque fichier existant ---
    for conf_file in "$local_conf" "$dev_conf"; do
        if [[ -f "$conf_file" ]]; then
            read -rp "Voulez-vous éditer $conf_file avec nano ? [y/N] : " REPLY
            REPLY=${REPLY,,}
            if [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]; then
                (exec </dev/tty >/dev/tty 2>/dev/tty; nano "$conf_file")
                echo "✅ Édition terminée : $conf_file"
            fi
        fi
    done
}



###############################################################################
# Fonction : Récupérer le log précédent afin de l'afficher via le menu
###############################################################################
get_last_log() {
    # Tous les logs triés par date décroissante
    local logs=("$LOG_DIR"/*.log)

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




