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
# Fonction : Surcharger global.conf < config.local.conf < config.dev.conf < secrets.env (si présents)
# Utilise display_msg() pour tout affichage
# DISPLAY_MODE possible : soft (aucun affichage) | verbose (messages détaillés)
###############################################################################
load_optional_configs() {
    local any_loaded=false

    local configs=(
        "$DIR_CONF_LOCAL_FILE|CONFIGURATION LOCALE ACTIVÉE ℹ️"
        "$DIR_CONF_DEV_FILE|CONFIGURATION DEV ACTIVÉE ℹ️"
        "$DIR_SECRET_FILE|SECRETS LOADED ℹ️"
    )

    for entry in "${configs[@]}"; do
        IFS="|" read -r file msg <<< "$entry"
        if [[ -f "$file" && -r "$file" ]]; then
            source "$file"
            any_loaded=true

            # On peut décider quel type de message on veut ici
            display_msg "verbose|hard" --theme success "$(basename "$file") chargé"
        fi
    done

    if [[ "$any_loaded" == false ]]; then
        display_msg "soft" --theme info "Aucun fichier chargé"
        display_msg "verbose" --theme info "Configuration par défaut uniquement."
        display_msg "hard" --theme info "Aucun fichier de configuration optionnel trouvé. Configuration par défaut uniquement."
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

    print_aligned_table "Date / Heure début"  "$(safe_var "START_TIME")"
    print_aligned_table "Date / Heure fin"    "$END_TIME"
    print_aligned_table "Mode de lancement"   "$(safe_var "LAUNCH_MODE")"
    print_aligned_table "Nb. de jobs traités" "$(safe_var "EXECUTED_JOBS") / $(safe_count JOBS_LIST)"
    print_aligned_table "Dernier code erreur" "$(safe_var "ERROR_CODE")"
    print_aligned_table "Dossier"             "$(safe_var "DIR_LOG")/"
    print_aligned_table "Log mail"            "$(safe_var "LOG_FILE_MAIL")"
    print_aligned_table "Log rclone"          "$(safe_var "LOG_FILE_INFO")"

    if [[ -n "${MAIL_TO:-}" ]]; then
        print_aligned_table "Email envoyé à" "$(safe_var "MAIL_TO")"
        print_aligned_table "Sujet email"    "$(safe_var "SUBJECT_RAW")"
    fi

    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        print_aligned_table "Notifs Discord" "$(safe_var "MSG_DISCORD_PROCESSED")"
    else
        print_aligned_table "Notifs Discord" "$(safe_var "MSG_DISCORD_ABORDED")"
    fi

    print_aligned_table "Simulation (dry-run)" "$(safe_var "MSG_DRYRUN")"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='
    print_fancy --align "center" --bg "yellow" --fg "black" "$(safe_var "MSG_END_REPORT")"
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


###############################################################################
# Fonction : Intérroger le numéro de version/tag/release (local ou git)
###############################################################################
get_current_version() {
    if [[ -s "$DIR_VERSION_FILE" ]]; then
        APP_VERSION="$(<"$DIR_VERSION_FILE")"
    else
        APP_VERSION="-NC-"
    fi
}


###############################################################################
# Fonction : Contrôle et validation des variables
###############################################################################
control_local_config() {
    if ! print_table_vars_invalid VARS_TO_VALIDATE; then
        # Problème
        echo
        print_fancy --theme "error" "Configuration invalide. Vérifiez les variables (locales). ❌"
        echo
        echo
        print_fancy --fg green "-------------------------------------------"
        print_fancy --fg green style bold "  Aide au débogage : Configuration locale"
        print_fancy --fg green "-------------------------------------------"
        echo
        echo -e"${UNDERLINE}Voulez-vous :${RESET}"
        echo -e "[1] Appliquer la valeur ${BOLD}Défaut${RESET} automatiquement."
        echo -e "${ITALIC}    => N'est valable que pour cette session.${RESET}"
        echo -e "[2] Editer la configuration locale pour ${UNDERLINE}corriger${RESET}."
        echo -e "[3] Quitter."
        echo

        read -rp "Votre choix [1-3] : " choice

        case "$choice" in
            1)
                validate_vars
                ;;
            2)
                mini_edit_local_config
                control_local_config  # retour au menu principal après édition pour validation
                ;;
            3)
                die 99 "Interruption par l’utilisateur"
                ;;
            *)
                echo "❌  Choix invalide."
                sleep 1
                control_local_config
                ;;
        esac
    fi
    
    # Pas de problèmes
    display_msg "verbose|hard" --theme info "Configuration des variables locale validée."

}

mini_edit_local_config() {
    local candidates=(
        "$DIR_CONF_LOCAL_FILE"
        "$DIR_CONF_DEV_FILE"
        "$DIR_SECRET_FILE"
    )

    echo
    echo "Fichiers disponibles pour édition :"
    echo
    local i=1
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && echo "[$i] $f" || echo "[$i] $f (absent)"
        ((i++))
    done
    echo "[$i] Retour"
    echo

    read -rp "Choisir un fichier à éditer [1-$i] : " subchoice

    if [[ "$subchoice" -ge 1 && "$subchoice" -lt "$i" ]]; then
        local target="${candidates[$((subchoice-1))]}"
        if [[ -f "$target" ]]; then
            ${EDITOR:-nano} "$target"
        else
            echo "⚠️  Fichier absent : $target"
            sleep 1
        fi
    fi
}
