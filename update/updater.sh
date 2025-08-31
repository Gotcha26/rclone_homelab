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
# Fonction : Met à jour le script vers la dernière release (dernier tag)
# Appel explicite uniquement.
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    git fetch --tags

    # Dernier tag distant
    local latest_tag
    latest_tag=$(git tag -l | sort -V | tail -n1)

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
            exit 0  # Quitter après succès
        else
            # Si échec (modifications locales)
            MSG_MAJ_UPDATE_TAG_FAILED=$(printf "$MSG_MAJ_UPDATE_TAG_FAILED_TEMPLATE" "$latest_tag")
            print_fancy --align "center" --theme "error" "$MSG_MAJ_UPDATE_TAG_FAILED"
            exit 1  # Quitter après échec
        fi
    else
        MSG_MAJ_UPDATE_TAG_REJECTED=$(printf "$MSG_MAJ_UPDATE_TAG_REJECTED_TEMPLATE" "$latest_tag")
        print_fancy --align "center" --theme "info" "$MSG_MAJ_UPDATE_TAG_REJECTED"
        exit 0  # Quitter même si rien à faire
    fi
}