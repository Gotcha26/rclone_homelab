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
        display_msg "verbose" --theme info "Configuration par défaut uniquement."
        display_msg "hard" --theme info "Aucun fichier de configuration optionnel trouvé. Configuration par défaut uniquement."
    fi
}


###############################################################################
# Fonction : Cycle de vérifications pour rclone
###############################################################################
check_rclone() {
    local status=0
    local conf_file=""

    # Vérif binaire rclone
    if ! check_rclone_installed; then
        if [[ "$ACTION_MODE" == "manu" ]]; then
            display_msg "soft|verbose|hard" "❗  rclone n'est pas installé, proposition d'installation."
            install_rclone || return 11
        else
            status=11
        fi
    else
        display_msg "verbose|hard" --theme ok "rclone est installé."
        # Vérif configuration et capture chemin du fichier valide
        if conf_file="$(check_rclone_configured 2>/dev/null)"; then
            status=0
        else
            case $? in
                1) status=31 ;;   # Config vide/inutilisable
                2) status=32 ;;   # Aucun fichier trouvé
            esac
        fi
    fi

    # Tableau : code -> "thème¤message"
    declare -A MSGS=(
        [11]="warning¤rclone n'est pas installé. Le script va s'arrêter."
        [31]="error¤Fichier rclone détecté mais inutilisable."
        [32]="warning¤Aucun fichier rclone.conf trouvé."
    )

    case $status in
        0)
            # Affichage succès avec chemin et précision de provenance
            local source_type="inconnu"
            if [[ -n "${RCLONE_CONFIG:-}" && "$RCLONE_CONFIG" == "$conf_file" ]]; then
                source_type="variable d'environnement"
            elif [[ "$conf_file" == "$HOME/.config/rclone/rclone.conf" ]]; then
                source_type="dossier utilisateur"
            elif [[ "$conf_file" == "/etc/rclone.conf" ]]; then
                source_type="configuration globale"
            fi

            display_msg "verbose|hard" --theme ok "Fichier rclone valide trouvé ($source_type) : "
            display_msg "verbose|hard" --align right --fg blue "$conf_file"
            return 0
            ;;
        11|31|32)
            IFS="¤" read -r --theme message <<< "${MSGS[$status]}"
            if [[ "$ACTION_MODE" == "auto" ]]; then
                die "$status" "$message"
            else
                display_msg "soft|verbose|hard" --theme "$theme" "$message"
                display_msg "soft|verbose|hard" ""  # ligne vide
                display_msg "soft|verbose|hard" --theme follow \
                    "Utilisez le menu interactif pour éditer/reconfigurer rclone."
                return "$status"
            fi
            ;;
    esac
}


###############################################################################
# Fonction : Vérifier si rclone est installé
###############################################################################
check_rclone_installed() {
    command -v rclone >/dev/null 2>&1
}


###############################################################################
# Vérifie si rclone est configuré
# Retour :
#   0 -> fichier valide trouvé (chemin émis sur stdout)
#   1 -> fichier trouvé mais vide/inutilisable
#   2 -> aucun fichier trouvé
# Usage :
#   conf_file="$(check_rclone_configured 2>/dev/null)" ; rc=$?
#   if (( rc == 0 )); then ... use "$conf_file" ... fi
###############################################################################
check_rclone_configured() {
    local candidates=()
    local conf_file
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
                # succès : on émet le chemin sur stdout (pour capture) et return 0
                printf '%s\n' "$conf_file"
                return 0
            else
                # trouvé mais vide
                found=1
            fi
        fi
    done

    if (( found == 1 )); then
        return 1
    fi

    return 2
}


###############################################################################
# Fonction : Installer rclone si absent
###############################################################################
install_rclone() {
    # Cas ACTION_MODE=manu → on demande confirmation
    echo
    read -e -rp "📦  Voulez-vous installer rclone maintenant ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        die 11 "Installation de rclone refusée par l'utilisateur."
    fi

    # Tentative d’installation
    display_msg "verbose|hard" --theme follow "Installation de rclone en cours..."
    if sudo apt update && sudo apt install -y rclone; then
        display_msg "soft|verbose|hard" --theme ok "rclone a été installé avec succès."
        return 0
    else
        die 11 "Une erreur est survenue lors de l'installation de rclone."
    fi
}


###############################################################################
# Fonction : Vérifier l'existence, la lisibilité et le contenu du fichier jobs
# Retour : 0 si OK, 1 si KO
###############################################################################
check_jobs_file() {
    # Vérifier présence
    [[ -f "$DIR_JOBS_FILE" ]] || { [[ "$ACTION_MODE" == "auto" ]] && \
        die 3 "Fichier jobs introuvable : $DIR_JOBS_FILE"; return 1; }

    # Vérifier lisibilité
    [[ -r "$DIR_JOBS_FILE" ]] || { [[ "$ACTION_MODE" == "auto" ]] && \
        die 4 "Fichier jobs non lisible : $DIR_JOBS_FILE"; return 1; }

    # Vérifier contenu (au moins une ligne non vide et non commentée)
    grep -qEv '^[[:space:]]*($|#)' "$DIR_JOBS_FILE" || { [[ "$ACTION_MODE" == "auto" ]] && \
        die 5 "Aucun job valide trouvé dans $DIR_JOBS_FILE"; return 1; }

    # Tout est bon si on arrive jusqu'içi
    [[ "$ACTION_MODE" == "auto" ]] && display_msg "verbose|hard" --theme ok "Consultation des jobs : passée"

    return 0
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
# Fonction : Affiche le résumé de la tâche rclone
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
        print_aligned_table "Notifs Discord" "$(safe_var "Traitée(s)")"
    else
        print_aligned_table "Notifs Discord" "$(safe_var "⚠️  Aucun webhook Discord de défini.")"
    fi

    print_aligned_table "Simulation (dry-run)" "$(safe_var "✅  Oui : aucune modification de fichiers.")"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='
    print_fancy --align "center" --bg "yellow" --fg "black" "$(safe_var "--- Fin de rapport ---")"
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
    local -n arr="${1:-}" 2>/dev/null || { echo 0; return; }
    echo "${#arr[@]}"
}


###############################################################################
# Fonction : Création des répertoires temporaires nécessaires
###############################################################################
create_temp_dirs() {
    # DIR_TMP
    if [[ ! -d "$DIR_TMP" ]]; then
        mkdir -p "$DIR_TMP" 2>/dev/null || die 1 "Impossible de créer le dossier temporaire : $DIR_TMP"
    fi

    # DIR_LOG
    if [[ ! -d "$DIR_LOG" ]]; then
        mkdir -p "$DIR_LOG" 2>/dev/null || die 2 "Impossible de créer le dossier de logs : $DIR_LOG"
    fi
}


###############################################################################
# Fonction : Ajouter des options à rclone [OBSOLETE]
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
        head -n1 "$DIR_VERSION_FILE" | tr -d '\r\n'
    else
        echo "-NC-"
    fi
}


###############################################################################
# Fonction : Edition de la configuration locale (si présente...)
###############################################################################
mini_edit_local_config() {
    local candidates=(
        "$DIR_CONF_LOCAL_FILE"
        "$DIR_CONF_DEV_FILE"
        "$DIR_SECRET_FILE"
    )

    # Filtrer uniquement les fichiers existants
    local existing=()
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && existing+=("$f")
    done

    if [[ ${#existing[@]} -eq 0 ]]; then
        return 1
    fi

    echo
    echo "Fichiers disponibles pour édition :"
    echo
    local i=1
    for f in "${existing[@]}"; do
        echo "[$i] $f"
        ((i++))
    done
    echo "[$i] Retour"
    echo

    read -e -rp "Choisir un fichier à éditer [1-$i] : " subchoice

    if [[ "$subchoice" -ge 1 && "$subchoice" -lt "$i" ]]; then
        local target="${existing[$((subchoice-1))]}"
        ${EDITOR:-nano} "$target"
    fi
}


###############################################################################
# Fonction : Désinstallation générique d'un binaire/paquet avec menu et état
# Usage    : dev_uninstall [binaire]
###############################################################################
dev_uninstall() {
    local binary_name="${1:-}"
    local debian_pkgs=""

    # Liste supportée
    local supported=("rclone" "msmtp" "colordiff" "git" "curl" "unzip" "perl" "jq")

    # Si pas d’argument → afficher menu
    if [[ -z "${binary_name:-}" ]]; then
        echo
        echo "📦  Sélectionne le logiciel à désinstaller :"
        echo
        local i=1
        for item in "${supported[@]}"; do
            if command -v "$item" >/dev/null 2>&1; then
                local status="installé"
            else
                local status="absent"
            fi
            printf "  %d) %s [%s]\n" "$i" "$item" "$status"
            ((i++))
        done
        printf "  q) Quitter\n"

        read -rp "👉  Ton choix : " choice
        if [[ "$choice" == "q" ]]; then
            echo "❌  Abandon."
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#supported[@]} )); then
            binary_name="${supported[$((choice-1))]}"
        else
            echo "❌  Choix invalide."
            return 1
        fi
    fi

    # Table de correspondance binaire → paquet(s) Debian
    case "$binary_name" in
        rclone)    debian_pkgs="rclone" ;;
        msmtp)     debian_pkgs="msmtp msmtp-mta" ;;
        colordiff) debian_pkgs="colordiff" ;;
        git)       debian_pkgs="git" ;;
        curl)      debian_pkgs="curl" ;;
        unzip)     debian_pkgs="unzip" ;;
        perl)      debian_pkgs="perl" ;;
        jq)        debian_pkgs="jq" ;;
        *)
            print_fancy --theme error "'$binary_name' n'est pas géré par ce script."
            return 1
            ;;
    esac

    if ! command -v "$binary_name" >/dev/null 2>&1; then
        print_fancy --theme error "$binary_name n'est pas installé ou pas dans le PATH."
        return 0
    fi

    local paths
    mapfile -t paths < <(type -aP "$binary_name" | sort -u)

    for path in "${paths[@]}"; do
        print_fancy "🔍 $binary_name détecté à : $path"

        if dpkg -S "$path" >/dev/null 2>&1; then
            print_fancy --theme ok "Installation via paquet Debian détectée."
            print_fancy --theme info "Exécution de : apt remove --purge -y $debian_pkgs && apt autoremove -y"
            sudo apt remove --purge -y $debian_pkgs
            sudo apt autoremove -y
            print_fancy --theme success "$binary_name a été désinstallé avec apt."
            return 0
        else
            print_fancy --theme ok "Installation manuelle détectée (binaire copié directement)."
            print_fancy --theme info "Suppression du fichier : $path"
            sudo rm -f "$path"
            print_fancy --theme success "$binary_name (binaire manuel) supprimé."
        fi
    done

    # Cas particulier : msmtpq à supprimer si présent et manuel
    if [[ "$binary_name" == "msmtp" ]] && command -v msmtpq >/dev/null 2>&1; then
        local msmtpq_path
        msmtpq_path="$(command -v msmtpq)"
        print_fancy "🔍 msmtpq détecté à : $msmtpq_path"
        if ! dpkg -S "$msmtpq_path" >/dev/null 2>&1; then
            print_fancy --theme info "Suppression du fichier : $msmtpq_path"
            sudo rm -f "$msmtpq_path"
            print_fancy --theme success "msmtpq (binaire manuel) supprimé."
        fi
    fi
}


###############################################################################
# Fonction : Installation générique d'un binaire/paquet avec menu
# Usage    : dev_install [binaire]
###############################################################################
dev_install() {
    local binary_name="${1:-}"
    local debian_pkgs=""

    # Liste supportée
    local supported=("colordiff" "git" "curl" "unzip" "perl" "jq")

    # Si pas d’argument → afficher menu
    if [[ -z "${binary_name:-}" ]]; then
        echo
        echo "📦  Sélectionne le logiciel à installer :"
        echo
        local i=1
        for item in "${supported[@]}"; do
            if command -v "$item" >/dev/null 2>&1; then
                local status="installé"
            else
                local status="absent"
            fi
            printf "  %d) %s [%s]\n" "$i" "$item" "$status"
            ((i++))
        done
        printf "  q) Quitter\n"

        read -rp "👉  Ton choix : " choice
        if [[ "$choice" == "q" ]]; then
            echo "❌  Abandon."
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#supported[@]} )); then
            binary_name="${supported[$((choice-1))]}"
        else
            echo "❌  Choix invalide."
            return 1
        fi
    fi

    # Table de correspondance binaire → paquet(s) Debian
    case "$binary_name" in
        colordiff) debian_pkgs="colordiff" ;;
        git)       debian_pkgs="git" ;;
        curl)      debian_pkgs="curl" ;;
        unzip)     debian_pkgs="unzip" ;;
        perl)      debian_pkgs="perl" ;;
        jq)        debian_pkgs="jq" ;;
        *)
            print_fancy --theme error "'$binary_name' n'est pas géré par ce script."
            return 1
            ;;
    esac

    if command -v "$binary_name" >/dev/null 2>&1; then
        print_fancy --theme ok "$binary_name est déjà installé."
        return 0
    fi

    print_fancy "🔍 Installation de $binary_name via apt..."
    print_fancy --theme info "Exécution : sudo apt update && sudo apt install -y $debian_pkgs"
    sudo apt update
    sudo apt install -y $debian_pkgs
    print_fancy --theme success "$binary_name installé avec succès !"
}