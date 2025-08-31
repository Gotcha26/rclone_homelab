###############################################################################
# Fonction : Vérifie s'il existe une nouvelle release ou branche
# NE MODIFIE PAS le dépôt
###############################################################################
check_update() {

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Récupérer les infos distantes
    git fetch origin "$BRANCH" --tags --quiet

    # Récupérer le dernier tag de la branche active
    latest_tag=$(git tag --merged "origin/$BRANCH" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        print_fancy --fg "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
        return
    fi

    if [[ "$latest_tag" != "$VERSION" ]]; then
        MSG_MAJ_UPDATE1=$(printf "$MSG_MAJ_UPDATE_TEMPLATE" "$latest_tag" "$VERSION")
        echo
        print_fancy --align "left" --fg "green" --style "italic" "$MSG_MAJ_UPDATE1"
        print_fancy --align "center" --fg "green" --style "italic" "$MSG_MAJ_UPDATE2"
    fi
}


###############################################################################
# Fonction : Met à jour le script vers la dernière branche (forcée)
# Appel explicite uniquement
###############################################################################
force_update_branch() {
    local branch="${FORCE_BRANCH:-$BRANCH}"
    MSG_MAJ_UPDATE_BRANCH=$(printf "$MSG_MAJ_UPDATE_BRANCH_TEMPLATE" "$branch")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_BRANCH"

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Récupération des dernières infos du remote
    git fetch --all --tags

    # Assure que l'on est bien sur la branche souhaitée
    git checkout -f "$branch" || { echo "Erreur lors du checkout de $branch" >&2; exit 1; }

    # Écrase toutes les modifications locales, y compris fichiers non suivis
    git reset --hard "origin/$branch"
    git clean -fd

    # Rendre le script principal exécutable
    chmod +x "$SCRIPT_DIR/rclone_sync_main.sh"

    print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_BRANCH_SUCCESS"

    # Quitter immédiatement pour que le script relancé prenne en compte la mise à jour
    exit 0
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (dernier tag
# présent sur la branche courante définie dans la config)
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Déterminer la branche active via config (ou fallback main)
    local branch="${FORCE_BRANCH:-$BRANCH}"

    # Récupérer les infos distantes
    git fetch origin "$branch" --tags

    # Lister uniquement les tags atteignables depuis la branche
    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        echo "Aucun tag trouvé sur la branche $branch" >&2
        exit 1
    fi

    # Hash du tag distant et hash local
    local remote_hash
    remote_hash=$(git rev-parse "$latest_tag")
    local local_hash
    local_hash=$(git rev-parse HEAD)

    MSG_MAJ_UPDATE_RELEASE=$(printf "$MSG_MAJ_UPDATE_RELEASE_TEMPLATE" "$latest_tag")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_RELEASE"

    if [[ "$remote_hash" != "$local_hash" ]]; then
        # Essayer le checkout sécurisé sans message detached HEAD
        if git -c advice.detachedHead=false checkout "$latest_tag"; then
            chmod +x "$SCRIPT_DIR/rclone_sync_main.sh"
            MSG_MAJ_UPDATE_TAG_SUCCESS=$(printf "$MSG_MAJ_UPDATE_TAG_SUCCESS_TEMPLATE" "$latest_tag")
            print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_TAG_SUCCESS"
            exit 0
        else
            MSG_MAJ_UPDATE_TAG_FAILED=$(printf "$MSG_MAJ_UPDATE_TAG_FAILED_TEMPLATE" "$latest_tag")
            print_fancy --align "center" --theme "error" "$MSG_MAJ_UPDATE_TAG_FAILED"
            exit 1
        fi
    else
        MSG_MAJ_UPDATE_TAG_REJECTED=$(printf "$MSG_MAJ_UPDATE_TAG_REJECTED_TEMPLATE" "$latest_tag")
        print_fancy --align "center" --theme "info" "$MSG_MAJ_UPDATE_TAG_REJECTED"
        exit 0
    fi
}