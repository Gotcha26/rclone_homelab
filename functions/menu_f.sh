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
# Fonction : Initialiser un fichier si absent (config ou secrets)
# Usage : init_file <ID>
###############################################################################
init_file() {
    local id="$1"

    # Vérifier que l'ID existe dans le tableau
    if [[ -z "${VARS_LOCAL_FILES[$id]}" ]]; then
        print_fancy --theme "error" "ID inconnu : $id"
        return 1
    fi

    # Récupérer les chemins source et destination
    IFS=';' read -r main_file target_file <<< "${VARS_LOCAL_FILES[$id]}"

    # Message spécifique si secrets
    local info_msg="Vous êtes sur le point de créer un fichier personnalisable de configuration."
    if [[ "$id" == "conf_secret" ]]; then
        info_msg="Vous êtes sur le point de créer un fichier pour vos clés secrètes. (optionnel)"
    fi

    echo
    echo
    print_fancy --style "underline" "⚙️  Création de $target_file"
    print_fancy --theme "info" "$info_msg"
    print_fancy --fg "blue" -n "Fichier d'origine : "; print_fancy "$main_file"
    print_fancy --fg "blue" -n "Fichier à créer   : "; print_fancy "$target_file"
    echo

    # Confirmation utilisateur
    read -rp "❓  Voulez-vous créer ce fichier ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        print_fancy --theme "info" "Création ignorée pour : $target_file"
        return 1
    fi

    # Création du dossier si nécessaire
    mkdir -p "$(dirname "$target_file")" || {
        print_fancy --theme "error" "Impossible de créer le dossier cible $(dirname "$target_file")"
        return 1
    }

    # Copier le fichier
    cp "$main_file" "$target_file" || {
        print_fancy --theme "error" "Impossible de copier $main_file vers $target_file"
        return 1
    }

    print_fancy --theme "success" "Fichier installé : $target_file"

    # Proposer l'édition immédiate
    echo
    read -rp "✏️  Voulez-vous éditer le fichier maintenant avec $EDITOR ? [Y/n] : " EDIT_REPLY
    EDIT_REPLY=${EDIT_REPLY,,}
    if [[ -z "$EDIT_REPLY" || "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        $EDITOR "$target_file"
    else
        print_fancy --theme "info" "Édition ignorée pour : $target_file"
    fi
}
