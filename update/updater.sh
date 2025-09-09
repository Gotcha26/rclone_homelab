#!/usr/bin/env bash

###############################################################################
# Fonction : Met à jour (forcée) du script sur la branche en cour ou sur une branche spécifiée si précisée
# Appel explicite ou implicite si forcé via FORCE_UPDATE=true
###############################################################################
update_force_branch() {
    local branch="${FORCE_BRANCH:-$BRANCH}"
    MSG_MAJ_UPDATE_BRANCH=$(printf "$MSG_MAJ_UPDATE_BRANCH_TEMPLATE" "$branch")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_BRANCH"

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Récupération des dernières infos du remote
    git fetch --all --tags

    # Vérifie si la branche locale est déjà à jour
    local local_hash remote_hash
    local_hash=$(git rev-parse "$branch")
    remote_hash=$(git rev-parse "origin/$branch")

    if [[ "$local_hash" == "$remote_hash" ]]; then
        # Rien à mettre à jour → on retourne 1
        print_fancy --align "center" --theme "info" "Branche '$branch' déjà à jour"
        return 1
    fi

    # Assure que l'on est bien sur la branche souhaitée
    git checkout -f "$branch" || { echo "Erreur lors du checkout de $branch" >&2; exit 1; }

    # Écrase toutes les modifications locales, y compris fichiers non suivis
    git reset --hard "origin/$branch"
    git clean -fd

    # Rendre le script principal exécutable
    chmod +x "$SCRIPT_DIR/main.sh"

    print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_BRANCH_SUCCESS"

    # Retourne 0 pour signaler qu’une MAJ a été effectuée
    return 0
}


###############################################################################
# Fonction : Met à jour automatique du script vers la dernière release
# Informe de l'état de la mise à jour
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    local branch="${FORCE_BRANCH:-$BRANCH}"

    git fetch origin "$branch" --tags --quiet

    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        echo "❌ Aucun tag trouvé sur la branche $branch"
        return 1
    fi

    local latest_tag_hash head_hash
    latest_tag_hash=$(git rev-parse "$latest_tag")
    head_hash=$(git rev-parse HEAD)

    # HEAD exactement sur un tag ?
    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    if [[ "$head_hash" == "$latest_tag_hash" ]]; then
        echo "✅ Déjà sur la dernière release : $latest_tag"
        return 0
    elif git merge-base --is-ancestor "$latest_tag_hash" "$head_hash"; then
        echo "ℹ️ Vous êtes en avance sur la dernière release : $latest_tag"
        echo "👉 HEAD actuel : $(git rev-parse --short HEAD)"
        echo "✅ Aucune action effectuée pour éviter une régression"
        return 0
    else
        echo "⚡ Nouvelle release détectée : $latest_tag (HEAD actuel : $(git rev-parse --short HEAD))"
        if git -c advice.detachedHead=false checkout "$latest_tag"; then
            chmod +x "$SCRIPT_DIR/main.sh"
            echo "🎉 Mise à jour réussie vers $latest_tag"
            return 0
        else
            echo "❌ Échec lors du passage à $latest_tag"
            return 1
        fi
    fi
}


###############################################################################
# Fonction : Vérifie s'il existe une nouvelle release ou branche
# NE MODIFIE PAS le dépôt
###############################################################################
update_check() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    local branch="${FORCE_BRANCH:-$BRANCH}"

    git fetch origin "$branch" --tags --quiet

    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        print_fancy --fg "red" --bg "white" --style "bold underline" "❌ Aucun tag trouvé sur la branche $branch"
        return 1
    fi

    local latest_tag_hash head_hash
    latest_tag_hash=$(git rev-parse "$latest_tag")
    head_hash=$(git rev-parse HEAD)

    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    if [[ "$head_hash" == "$latest_tag_hash" ]]; then
        print_fancy --align "center" --theme "info" "✅ Vous êtes sur la dernière release : $latest_tag"
    elif git merge-base --is-ancestor "$latest_tag_hash" "$head_hash"; then
        print_fancy --align "center" --theme "warning" "ℹ️ Vous êtes en avance sur la dernière release : $latest_tag"
        print_fancy --align "center" --theme "warning" "👉 HEAD actuel : $(git rev-parse --short HEAD)"
    else
        print_fancy --align "center" --theme "info" "⚡ Nouvelle release disponible : $latest_tag (HEAD actuel : $(git rev-parse --short HEAD))"
    fi
}