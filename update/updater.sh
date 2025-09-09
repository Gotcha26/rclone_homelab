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
# Fonction : Vérifie s'il existe une nouvelle release (tag) sur la branche active
# Affiche également les horodatages des commits et tags
###############################################################################
update_check() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    git fetch origin "$BRANCH" --tags --quiet

    # Dernier tag atteignable depuis la branche
    local latest_tag
    latest_tag=$(git tag --merged "origin/$BRANCH" | sort -V | tail -n1)

    # Commit actuel et date
    local head_commit head_date
    head_commit=$(git rev-parse HEAD)
    head_date=$(git show -s --format=%ci "$head_commit")

    # Commit correspondant au dernier tag et date
    local latest_tag_commit latest_tag_date
    latest_tag_commit=$(git rev-parse "$latest_tag")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit")

    # Vérifier si on est sur un tag exact
    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    echo
    echo "📌 Branche : $BRANCH"
    echo "🕒 Commit actuel : $head_commit (${head_date})"
    echo "🕒 Dernier tag    : $latest_tag (${latest_tag_date})"

    if [[ "$head_commit" == "$latest_tag_commit" ]]; then
        echo "✅ Vous êtes sur la dernière release : $latest_tag"
    elif git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
        echo "⚠️ Vous êtes en avance sur la dernière release : ${current_tag:-dev}"
        echo "👉 Dernière release stable : $latest_tag"
    else
        echo "⚡ Nouvelle release disponible : $latest_tag"
        echo "👉 Votre version actuelle : ${current_tag:-dev}"
    fi
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (tag)
# Affiche les horodatages pour plus de clarté
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

    local head_commit head_date
    head_commit=$(git rev-parse HEAD)
    head_date=$(git show -s --format=%ci "$head_commit")

    local latest_tag_commit latest_tag_date
    latest_tag_commit=$(git rev-parse "$latest_tag")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit")

    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    echo
    echo "📌 Branche : $branch"
    echo "🕒 Commit actuel : $head_commit (${head_date})"
    echo "🕒 Dernier tag    : $latest_tag (${latest_tag_date})"

    if [[ "$head_commit" == "$latest_tag_commit" ]]; then
        echo "✅ Déjà sur la dernière release : $latest_tag"
        return 0
    fi

    if git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
        echo "⚠️ Vous êtes en avance sur la dernière release : ${current_tag:-dev}"
        echo "👉 Pas de mise à jour effectuée"
        return 0
    fi

    echo "⚡ Nouvelle release détectée : $latest_tag (actuellement ${current_tag:-dev})"
    if git -c advice.detachedHead=false checkout "$latest_tag"; then
        chmod +x "$SCRIPT_DIR/main.sh"
        echo "🎉 Mise à jour réussie vers $latest_tag"
        return 0
    else
        echo "❌ Échec lors du passage à $latest_tag"
        return 1
    fi
}

