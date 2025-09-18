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
        "DRY_RUN:bool:false"
        "MAIL_TO:''"
        "DISCORD_WEBHOOK_URL:''"
        "FORCE_UPDATE:bool:false"
        "FORCE_BRANCH:''"
        "LAUNCH_MODE:hard|verbose:hard"
        "TERM_WIDTH_DEFAULT:80-120:80"
        "LOG_RETENTION_DAYS:1-15:14"
        "LOG_LINE_MAX:100-10000:1000"
        "DEBUG_INFOS:bool:false"
        "DEBUG_MODE:bool:false"
        "DISPLAY_MODE:none|simplified|verbose:simplified"
    )
}


###############################################################################
# Fonction : Charger config.local < config.dev < secrets.env (si présents) [Du moins important au plus important]
###############################################################################
load_optional_configs() {
    local display_mode="${DEBUG_INFO:-false}"  # verbose / simplified / none

    # 1/ -- config.main.conf
    # 2/ -- config.local --
    if [[ -f "$DIR_FILE_CONF_LOCAL" && -r "$DIR_FILE_CONF_LOCAL" ]]; then
        source "$DIR_FILE_CONF_LOCAL"
        [[ "$display_mode" == "verbose" ]] && print_fancy --theme "info" --align "center" --bg "yellow" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION LOCALE ACTIVÉE ℹ️ "
    else
        [[ "$display_mode" == "verbose" ]] && print_fancy --theme "info" --align "center" --bg "yellow" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION PAR DEFAUT UNIQUEMENT D'ACTIVÉE ℹ️ "
    fi
    # 3/ -- config.dev (prioritaire, chargé en dernier) --
    if [[ -f "$DIR_FILE_CONF_DEV" && -r "$DIR_FILE_CONF_DEV" ]]; then
        source "$DIR_FILE_CONF_DEV"
        print_fancy --theme "info" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION DEV ACTIVÉE  ℹ️ "
    fi
    # 4/ -- secrets.env
    if [[ -f "$DIR_SECRET_FILE" && -r "$DIR_SECRET_FILE" ]]; then
        source "$DIR_SECRET_FILE"
        print_fancy --theme "info" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
        "CONFIGURATION DEV ACTIVÉE  ℹ️ "
    fi
    # 5/ -- arguments de lancement du script [a le dernier mots]
}


###############################################################################
# Fonction : Vérifier si rclone est installé
# Mode : soft    = retour 1 si absent
#        verbose = interactif, propose l'installation
#        hard    = die si absent
###############################################################################
check_rclone_installed() {
    local mode="${1:-${LAUNCH_MODE:-hard}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    if ! command -v rclone >/dev/null 2>&1; then
        case "$mode" in
            soft) return 1 ;;
            verbose) install_rclone verbose ;;
            hard) die 11 "rclone n'est pas installé. Le script va s'arrêter." ;;
        esac
    fi

    return 0
}


###############################################################################
# Fonction : Installer rclone selon le mode choisi
# Usage    : install_rclone [soft|verbose|hard]
###############################################################################
install_rclone() {
    local mode="${1:-${LAUNCH_MODE:-hard}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    case "$mode" in
        soft)
            echo "📦  Installation de rclone en mode silencieux..."
            ;;
        verbose)
            echo "⚠️  rclone n'est pas installé."
            read -rp "Voulez-vous l'installer maintenant ? [y/N] : " REPLY
            REPLY=${REPLY,,}
            if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
                die 11 "rclone est requis mais n'a pas été installé."
            fi
            ;;
        hard)
            die 11 "rclone est requis mais n'est pas installé."
            ;;
    esac

    # Tentative d’installation
    echo "📦  Installation de rclone en cours..."
    if sudo apt update && sudo apt install -y rclone; then
        return 0
    else
        case "$mode" in
            verbose) die 11 "Une erreur est survenue lors de l'installation de rclone." ;;
            soft)    return 1 ;;
        esac
    fi
}



###############################################################################
# Vérifie si rclone est configuré
# Paramètre optionnel : "soft" -> ne pas die, juste retourner 1 si non configuré
###############################################################################
check_rclone_configured() {
    local candidates=()
    local mode="${1:-${LAUNCH_MODE:-hard}}"   # ordre de priorité : arg > var globale > défaut hard
    local found=0

    # 1. Variable d'environnement RCLONE_CONFIG si définie
    [[ -n "${RCLONE_CONFIG:-}" ]] && candidates+=("$RCLONE_CONFIG")

    # 2. Fichier utilisateur standard (~/.config/rclone/rclone.conf)
    [[ -n "$HOME" ]] && candidates+=("$HOME/.config/rclone/rclone.conf")

    # 3. Fichier global système
    candidates+=("/etc/rclone.conf")

    for conf_file in "${candidates[@]}"; do
        if [[ -f "$conf_file" && -r "$conf_file" ]]; then
            local filesize
            filesize=$(stat -c %s "$conf_file" 2>/dev/null || echo 0)
            if (( filesize > 0 )); then
                [[ "$mode" == "verbose" ]] && print_fancy --theme "sucess" "Fichier rclone valide trouvé : $conf_file" >&2
                echo "$conf_file"
                return 0
            else
                [[ "$mode" == "verbose" ]] && print_fancy --theme "warning" "Fichier rclone trouvé mais vide : $conf_file" >&2
                found=1
            fi
        fi
    done

    if (( found == 1 )); then
        case "$mode" in
            soft)   return 1 ;;
            verbose) print_fancy --theme "error" "Fichier rclone détecté mais inutilisable." >&2; return 1 ;;
            hard)   die 30 "Fichier rclone détecté mais inutilisable." >&2; exit 1 ;;
        esac
    fi

    # Aucun fichier trouvé
    case "$mode" in
        soft)   return 2 ;;
        verbose) print_fancy --theme "info" "Aucun fichier rclone.conf trouvé." >&2; return 2 ;;
        hard)   die 30 "Aucun fichier rclone.conf trouvé — arrêt immédiat." >&2; exit 2 ;;
    esac
}


###############################################################################
# Fonction : Vérifier l’existence, la lisibilité et le contenu du fichier jobs
# Usage    : check_jobs_file [soft|verbose|hard]
###############################################################################
check_jobs_file() {
    local mode="${1:-${LAUNCH_MODE:-hard}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    # Vérifier existence
    if [[ ! -f "$DIR_JOBS_FILE" ]]; then
        case "$mode" in
            soft)    return 1 ;;
            verbose) echo "❌ $MSG_FILE_NOT_FOUND : $DIR_JOBS_FILE" >&2; return 1 ;;
            hard)    die 3 "$MSG_FILE_NOT_FOUND : $DIR_JOBS_FILE" ;;
        esac
    fi

    # Vérifier lisibilité
    if [[ ! -r "$DIR_JOBS_FILE" ]]; then
        case "$mode" in
            soft)    return 1 ;;
            verbose) echo "❌ $MSG_FILE_NOT_READ : $DIR_JOBS_FILE" >&2; return 1 ;;
            hard)    die 4 "$MSG_FILE_NOT_READ : $DIR_JOBS_FILE" ;;
        esac
    fi

    # Vérifier contenu
    if ! grep -qE '^[[:space:]]*[^#[:space:]]' "$DIR_JOBS_FILE"; then
        case "$mode" in
            soft)    return 1 ;;
            verbose) echo "❌ Aucun job valide trouvé dans $DIR_JOBS_FILE" >&2; return 1 ;;
            hard)    die 31 "❌ Aucun job valide trouvé dans $DIR_JOBS_FILE" ;;
        esac
    fi

    # Si tout est bon
    return 0
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
# Fonction : Edit ele bon fichier de configuration de msmtp (si installation atypique)
###############################################################################
edit_msmtp_config() {
    local conf_file
    conf_file="$(check_msmtp_configured)" || {
        conf_file="${MSMTPRC:-$HOME/.msmtprc}"
        print_fancy --theme "warning" "Aucun fichier msmtp valide trouvé, création de : $conf_file"
        touch "$conf_file" && chmod 600 "$conf_file"
    }

    print_fancy --theme "info" "Édition du fichier msmtp : $conf_file"
    nano "$conf_file"
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
# Fonction : Rendre des scripts exécutable (utile après une MAJ notement)
###############################################################################
make_scripts_executable() {
    local base_dir="${1:-${SCRIPT_DIR:-}}"
    local scripts=("update/standalone_updater.sh") # Ajouter des fichiers ici si besoin, chacun entre "".

    if [[ -z "$base_dir" ]]; then
        print_fancy --theme "error" "ERREUR: base_dir non défini et SCRIPT_DIR absent."
        return 1
    fi

    for s in "${scripts[@]}"; do
        local f="$base_dir/$s"
        if [[ -f "$f" ]]; then
            chmod +x "$f"
            [[ "${DEBUG_INFOS,,}" == "true" ]] && print_fancy --theme "debug_info" $'chmod +x appliqué sur \n'"$f"
        else
            [[ "${DEBUG_INFOS,,}" == "true" ]] && --theme "warning" $'[DEBUG_INFO] Fichier absent : \n'"$f"
        fi
    done
}