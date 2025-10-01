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
# Fonction : Initialiser un fichier si absent (config ou secrets, ex: jobs)
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

    # Message spécifique si secrets
    local info_msg="Vous êtes sur le point de créer un fichier personnalisable de configuration."
    if [[ "$id" == "conf_secret" ]]; then
        info_msg="Vous êtes sur le point de créer un fichier pour vos clés secrètes. (optionnel)"
    fi

    echo
    echo
    print_fancy --style "underline" "⚙️  Création de $user_file"
    print_fancy --theme "info" "$info_msg"
    print_fancy --fg "blue" -n "Fichier d'origine : "; print_fancy "$ref_file"
    print_fancy --fg "blue" -n "Fichier à créer   : "; print_fancy "$user_file"
    echo

    # Confirmation utilisateur
    read -e -rp "❓  Voulez-vous créer ce fichier ? [Y/n] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        print_fancy --theme "info" "Création ignorée pour : $user_file"
        return 1
    fi

    # Création du dossier si nécessaire
    mkdir -p "$(dirname "$user_file")" || {
        print_fancy --theme "error" "Impossible de créer le dossier cible $(dirname "$user_file")"
        return 1
    }

    # Copier le fichier d'exemple -> fichier utilisateur
    cp "$ref_file" "$user_file" || {
        print_fancy --theme "error" "Impossible de copier $ref_file vers $user_file"
        return 1
    }
    print_fancy --theme "success" "Fichier installé : $user_file"

    # Sauvegarde de la référence actuelle pour suivi des mises à jour
    if mkdir -p "$BACKUP_DIR" && cp -f "$ref_file" "$last_ref_backup"; then
        print_fancy --theme "success" \
            "Backup de référence mis à jour : $last_ref_backup"
    else
        print_fancy --theme "error" \
            "Échec de la sauvegarde du fichier de référence ($ref_file → $last_ref_backup)"
        return 1
    fi

    # Proposer l'édition immédiate
    echo
    read -e -rp "✏️  Voulez-vous éditer le fichier maintenant avec $EDITOR ? [Y/n] : " EDIT_REPLY
    EDIT_REPLY=${EDIT_REPLY,,}
    if [[ -z "$EDIT_REPLY" || "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        $EDITOR "$user_file"
    else
        print_fancy --theme "info" "Édition ignorée pour : $user_file"
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
        printf "  q) Quitter\n"
        echo

        read -e -rp "👉  Ton choix : " choice
        echo
        if [[ "$choice" == "q" ]]; then
            echo "❌  Abandon."
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#supported[@]} )); then
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
    local debian_pkgs=""

    # Liste supportée
    local supported=("colordiff" "git" "curl" "unzip" "perl" "jq")

    # Si pas d’argument → afficher menu
    if [[ -z "${binary_name:-}" ]]; then
        echo
        echo "📦  Sélectionne le logiciel à installer :"
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
        printf "  q) Quitter\n"
        echo

        read -e -rp "👉  Ton choix : " choice
        echo
        if [[ "$choice" == "q" ]]; then
            echo "❌  Abandon."
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#supported[@]} )); then
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
    $SUDO apt update
    $SUDO apt install -y $debian_pkgs
    print_fancy --theme success "$binary_name installé avec succès !"
}
