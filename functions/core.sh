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
        "EDITOR:nano|micro:nano"
        "DEBUG_INFOS:bool:false"
        "DEBUG_MODE:bool:false"
        "DISPLAY_MODE:none|simplified|verbose:simplified"
    )
}


###############################################################################
# Fonction : Surcharger global.conf < config.local.conf < config.dev.conf < secrets.env (si présents)
###############################################################################
#   load_optional_configs               → s’adapte à DEBUG_INFOS / DISPLAY_MODE.
#   load_optional_configs simplified    → sortie courte.
#   load_optional_configs verbose       → sortie détaillée.
#   load_optional_configs none          → aucun affichage.
# Argument > DISPLAY_MODE > DEBUD_INFOS
###############################################################################
load_optional_configs() {
    local arg_mode="${1-}"
    local mode=""

    # --- Sélection du mode ---
    if [[ -n "$arg_mode" ]]; then
        mode="$arg_mode"
    elif [[ -n "$DISPLAY_MODE" ]]; then
        mode="$DISPLAY_MODE"
    elif [[ "$DEBUG_INFOS" == true ]]; then
        mode="verbose"
    else
        mode="simplified"
    fi

    local any_loaded=false

    # 1/ -- config.local.conf --
    if [[ -f "$DIR_CONF_LOCAL_FILE" && -r "$DIR_CONF_LOCAL_FILE" ]]; then
        source "$DIR_CONF_LOCAL_FILE"
        any_loaded=true
        case "$mode" in
            verbose)
                print_fancy --theme "info" --align "center" --bg "yellow" --fg "rgb:0;0;0" --highlight \
                "CONFIGURATION LOCALE ACTIVÉE ℹ️"
                ;;
            simplified)
                echo "✔ Local config activée"
                ;;
            none) ;; # pas de sortie
        esac
    fi

    # 2/ -- config.dev.conf (prioritaire) --
    if [[ -f "$DIR_CONF_DEV_FILE" && -r "$DIR_CONF_DEV_FILE" ]]; then
        source "$DIR_CONF_DEV_FILE"
        any_loaded=true
        case "$mode" in
            verbose)
                print_fancy --theme "info" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
                "CONFIGURATION DEV ACTIVÉE ℹ️"
                ;;
            simplified)
                echo "✔ Dev config activée"
                ;;
            none) ;;
        esac
    fi

    # 3/ -- secrets.env --
    if [[ -f "$DIR_SECRET_FILE" && -r "$DIR_SECRET_FILE" ]]; then
        source "$DIR_SECRET_FILE"
        any_loaded=true
        case "$mode" in
            verbose)
                print_fancy --theme "info" --align "center" --bg "red" --fg "rgb:0;0;0" --highlight \
                "SECRETS LOADED ℹ️"
                ;;
            simplified)
                echo "✔ Secrets chargés"
                ;;
            none) ;;
        esac
    fi

    # 4/ -- Si aucun fichier n’a été chargé --
    if [[ "$any_loaded" == false ]]; then
        case "$mode" in
            verbose)
                print_fancy --theme "warning" --align "center" --bg "blue" --fg "white" --highlight \
                "Aucun fichier de configuration optionnel trouvé. Configuration par défaut uniquement."
                ;;
            simplified)
                echo "⚠️ Aucun fichier optionnel trouvé"
                ;;
            none) ;;
        esac
    fi
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
    $EDITOR "$conf_file"
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

    print_aligned_table "Date / Heure début"  "$(safe_var "$START_TIME")"
    print_aligned_table "Date / Heure fin"    "$END_TIME"
    print_aligned_table "Mode de lancement"   "$(safe_var "$LAUNCH_MODE")"
    print_aligned_table "Nb. de jobs traités" "$(safe_var "$EXECUTED_JOBS") / $(safe_count JOBS_LIST)"
    print_aligned_table "Dernier code erreur" "$(safe_var "$ERROR_CODE")"
    print_aligned_table "Dossier"             "$(safe_var "$DIR_LOG")/"
    print_aligned_table "Log mail"            "$(safe_var "$LOG_FILE_MAIL")"
    print_aligned_table "Log rclone"          "$(safe_var "$FILE_INFO")"

    if [[ -n "${MAIL_TO:-}" ]]; then
        print_aligned_table "Email envoyé à" "$(safe_var "$MAIL_TO")"
        print_aligned_table "Sujet email"    "$(safe_var "$SUBJECT_RAW")"
    fi

    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        print_aligned_table "Notifs Discord" "$(safe_var "$MSG_DISCORD_PROCESSED")"
    else
        print_aligned_table "Notifs Discord" "$(safe_var "$MSG_DISCORD_ABORDED")"
    fi

    [[ "${DRY_RUN:-}" == true ]] && \
        print_aligned_table "Simulation (dry-run)" "$(safe_var "$MSG_DRYRUN")"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='
    print_fancy --bg "yellow" --fg "black" "$(safe_var "$MSG_END_REPORT")"
    echo
}


###############################################################################
# Fonction : Retourne la valeur d'une variable
#   - Si variable non déclarée : "-nc-"
#   - Si variable déclarée mais vide : "-ABSENT-"
#   - Sinon : la valeur
# Usage :
#   safe_var VAR_NAME
###############################################################################
safe_var() {
    local varname="$1"

    if ! declare -p "$varname" &>/dev/null; then
        echo "-nc-"
    else
        local val="${!varname}"
        [[ -z "$val" ]] && echo "-ABSENT-" || echo "$val"
    fi
}


###############################################################################
# Fonction : Pour les tableaux : renvoie la taille, ou 0 si non défini
###############################################################################
safe_count() {
    local -n arr=$1 2>/dev/null || { echo 0; return; }
    echo "${#arr[@]}"
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
# Fonction : Ajouter des options à rclone
###############################################################################
add_rclone_opts() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        RCLONE_OPTS+=(--dry-run)
    fi
}