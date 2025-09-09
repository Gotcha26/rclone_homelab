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
# Affiche minimal pour main si à jour ou en avance, sinon détails complets
# Pour les branches dev ou autres expérimentales, affiche l'état local vs distant
###############################################################################
update_check() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    git fetch --all --tags --quiet

    # Commit et date HEAD local
    local head_commit head_date
    head_commit=$(git rev-parse HEAD)
    head_date=$(git show -s --format=%ci "$head_commit")

    # Détecter la branche réelle (HEAD peut être détaché)
    local branch_real
    branch_real=$(git branch --show-current)
    if [[ -z "$branch_real" ]]; then
        # HEAD détaché : tenter de déterminer une branche distante contenant ce commit
        branch_real=$(git branch -r --contains "$head_commit" | head -n1 | sed 's|origin/||')
    fi
    [[ -z "$branch_real" ]] && branch_real="(détaché)"

    # Dernier tag disponible sur la branche réelle
    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch_real" | sort -V | tail -n1)

    # Commit et date HEAD distant
    local remote_commit remote_date
    remote_commit=$(git rev-parse "origin/$branch_real")
    remote_date=$(git show -s --format=%ci "$remote_commit")

    # Tag actuel si HEAD exactement sur un tag
    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    # Affichage de la branche/commit réel
    echo
    echo "📌  Vous êtes actuellement sur le commit : $head_commit ($head_date)"
    echo "📌  Branch réelle utilisée pour les mises à jour : $branch_real"

    # --- Branche main (grand public) ---
    if [[ "$branch_real" == "main" ]]; then
        if [[ -z "$latest_tag" ]]; then
            print_fancy --fg "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
            return 1
        fi

        local latest_tag_commit
        latest_tag_commit=$(git rev-parse "$latest_tag")

        if [[ "$head_commit" == "$latest_tag_commit" ]] || git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
            echo "✅  Version actuelle ${current_tag:-dev} >> A jour"
            return 0
        else
            echo
            echo "⚡  Nouvelle release disponible : $latest_tag"
            echo "🕒  Dernier commit local  : $head_commit ($head_date)"
            echo "🕒  Dernier commit distant: $remote_commit ($remote_date)"
            echo "🕒  Dernière release      : $latest_tag"
            echo "ℹ️  Pour mettre à jour : relancer le script en mode menu ou utiliser --update-tag"
            return 1
        fi
    fi

    # --- Branche dev ou expérimentale ---
    echo "🕒  Commit distant : $remote_commit ($remote_date)"

    if [[ "$head_commit" == "$remote_commit" ]]; then
        echo "✅  Votre branche est à jour avec l'origine."
        return 0
    elif git merge-base --is-ancestor "$head_commit" "$remote_commit"; then
        print_fancy --bg "blue" --align "center" --highlight "⚡  Mise à jour possible : votre branche est en retard sur origin/$branch_real"
        return 1
    else
        print_fancy --bg "green" --align "center" --highlight "⚠️  Votre branche est en avance ou diverge sur origin/$branch_real"
        return 0
    fi
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (tag)
# Affiche horodatages pour plus de clarté
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    local branch="${FORCE_BRANCH:-$BRANCH}"

    git fetch origin "$branch" --tags --quiet

    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        echo "❌  Aucun tag trouvé sur la branche $branch"
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
    echo "📌  Branche : $branch"
    echo "🕒  Commit actuel : $head_commit ($head_date)"
    echo "🕒  Dernier tag    : $latest_tag ($latest_tag_date)"

    if [[ "$head_commit" == "$latest_tag_commit" ]]; then
        echo "✅  Déjà sur la dernière release : $latest_tag"
        return 0
    fi

    if git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
        echo "⚠️  Vous êtes en avance sur la dernière release : ${current_tag:-dev}"
        echo "👉  Pas de mise à jour effectuée"
        return 0
    fi

    echo "⚡ Nouvelle release détectée : $latest_tag (actuellement ${current_tag:-dev})"
    if git -c advice.detachedHead=false checkout "$latest_tag"; then
        chmod +x "$SCRIPT_DIR/main.sh"
        echo "🎉  Mise à jour réussie vers $latest_tag"
        echo "ℹ️  Pour plus d’infos, utilisez rclone_homelab sans arguments pour afficher le menu."
        return 0
    else
        echo "❌  Échec lors du passage à $latest_tag"
        return 1
    fi
}