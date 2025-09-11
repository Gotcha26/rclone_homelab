#!/usr/bin/env bash


###############################################################################
# Fonction principale : update_check
###############################################################################
update_check() {
    fetch_git_info || return 1
    analyze_update_status
}


###############################################################################
# Fonction : Récupère toutes les informations nécessaires sur Git
# Variables retournées :
# - head_commit / head_epoch
# - remote_commit / remote_epoch
# - latest_tag / latest_tag_epoch
# - branch_real
# - current_tag
# Paramètre de sécurité : IGNORE_LOCAL_CHANGES=true pour écraser temporairement tout
###############################################################################
fetch_git_info() {

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # Option : ignorer les modifications locales non commitées
    if [[ "${IGNORE_LOCAL_CHANGES:-false}" == true ]]; then
        # stash temporaire de tout l'état local
        STASH_NAME="tmp_stash_$(date +%s)"
        git stash push -u -m "$STASH_NAME" >/dev/null 2>&1 || true
    fi

    # Récupération des dernières infos du remote
    git fetch origin --tags --prune --quiet

    # Commit et date HEAD local
    head_commit=$(git rev-parse HEAD)
    head_epoch=$(git show -s --format=%ct "$head_commit")

    # Détection de la branche locale réelle
    branch_real=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(détaché)")

    # Commit et date HEAD distant (seulement si branche existante)
    if [[ "$branch_real" != "(détaché)" ]]; then
        remote_commit=$(git rev-parse "origin/$branch_real" 2>/dev/null || echo "")
        remote_epoch=$(git show -s --format=%ct "$remote_commit" 2>/dev/null || echo 0)
    else
        remote_commit=""
        remote_epoch=0
    fi

    # Dernier tag disponible sur la branche réelle
    if [[ "$branch_real" != "(détaché)" ]]; then
        latest_tag=$(git tag --merged "origin/$branch_real" | sort -V | tail -n1)
    else
        latest_tag=""
    fi

    if [[ -n "$latest_tag" ]]; then
        latest_tag_commit=$(git rev-parse "$latest_tag")
        latest_tag_epoch=$(git show -s --format=%ct "$latest_tag_commit")
    else
        latest_tag_commit=""
        latest_tag_epoch=0
    fi

    # Tag actuel si HEAD exactement sur un tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    # Re-appliquer les modifications locales si on a stashed
    if [[ "${IGNORE_LOCAL_CHANGES:-false}" == true ]]; then
        git stash pop >/dev/null 2>&1 || true
    fi
}


###############################################################################
# Fonction : Affichage des informations Git issues de fetch_git_info()
###############################################################################
analyze_update_status() {
    echo "################################################################################"
    echo " INFOS GIT"
    echo
    echo "📌  Branche locale      : $branch_real"
    echo "📌  Commit local        :
    $head_commit ($(date -d "@$head_epoch"))"
    [[ -n "$remote_commit" ]] && echo "🕒  Commit distant      :
    $remote_commit ($(date -d "@$remote_epoch"))"
    [[ -n "$latest_tag" ]] && echo "🕒  Dernière release    : $latest_tag ($(date -d "@$latest_tag_epoch"))"

    if [[ "$branch_real" == "main" ]]; then
        # Branche main : vérifier si on est à jour avec la dernière release
        if [[ -z "$latest_tag" ]]; then
            print_fancy --fg "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
            return 1
        fi

        if [[ "$head_commit" == "$latest_tag_commit" ]] || git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
            echo
            echo "✅  Version actuelle ${current_tag:-dev} >> A jour"
            return 0
        fi

        if (( latest_tag_epoch < head_epoch )); then
            echo
            print_fancy --bg "yellow" --align "center" --highlight \
                "⚠️  Attention : votre commit local est plus récent que la dernière release !"
            echo "👉  Forcer la mise à jour pourrait écraser des changements locaux"
            return 0
        else
            echo
            echo "⚡ Nouvelle release disponible : $latest_tag ($(date -d "@$latest_tag_epoch"))"
            echo "ℹ️  Pour mettre à jour : relancer le script en mode menu ou utiliser --update-tag"
            return 1
        fi
    else
        # Branche dev ou autre
        if [[ -z "$remote_commit" ]]; then
            echo
            echo "ℹ️  Aucune branche distante détectée pour '$branch_real'"
            return 1
        fi

        if [[ "$head_commit" == "$remote_commit" ]]; then
            echo
            echo "✅  Votre branche est à jour avec l'origine."
            return 0
        fi

        if (( head_epoch < remote_epoch )); then
            echo
            print_fancy --bg "blue" --align "center" --highlight \
                "⚡  Mise à jour disponible : votre commit est plus ancien que origin/$branch_real"
            return 1
        else
            echo
            print_fancy --bg "green" --align "center" --highlight \
                "⚠️  Votre commit est plus récent que origin/$branch_real"
            return 0
        fi
    fi
    echo "################################################################################"
}


###############################################################################
# Fonction : Met à jour (forcée) du script sur la branche en cours
# ou sur une branche spécifiée via FORCE_BRANCH
# → préserve les fichiers ignorés (.gitignore)
###############################################################################
update_force_branch() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Déterminer la branche réelle
    local branch_real
    branch_real=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(détaché)")

    # Choix de la branche à utiliser
    local branch="${FORCE_BRANCH:-$branch_real}"

    # Si HEAD détaché ou branche vide → fallback sur main
    if [[ -z "$branch" || "$branch" == "(détaché)" || "$branch" == "HEAD" ]]; then
        echo "⚠️  HEAD détaché détecté → fallback automatique sur 'main'"
        branch="main"
    fi

    MSG_MAJ_UPDATE_BRANCH=$(printf "$MSG_MAJ_UPDATE_BRANCH_TEMPLATE" "$branch")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_BRANCH"

    # Liste des fichiers ignorés (d'après .gitignore)
    local ignored_files
    ignored_files=$(git ls-files --ignored --exclude-standard)

    # Sauvegarde temporaire si fichiers ignorés présents
    if [[ -n "$ignored_files" ]]; then
        echo "💾 Sauvegarde des fichiers ignorés..."
        tar czf /tmp/ignored_backup.tar.gz $ignored_files 2>/dev/null || true
    fi

    # Récupération des dernières infos
    git fetch --all --tags

    # Passage forcé sur la branche cible
    git checkout -f "$branch" || { echo "❌ Erreur lors du checkout de $branch" >&2; exit 1; }
    git reset --hard "origin/$branch"
    git clean -fd

    # Restauration éventuelle des fichiers ignorés
    if [[ -f /tmp/ignored_backup.tar.gz ]]; then
        echo "♻️  Restauration des fichiers ignorés..."
        tar xzf /tmp/ignored_backup.tar.gz -C "$SCRIPT_DIR"
        rm -f /tmp/ignored_backup.tar.gz
        echo "✅ Fichiers ignorés restaurés"
    fi

    chmod +x "$SCRIPT_DIR/main.sh"

    print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_BRANCH_SUCCESS"
    return 0
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (tag)
# → préserve les fichiers ignorés (.gitignore)
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # Déterminer la branche réelle
    local branch_real
    branch_real=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(détaché)")

    # Choix de la branche à utiliser
    local branch="${FORCE_BRANCH:-$branch_real}"

    # Si HEAD détaché ou branche vide → fallback sur main
    if [[ -z "$branch" || "$branch" == "(détaché)" || "$branch" == "HEAD" ]]; then
        echo "⚠️  HEAD détaché détecté → fallback automatique sur 'main'"
        branch="main"
    fi

    git fetch origin "$branch" --tags --quiet

    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        echo "❌  Aucun tag trouvé sur la branche $branch"
        return 1
    fi

    local head_commit head_date latest_tag_commit latest_tag_date current_tag
    head_commit=$(git rev-parse HEAD)
    head_date=$(git --no-pager show -s --format=%ci "$head_commit")
    latest_tag_commit=$(git rev-parse "$latest_tag")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit")
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

    # --- Sauvegarde des fichiers ignorés ---
    local ignored_files
    ignored_files=$(git ls-files --ignored --exclude-standard)
    if [[ -n "$ignored_files" ]]; then
        echo "💾 Sauvegarde des fichiers ignorés..."
        tar czf /tmp/ignored_backup.tar.gz $ignored_files 2>/dev/null || true
    fi

    # Checkout vers le tag
    if git -c advice.detachedHead=false checkout "$latest_tag"; then
        # Restauration des fichiers ignorés
        if [[ -f /tmp/ignored_backup.tar.gz ]]; then
            echo "♻️  Restauration des fichiers ignorés..."
            tar xzf /tmp/ignored_backup.tar.gz -C "$SCRIPT_DIR"
            rm -f /tmp/ignored_backup.tar.gz
            echo "✅ Fichiers ignorés restaurés"
        fi

        chmod +x "$SCRIPT_DIR/main.sh"
        echo "🎉  Mise à jour réussie vers $latest_tag"
        echo "ℹ️  Pour plus d’infos, utilisez rclone_homelab sans arguments pour afficher le menu."
        return 0
    else
        echo "❌  Échec lors du passage à $latest_tag"
        return 1
    fi
}