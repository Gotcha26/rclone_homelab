###############################################################################
# Fonction help (aide)
###############################################################################

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Présentation :
Script d'interface entre rclone™️ et vos propres paramètres. Permet de lancer des jobs par batch,
par exécution unique ou même via tâche Cron.
Un menu interactif est présent pour vous aider. Pour y accéder, appeler $(basename "$0") SANS options.

Options :
  --auto             Lance le script en mode automatique (A DEFINIR).
  --mailto=abc@y.com Envoie un rapport par e-mail à l'adresse fournie.
  --dry-run          Simule la synchronisation sans transférer ni supprimer de fichiers.
  -h, --help         Affiche cette modeste aide.
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

Plus d'options disponnibles dans le fichier édités depuis le menu interactif.

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

    # --- Dépendances de la configuration locale ---

    # Association des modes si nécessaire (DEBUG) 
    [[ "$DEBUG_INFOS" == true || "$DEBUG_MODE" == true ]] && DISPLAY_MODE="hard"
    [[ "$DEBUG_MODE" == true ]] && ACTION_MODE="manu"

    # Application des flags issus de la config
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        RCLONE_OPTS+=("--dry-run")
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
    read -e -rp "📦  Voulez-vous installer rclone maintenant ? [O/n] : " -n 1 -r
    echo
    if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
        # Tentative d’installation
        display_msg "verbose|hard" --theme follow "Installation de rclone en cours..."
        if $SUDO apt update && $SUDO apt install -y rclone; then
            display_msg "soft|verbose|hard" --theme ok "rclone a été installé avec succès."
            return 0
        else
            die 10 "Une erreur est survenue lors de l'installation de rclone."
        fi
    else
        die 11 "Installation de rclone refusée par l'utilisateur."
    fi
}


###############################################################################
# Fonction : Vérifier l'existence, la lisibilité et le contenu du fichier jobs
# Retour :
#   0 = OK
#   1 = Fichier introuvable
#   2 = Fichier non lisible
#   3 = Aucun job valide
###############################################################################
check_jobs_file() {
    local ret=0

    # Vérifier présence
    if [[ ! -f "$DIR_JOBS_FILE" ]]; then
        [[ "$ACTION_MODE" == "auto" ]] && die 7 "Fichier jobs introuvable : $DIR_JOBS_FILE"
        return 1
    fi

    # Vérifier lisibilité
    if [[ ! -r "$DIR_JOBS_FILE" ]]; then
        [[ "$ACTION_MODE" == "auto" ]] && die 8 "Fichier jobs non lisible : $DIR_JOBS_FILE"
        return 2
    fi

    # Vérifier contenu (au moins une ligne non vide et non commentée)
    if ! grep -qEv '^[[:space:]]*($|#)' "$DIR_JOBS_FILE" 2>/dev/null; then
        [[ "$ACTION_MODE" == "auto" ]] && die 9 "Aucun job valide trouvé dans $DIR_JOBS_FILE"
        return 3
    fi

    # Message si auto et succès
    [[ "$ACTION_MODE" == "auto" && $ret -eq 0 ]] && \
        display_msg "verbose|hard" --theme ok "Consultation des jobs : passée"

return 0
}


###############################################################################
# Fonction : Edit le bon fichier de configuration de msmtp (si installation atypique)
###############################################################################
edit_msmtp_config() {
    local conf_file

    if ! conf_file="$(check_msmtp_configured 2>/dev/null)"; then
        # Aucun fichier valide → on choisit ~/.msmtprc par défaut
        conf_file="${HOME}/.msmtprc"
        print_fancy --theme "warning" "Aucun fichier msmtp valide trouvé, création de : $conf_file"

        # Création + permissions strictes
        touch "$conf_file"
        chmod 600 "$conf_file"
    fi

    # Vérification des permissions (msmtp râle si elles ne sont pas correctes)
    if [[ -f "$conf_file" ]]; then
        chmod 600 "$conf_file"
    fi

    print_fancy --theme "info" "Édition du fichier msmtp : $conf_file"
    "${EDITOR:-nano}" "$conf_file"
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

    print_aligned_table "Date / Heure début"   "$(safe_var "START_TIME")"
    print_aligned_table "Date / Heure fin"     "$END_TIME"
    print_aligned_table "Mode de lancement"    "$(safe_var "INITIAL_LAUNCH")"
    print_aligned_table "Nb. de jobs traités"  "$(safe_var "EXECUTED_JOBS") / $(safe_count JOBS_LIST)"
    print_aligned_table "Dernier code erreur"  "$(safe_var "ERROR_CODE")"
    print_aligned_table "Dossier"              "$(safe_var "DIR_LOG")/"
    print_aligned_table "Log mail"             "$(safe_var "DIR_LOG_FILE_MAIL")"
    print_aligned_table "Log rclone"           "$(safe_var "DIR_LOG_FILE_INFO")"

    if [[ -n "${MAIL_TO:-}" ]]; then
        print_aligned_table "Copie du mail"        "$(safe_var "DIR_TMP_MAIL")"
        print_aligned_table "Email envoyé à"       "$(safe_var "MAIL_TO")"
        print_aligned_table "Sujet email"          "$(safe_var "SUBJECT_RAW")"
    fi

    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        print_aligned_table "Notifs Discord"      "✅  Oui : Traitée(s)"
    else
        print_aligned_table "Notifs Discord"      "⚠️  Aucun webhook Discord de défini."
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        print_aligned_table "Simulation (dry-run)" "✅  Oui : aucune modification de fichiers."
    else
        print_aligned_table "Simulation (dry-run)" " - Non activée"
    fi

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='
    print_fancy --align "center" --bg "yellow" --fg "black" "--- Fin du rapport ---"
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
    # Vérifier si la variable existe et est bien un tableau
    if [[ -n "$1" && "$(declare -p "$1" 2>/dev/null)" =~ "declare -a"|"declare -A" ]]; then
        local -n arr="$1"
        echo "${#arr[@]}"
    else
        echo 0
    fi
}


###############################################################################
# Fonction : Création des répertoires temporaires nécessaires
###############################################################################
create_temp_dirs() {
    # DIR_TMP
    if [[ ! -d "$DIR_TMP" ]]; then
        mkdir -p "$DIR_TMP" 2>/dev/null || die 5 "Impossible de créer le dossier temporaire : $DIR_TMP"
    fi

    # DIR_LOG
    if [[ ! -d "$DIR_LOG" ]]; then
        mkdir -p "$DIR_LOG" 2>/dev/null || die 6 "Impossible de créer le dossier de logs : $DIR_LOG"
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
# Fonction : Contrôle et validation des variables avec menu
# Entrée : nom du tableau associatif
###############################################################################
menu_validation_local_variables() {
    local -n var_array="$1"

    if ! print_table_vars_invalid "$1"; then
        # Problème
        echo
        print_fancy --theme "error" "Configuration invalide. Vérifiez les variables (locales) ❌"
        echo
        echo
        print_fancy --fg green "-------------------------------------------"
        print_fancy --fg green --style bold "  Aide au débogage : Configuration locale"
        print_fancy --fg green "-------------------------------------------"
        echo
        echo -e "${UNDERLINE}Voulez-vous :${RESET}"
        echo
        echo -e "[1] Appliquer la valeur ${BOLD}Défaut${RESET} automatiquement."
        echo -e "${ITALIC}    => N'est valable que pour cette session.${RESET}"
        echo -e "[2] Editer la configuration locale pour ${UNDERLINE}corriger${RESET}."
        echo -e "[3] Quitter."
        echo

        read -e -rp "Votre choix [1-3] : " choice
        echo

        case "$choice" in
            1)
                echo
                echo "👉  Application de la correction automatique."
                echo
                self_validation_local_variables "$1"
                ;;
            2)
                echo
                if ! mini_edit_local_config; then
                    print_fancy --bg yellow --fg red --highlight "⚠️  Le mystère s’épaissit... où se trouve le soucis ?!"
                    print_fancy --bg yellow --fg red --highlight "Aucun fichier disponible, retour au menu principal."
                fi
                menu_validation_local_variables  "$1" # retour au menu principal après édition pour validation
                ;;
            3)
                echo
                die 99 "Interruption par l’utilisateur"
                echo
                ;;
            *)
                echo "❌  Choix invalide."
                sleep 1
                menu_validation_local_variables "$1"
                ;;
        esac
        return 1
    fi
    return 0
    # Pas de problèmes
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
    echo

    if [[ "$subchoice" -ge 1 && "$subchoice" -lt "$i" ]]; then
        local target="${existing[$((subchoice-1))]}"
        ${EDITOR:-nano} "$target"
    fi
}


###############################################################################
# Fonction de purge des fichiers anciens
###############################################################################
purge_old_files() {
    local retention_days="$1"
    shift
    local dirs=("$@")  # tous les dossiers passés en arguments

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -mtime +"$retention_days" -delete 2>/dev/null
            display_msg "verbose|hard" --theme ok "Purge effectuée dans $dir"
        else
            display_msg "soft|verbose|hard" --theme warning "Dossier inexistant : $dir"
        fi
    done
}