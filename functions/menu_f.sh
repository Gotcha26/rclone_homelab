###############################################################################
# Fonction : Ajout des options (affichage) pour le menu interactif
###############################################################################
add_option() {
    MENU_OPTIONS+=("$1")
    MENU_ACTIONS+=("$2")
}


###############################################################################
# Fonction : Ajoute un séparateur seulement si la dernière entrée n'est pas déjà un séparateur
###############################################################################
add_separator_if_needed() {
    if (( ${#MENU_OPTIONS[@]} > 0 )) && [[ "${MENU_ACTIONS[-1]}" != "__separator__" ]]; then
        MENU_OPTIONS+=("────────────────────────────────────")
        MENU_ACTIONS+=("__separator__")
    fi
}


###############################################################################
# Fonction : Calcul du numéro de l'option dans une liste interactive (instable par nature)
###############################################################################
print_menu() {
    local -n options=$1
    local -n actions=$2
    local -n choice_to_index=$3
    local -n num_ref=$4   # référence vers la variable num

    local max_len=0 text_len

    for i in "${!options[@]}"; do
        [[ "${actions[$i]}" == "__separator__" || "${actions[$i]}" == "quit" ]] && continue
        if [[ "${options[$i]}" =~ \[(.*)\] ]]; then
            text_len=$((${#options[$i]} - ${#BASH_REMATCH[0]}))
        else
            text_len=${#options[$i]}
        fi
        (( text_len > max_len )) && max_len=$text_len
    done

    for i in "${!options[@]}"; do
        if [[ "${actions[$i]}" == "__separator__" ]]; then
            echo "    ${options[$i]}"
        elif [[ "${actions[$i]}" == "quit" ]]; then
            printf "q) %-${max_len}s\n" "${options[$i]}"
        else
            printf "%d) %-${max_len}s\n" "$num_ref" "${options[$i]}"
            choice_to_index[$num_ref]=$i
            ((num_ref++))
        fi
    done
}


###############################################################################
# Fonction : Initialiser un fichier local si absent
# Usage : init_file <ID>
# Fonctionne avec le tableau VARS_LOCAL_FILES
###############################################################################
init_file() {
    local id="$1"

    # Vérifier que l'ID existe dans le tableau
    if [[ -z "${VARS_LOCAL_FILES[$id]}" ]]; then
        print_fancy --theme "error" "ID inconnu : $id"
        return 1
    fi

    # Récupérer les chemins source (ref_file) et destination (user_file)
    IFS=';' read -r ref_file user_file <<< "${VARS_LOCAL_FILES[$id]}"
    local last_ref_backup="$BACKUP_DIR/last_$(basename "$ref_file")"

    print_fancy --style "underline" "⚙️  Initialisation de $user_file"
    print_fancy --fg "blue" -n "Fichier d'origine : "; print_fancy "$ref_file"
    print_fancy --fg "blue" -n "Fichier créé      : "; print_fancy "$user_file"

    # Création du dossier si nécessaire
    mkdir -p "$(dirname "$user_file")" || {
        print_fancy --theme "error" "Impossible de créer le dossier cible $(dirname "$user_file")"
        return 1
    }

    # Copier la référence vers la cible
    cp -f "$ref_file" "$user_file" || {
        print_fancy --theme "error" "Impossible de copier $ref_file vers $user_file"
        return 1
    }
    print_fancy --theme "success" "Fichier installé : $user_file"

    # Sauvegarde de la référence pour suivi
    if mkdir -p "$BACKUP_DIR" && cp -f "$ref_file" "$last_ref_backup"; then
        print_fancy --theme "success" "Backup de référence mis à jour : $last_ref_backup"
    else
        print_fancy --theme "error" "Échec de la sauvegarde de la référence ($ref_file → $last_ref_backup)"
    fi

    # Ouverture directe de l’éditeur
    echo
    print_fancy --theme "info" "Ouverture de l'éditeur : $EDITOR"
    "$EDITOR" "$user_file"
}


###############################################################################
# Fonction : Sélection interactive d'un composant (menu commun)
# Usage    : _dev_select_component <label_action> <composant1> <composant2> ...
# Retour   : le nom du composant choisi sur stdout, code 0=ok, 1=abandon/invalide
###############################################################################
_dev_select_component() {
    local action_label="$1"
    shift
    local supported=("$@")

    echo
    echo "📦  Sélectionne le composant à $action_label :"
    echo

    # Calcul largeur max des noms pour aligner le statut
    local max_len=0
    for item in "${supported[@]}"; do
        (( ${#item} > max_len )) && max_len=${#item}
    done

    # Affichage menu
    local i=1
    for item in "${supported[@]}"; do
        local status="absent"
        [[ -x "$(command -v "$item" 2>/dev/null)" ]] && status="installé"
        printf "  %d) %-*s [%s]\n" "$i" "$max_len" "$item" "$status"
        ((i++))
    done
    printf "  q) Retour\n"
    echo

    read -e -rp "👉  Ton choix : " choice
    echo
    if [[ "$choice" == "q" ]]; then
        echo "❌  Abandon." >&2
        return 1
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#supported[@]} )); then
        echo "${supported[$((choice-1))]}"
        return 0
    else
        echo "❌  Choix invalide." >&2
        return 1
    fi
}


###############################################################################
# Fonction : Résolution binaire → paquet(s) Debian
# Usage    : _resolve_debian_pkg <binary_name>
# Retour   : le(s) nom(s) de paquet(s) sur stdout, code 1 si non géré
###############################################################################
_resolve_debian_pkg() {
    local binary_name="$1"
    case "$binary_name" in
        rclone)    echo "rclone" ;;
        msmtp)     echo "msmtp msmtp-mta" ;;
        colordiff) echo "colordiff" ;;
        git)       echo "git" ;;
        curl)      echo "curl" ;;
        unzip)     echo "unzip" ;;
        perl)      echo "perl" ;;
        jq)        echo "jq" ;;
        *)
            print_fancy --theme error "'$binary_name' n'est pas géré par ce script."
            return 1
            ;;
    esac
}


###############################################################################
# Fonction : Désinstallation générique d'un binaire/paquet avec menu et état
# Usage    : dev_uninstall [binaire]
###############################################################################
dev_uninstall() {
    local binary_name="${1:-}"

    # Si pas d'argument → afficher menu
    if [[ -z "${binary_name:-}" ]]; then
        binary_name=$(_dev_select_component "désinstaller" "rclone" "msmtp" "colordiff" "git" "curl" "unzip" "perl" "jq") || return $?
    fi

    local debian_pkgs
    debian_pkgs=$(_resolve_debian_pkg "$binary_name") || return 1

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
            $SUDO apt remove --purge -y $debian_pkgs
            $SUDO apt autoremove -y
            print_fancy --theme success "$binary_name a été désinstallé avec apt."
            return 0
        else
            print_fancy --theme ok "Installation manuelle détectée (binaire copié directement)."
            print_fancy --theme info "Suppression du fichier : $path"
            $SUDO rm -f "$path"
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
            $SUDO rm -f "$msmtpq_path"
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

    # Si pas d'argument → afficher menu
    if [[ -z "${binary_name:-}" ]]; then
        binary_name=$(_dev_select_component "installer" "colordiff" "git" "curl" "unzip" "perl" "jq") || return $?
    fi

    local debian_pkgs
    debian_pkgs=$(_resolve_debian_pkg "$binary_name") || return 1

    if command -v "$binary_name" >/dev/null 2>&1; then
        print_fancy --theme ok "$binary_name est déjà installé."
        return 0
    fi

    print_fancy "🔍 Installation de $binary_name via apt..."
    print_fancy --theme info "Exécution : sudo apt update && sudo apt install -y $debian_pkgs"
    $SUDO apt update
    $SUDO apt install -y $debian_pkgs
    print_fancy --theme success "$binary_name installé avec succès !"
}
