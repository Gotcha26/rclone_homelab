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
# Fonction : Tableau - S'assure des valeurs prises par les varaibles locales utilisateur
###############################################################################
set_validation_vars() {
    VARS_TO_VALIDATE=(
        "LOG_LINE_MAX:100-10000:1000"
        "TERM_WIDTH_DEFAULT:80-120:80"
        "LOG_RETENTION_DAYS:1-15:14"
        "FORCE_UPDATE:bool:false"
        "DRY_RUN:bool:false"
        "LAUNCH_MODE:hard|verbose:hard"
        "DEBUG_MODE:bool:false"
        "DEBUG_INFOS:bool:false"
        "DISPLAY_MODE:none|simplified|verbose:simplified"
    )
}


###############################################################################
# Fonction : Charger config.local puis config.dev (si présents)
###############################################################################
load_optional_configs() {
    # -- config.local --
    if [[ -f "$DIR_FILE_CONF_LOCAL" && -r "$DIR_FILE_CONF_LOCAL" ]]; then
        source "$DIR_FILE_CONF_LOCAL"
    fi

    # -- config.dev (prioritaire, chargé en dernier) --
    if [[ -f "$DIR_FILE_CONF_DEV" && -r "$DIR_FILE_CONF_DEV" ]]; then
        source "$DIR_FILE_CONF_DEV"
    fi
}


###############################################################################
# Fonction charge dans l'ordre main > local > dev
###############################################################################
show_optional_configs() {
    local display_mode="${DISPLAY_MODE:-simplified}"  # verbose / simplified / none

    if [[ -f "$DIR_FILE_CONF_LOCAL" && -r "$DIR_FILE_CONF_LOCAL" ]]; then
        [[ "$display_mode" == "verbose" ]] && print_fancy --theme "info" --align "center" --bg "yellow" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION LOCALE ACTIVÉE ℹ️ "
    fi

    if [[ -f "$DIR_FILE_CONF_DEV" && -r "$DIR_FILE_CONF_DEV" ]]; then
        print_fancy --theme "info" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION DEV ACTIVÉE  ℹ️ "
    fi
}


###############################################################################
# Fonction : Vérifier si rclone est installé
# Mode : soft    = retour 1 si absent
#        verbose = interactif, propose l'installation
#        hard    = die si absent
###############################################################################
check_rclone_installed() {
    local LAUNCH_MODE="$1:${LAUNCH_MODE:-hard}"  # argument : variable:<defaut> (l'argument prime sur la variable)

    if ! command -v rclone >/dev/null 2>&1; then
        case "$mode" in
            soft)
                return 1
                ;;
            verbose)
                install_rclone verbose
                ;;
            hard)
                die 11 "❌  rclone n'est pas installé. Le script va s'arrêter."
                ;;
            *)
                echo "❌  Mode inconnu '$mode' dans check_rclone_installed"
                return 2
                ;;
        esac
    fi

    return 0
}


###############################################################################
# Fonction : Installer rclone
# Mode : verbose = interactif + die si échec/refus
#        soft    = tentative silencieuse, retour 0-1, pas de die
###############################################################################
install_rclone() {
    local mode="${1:-hard}"  # verbose / soft

    # Mode hard = interactif
    if [[ "$mode" == "verbose" ]]; then
        echo "⚠️  rclone n'est pas installé."
        read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
        REPLY=${REPLY,,}

        if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
            die 11 "❌  rclone est requis mais n'a pas été installé."
        fi
    fi

    # Commande d'installation centralisée
    echo "📦  Installation de rclone en cours..."
    if sudo apt update && sudo apt install -y rclone; then
        return 0
    else
        # Mode soft → retourne 1, mode hard → die
        if [[ "$mode" == "soft" ]]; then
            return 1
        else
            die 11 "❌  Une erreur bloquante est survenue lors de l'installation de rclone."
        fi
    fi
}


###############################################################################
# Vérifie si rclone est configuré
# Paramètre optionnel : "soft" -> ne pas die, juste retourner 1 si non configuré
###############################################################################
check_rclone_configured() {
    local mode="${1:-verbose}"  # verbose = die si pas configuré, soft = juste retour 1
    local conf_file="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"

    if [[ ! -f "$conf_file" || ! -r "$conf_file" || ! -s "$conf_file" ]]; then
        if [[ "$mode" == "verbose" ]]; then
            die 12 "❌  rclone est installé mais n'est pas configuré. Veuillez exécuter : rclone config"
        else
            return 1  # soft fail
        fi
    fi

    return 0
}


###############################################################################
# Fonction : Vérifier l’existence, la lisibilité et le contenu du fichier jobs
###############################################################################
check_jobs_file() {
    # Vérifier existence
    if [[ ! -f "$DIR_JOBS_FILE" ]]; then
        return 1
    fi

    # Vérifier lisibilité
    if [[ ! -r "$DIR_JOBS_FILE" ]]; then
        return 1
    fi

    # Vérifier qu’il contient au moins une ligne valide
    if ! grep -qE '^[[:space:]]*[^#[:space:]]' "$DIR_JOBS_FILE"; then
        return 1
    fi

    # Si tout va bien
    return 0
}


###############################################################################
# Fonction : Vérifier l’existence, la lisibilité et le contenu du fichier jobs
###############################################################################
post_check_jobs_file() {
    # Vérifier existence
    if [[ ! -f "$DIR_JOBS_FILE" ]]; then
            die 3 "$MSG_FILE_NOT_FOUND : $DIR_JOBS_FILE"
    fi

    # Vérifier lisibilité
    if [[ ! -r "$DIR_JOBS_FILE" ]]; then
        die 4 "$MSG_FILE_NOT_READ : $DIR_JOBS_FILE"
    fi

    # Vérifier qu’il contient au moins une ligne valide
    if ! grep -qE '^[[:space:]]*[^#[:space:]]' "$DIR_JOBS_FILE"; then
        die 31 "❌ Aucun job valide trouvé dans $DIR_JOBS_FILE"
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
# Fonction : Détecter le fichier de configuration msmtp réellement utilisé
###############################################################################
check_msmtp_configured() {
    local candidates=()

    # 1. Variable d'environnement MSMTPRC si définie
    [[ -n "${MSMTPRC:-}" ]] && candidates+=("$MSMTPRC")

    # 2. Fichier utilisateur
    [[ -n "$HOME" ]] && candidates+=("$HOME/.msmtprc")

    # 3. Fichier système
    candidates+=("/etc/msmtprc")

    # Parcours des candidats
    for conf_file in "${candidates[@]}"; do
        if [[ -f "$conf_file" && -r "$conf_file" ]]; then
            local filesize
            filesize=$(stat -c %s "$conf_file" 2>/dev/null || echo 0)
            if (( filesize > 0 )); then
                echo "$conf_file"
                return 0
            else
                echo "⚠️  Fichier msmtp trouvé mais vide : $conf_file" >&2
            fi
        fi
    done

    # Aucun fichier valide trouvé
    echo "❌  Aucun fichier msmtp valide trouvé." >&2
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
    post_check_jobs_file
}