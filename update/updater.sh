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
# Fonction : Récupère toutes les informations nécessaires sur Git
# Retourne les variables suivantes :
# - head_commit / head_epoch
# - remote_commit / remote_epoch
# - latest_tag / latest_tag_epoch
# - branch_real
# - current_tag
###############################################################################
fetch_git_info() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # Récupération des dernières infos du remote
    git fetch --all --tags --quiet

    # Commit et date HEAD local
    head_commit=$(git rev-parse HEAD)
    head_epoch=$(git show -s --format=%ct "$head_commit")

    # Détecter la branche réelle
    branch_real=$(git branch --show-current)
    if [[ -z "$branch_real" ]]; then
        branch_real=$(git branch -r --contains "$head_commit" | head -n1 | sed 's|origin/||')
    fi
    [[ -z "$branch_real" ]] && branch_real="(détaché)"

    # Commit et date HEAD distant
    remote_commit=$(git rev-parse "origin/$branch_real")
    remote_epoch=$(git show -s --format=%ct "$remote_commit")

    # Dernier tag disponible sur la branche réelle
    latest_tag=$(git tag --merged "origin/$branch_real" | sort -V | tail -n1)
    if [[ -n "$latest_tag" ]]; then
        latest_tag_commit=$(git rev-parse "$latest_tag")
        latest_tag_epoch=$(git show -s --format=%ct "$latest_tag_commit")
    else
        latest_tag_commit=""
        latest_tag_epoch=0
    fi

    # Tag actuel si HEAD exactement sur un tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
}

###############################################################################
# Fonction : Analyse les informations Git et décide de l’état de mise à jour
# Utilise les variables remplies par fetch_git_info
###############################################################################
analyze_update_status() {

    echo
    # Affichage plus précis : si HEAD détaché ou commit non aligné avec la branche actuelle
    if git describe --tags --exact-match >/dev/null 2>&1; then
        branch_display="$branch_real"
    else
        # Détecte la branche principale du commit local via git for-each-ref
        branch_display=$(git for-each-ref --format='%(refname:short)' --contains "$head_commit" | head -n1)
    fi
    echo "📌  Branche locale : ${branch_display:-(détaché)}"
    echo "📌  Commit local   : $head_commit ($(date -d "@$head_epoch"))"
    echo "🕒  Commit distant : $remote_commit ($(date -d "@$remote_epoch"))"
    [[ -n "$latest_tag" ]] && echo "🕒  Dernière vers. : $latest_tag ($(date -d "@$latest_tag_epoch"))"

    # --- Branche main ---
    if [[ "$branch_real" == "main" ]]; then
        if [[ -z "$latest_tag" ]]; then
            print_fancy --fg "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
            return 1
        fi

        # Déjà sur le dernier tag ou commit local plus récent ?
        if [[ "$head_commit" == "$latest_tag_commit" ]] || git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
            echo "✅  Bilan          : ${current_tag:-dev} >> A jour"
            return 0
        fi

        # Comparaison horodatage
        echo
        echo "⚡  Nouvelle release détectée : $latest_tag ($(date -d "@$latest_tag_epoch"))"
        if (( latest_tag_epoch < head_epoch )); then
            print_fancy --bg "yellow" --align "center" --highlight \
                "⚠️  Attention : votre commit local est plus récent que la dernière release !"
            echo "👉  Forcer la mise à jour pourrait écraser des changements locaux"
            return 0
        else
            echo "🕒  Dernière release disponible : $latest_tag ($(date -d "@$latest_tag_epoch"))"
            echo "ℹ️  Pour mettre à jour : relancer le script en mode menu ou utiliser --update-tag"
            return 1
        fi
    fi

    # --- Branche dev ou expérimentale ---
    if [[ "$head_commit" == "$remote_commit" ]]; then
        echo "✅  Votre branche est à jour avec l'origine."
        return 0
    fi

    if (( head_epoch < remote_epoch )); then
        print_fancy --bg "blue" --align "center" --highlight \
            "⚡  Mise à jour disponible : votre commit est plus ancien que origin/$branch_real"
        return 1
    else
        print_fancy --bg "green" --align "center" --highlight \
            "⚠️  Votre commit est plus récent que origin/$branch_real"
        return 0
    fi
}

###############################################################################
# Fonction principale : update_check
###############################################################################
update_check() {
    fetch_git_info || return 1
    analyze_update_status
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
    head_date=$(git --no-pager show -s --format=%ci "$head_commit")

    local latest_tag_commit latest_tag_date
    latest_tag_commit=$(git rev-parse "$latest_tag")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit")

    local current_tag
    current_tag=$(git --no-pager describe --tags --exact-match 2>/dev/null || echo "")

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