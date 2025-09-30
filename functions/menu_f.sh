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
    read -rp "❓  Voulez-vous créer ce fichier ? [y/N] : " REPLY
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
    read -rp "✏️  Voulez-vous éditer le fichier maintenant avec $EDITOR ? [Y/n] : " EDIT_REPLY
    EDIT_REPLY=${EDIT_REPLY,,}
    if [[ -z "$EDIT_REPLY" || "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        $EDITOR "$user_file"
    else
        print_fancy --theme "info" "Édition ignorée pour : $user_file"
    fi
}