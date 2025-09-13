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
###############################################################################
fetch_git_info() {

    # La défintion des variables est rendue obligatoire à cause de set -u
    # afin de passer d'une variable à une autre.
    branch_real=""
    head_commit=""
    head_epoch=0
    remote_commit=""
    remote_epoch=0
    latest_tag=""
    latest_tag_commit=""
    latest_tag_epoch=0
    current_tag=""

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

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

}


###############################################################################
# Fonction : Affichage des informations Git issues de fetch_git_info()
###############################################################################
analyze_update_status() {
    # Déterminer le mode d'affichage
    local display_mode="${DISPLAY_MODE:-simplified}"  # verbose / simplified / none
    local result_code=0

    # Mode verbose : affichage complet
    if [[ "$display_mode" == "verbose" ]]; then
        print_fancy --fill "#" "#"
        print_fancy --align "center" --style "bold" "INFOS GIT"
        echo "" || true
        print_fancy "📌  Branche locale      : $branch_real"
        print_fancy "📌  Commit local        : $head_commit ($(date -d "@$head_epoch"))"
        [[ -n "$remote_commit" ]] && print_fancy "🕒  Commit distant      : $remote_commit ($(date -d "@$remote_epoch"))"
        [[ -n "$latest_tag" ]] && print_fancy "🏷️  Dernière release    : $latest_tag ($(date -d "@$latest_tag_epoch"))"
    fi

    # --- Analyse des commits / branches ---
    if [[ "$branch_real" == "main" ]]; then
        # --- Branche main : vérifier si on est à jour avec la dernière release ---
        if [[ -z "$latest_tag" ]]; then
            [[ "$display_mode" == "verbose" ]] && echo "" || true
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && print_fancy --theme "error" --fg "red" --bg "white" --style "bold underline" "Impossible de vérifier les mises à jour (API GitHub muette)."
            result_code=1

        elif [[ "$head_commit" == "$latest_tag_commit" ]] || git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
            [[ "$display_mode" == "verbose" ]] && echo "" || true
            [[ "$display_mode" == "verbose" ]] && \
                text=""
                text+="Version actuelle ${current_tag:-dev} >> "
                text+="${BOLD}À jour${RESET}"
                print_fancy --theme "success" --fg "blue" --align "right" "$text"
            [[ "$display_mode" == "simplified" ]] && \
                print_fancy --theme "success" --fg "blue" --align "right" "À jour."
            result_code=0
        elif (( latest_tag_epoch < head_epoch )); then
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && echo "" || true
            [[ "$display_mode" == "verbose" ]] && \
                print_fancy --theme "warning" --bg "yellow" --align "center" --style "bold" --highlight "Des nouveautés existent mais ne sont pas encore officialisées."
            [[ "$display_mode" == "verbose" ]] && \
                print_fancy --theme "follow" --bg "yellow" --align "center" --style "bold underline" --highlight "La mise à jour automatisée n'est pas proposée pour garantir la stabilité."
            [[ "$display_mode" == "verbose" ]] && \
                print_fancy --bg "yellow" --align "center" --style "italic" --highlight "Forcer la mise à jour (possible) pourrait avoir des effets indésirables."
            [[ "$display_mode" == "verbose" ]] && \
                print_fancy --bg "yellow" --align "center" --style "italic" --highlight "Vous êtes bien sur la dernière release stable : ${current_tag:-dev}"
            [[ "$display_mode" == "simplified" ]] && \
                print_fancy --theme "success" --fg "yellow" --align "right" style "underline" "Votre version est à jour..."
            # [[ "$display_mode" == "simplified" ]] && \
            #     print_fancy --theme "info" "Des commits locaux plus récents que la dernière release."
            result_code=0
        else
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && echo "" || true
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --theme "flash" --bg "blue" --align "center" --style "bold" --highlight "Nouvelle release disponible : $latest_tag ($(date -d "@$latest_tag_epoch"))"
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                text=""
                text+="Pour mettre à jour : relancer le script "
                text+="${UNDERLINE}sans arguments${RESET}"
                text+=" pour accéder au menu."
                print_fancy --theme "info" --bg "blue" --align "center" --highlight "$text"
        fi

    else
        # Branche dev ou autre
        if [[ -z "$remote_commit" ]]; then
            [[ "$display_mode" == "verbose" ]] && echo "" || true
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --theme "error" --fg "red" --bg "white" --style "bold underline" "Aucune branche distante détectée pour '$branch_real'"
            # [[ "$display_mode" == "simplified" ]] && \
            #     print_fancy --theme "info" "Pas de remote pour $branch_real"
            result_code=1

        elif [[ "$head_commit" == "$remote_commit" ]]; then
            [[ "$display_mode" == "verbose" ]] && echo "" || true
            [[ "$display_mode" == "verbose" ]] && \
                text=""
                text+="Votre branche '$branch_real' est "
                text+="${UNDERLINE}à jour${RESET}"
                text+=" avec le dépôt."
                print_fancy --theme "success" --fg "blue" --style "bold" --align "right" "$text"
            [[ "$display_mode" == "simplified" ]] && \
                print_fancy --theme "success" --fg "blue" --align "right" "À jour."
            result_code=0
        elif (( head_epoch < remote_epoch )); then
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && echo "" || true
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --theme "flash" --bg "blue" --align "center" --style "bold" --highlight "Mise à jour disponible : Des nouveautés sur le dépôt sont apparues."
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --bg "blue" --align "center" --highlight "Vous pouvez forcer la MAJ ou utiliser le menu pour mettre à jour."
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                text=""
                text+="Les modifications "
                text+="${ITALIC}(hors .gitignore)${RESET}"
                text+=" seront "
                text+="${BOLD}écrasées/perdues${RESET}"
                text+="."
                print_fancy --theme "warning" --bg "blue" --align "center" --style "underline" --highlight "$text"
            result_code=1
        else
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && echo "" || true
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --theme "warning" --bg "blue" --align "center" --style "bold" --highlight "Votre commit local est plus récent que origin/$branch_real"
            text=""
            text+="Pas de mise à jour à faire sous peine de "
            text+="${BOLD}régressions/pertes${RESET}"
            text+="."
            [[ "$display_mode" == "verbose" || "$display_mode" == "simplified" ]] && \
                print_fancy --theme "warning" --bg "blue" --align "center" --style "italic underline" --highlight "$text"
            result_code=0
        fi
    fi

    [[ "$display_mode" == "verbose" ]] && print_fancy --fill "#" "#"
    return $result_code
}


###############################################################################
# Fonction : Affichage un résumé conditionnel de analyze_update_status()
###############################################################################
git_summary() {
    [[ "${DEBUG_INFOS:-true}" == "false" ]] || return
    if [[ $1 -eq 0 ]]; then
        print_fancy --theme "success" --align "right" "Git → OK"
    else
        print_fancy --theme "warning" --align "center" "Git → Une information sur une éventuelle MAJ est disponnible."
    fi
}


###############################################################################
# Fonction : Met à jour (forcée) du script sur la branche en cours
# ou sur une branche spécifiée via FORCE_BRANCH
# → préserve les fichiers ignorés (.gitignore)
###############################################################################
update_to_latest_branch() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Déterminer la branche réelle
    # Appel obligatoire à fetch_git_info si pas déjà fait
    [[ -z "${branch_real:-}" ]] && fetch_git_info

    # Choix de la branche à utiliser
    local branch="${FORCE_BRANCH:-$branch_real}"

    # Si HEAD détaché ou branche vide → fallback sur main
    if [[ -z "$branch" || "$branch" == "(détaché)" || "$branch" == "HEAD" ]]; then
        echo "⚠️  HEAD détaché détecté → fallback automatique sur 'main'"
        branch="main"
    fi

    MSG_MAJ_UPDATE_BRANCH=$(printf "$MSG_MAJ_UPDATE_BRANCH_TEMPLATE" "$branch")
    echo
    print_fancy --align "center" --bg "green" --style "italic" --highlight "$MSG_MAJ_UPDATE_BRANCH"

    # Liste des fichiers ignorés (d'après .gitignore)
    local ignored_files
    ignored_files=$(git ls-files --ignored --other --exclude-standard)

    # Sauvegarde temporaire si fichiers ignorés présents
    if [[ -n "$ignored_files" ]]; then
        echo
        echo "💾  Prendre soin des fichiers personnalisables..."
        echo
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
        echo
        echo "♻️  ... Retour des fichiers personnalisables."
        tar xzf /tmp/ignored_backup.tar.gz -C "$SCRIPT_DIR"
        rm -f /tmp/ignored_backup.tar.gz
        echo "✅  Les fichiers personnalisables sont heureux de faire leur retour !"
        echo
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
    # Récupérer infos Git si nécessaire
    [[ -z "${branch_real:-}" ]] && fetch_git_info

    # Choix de la branche : priorité à FORCE_BRANCH
    local branch
    if [[ -n "${FORCE_BRANCH:-}" ]]; then
        branch="$FORCE_BRANCH"
    else
        branch="$branch_real"
    fi

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
    ignored_files=$(git ls-files --ignored --other --exclude-standard)
    if [[ -n "$ignored_files" ]]; then
        echo
        echo "💾  Prendre soin des fichiers personnalisables..."
        echo
        tar czf /tmp/ignored_backup.tar.gz $ignored_files 2>/dev/null || true
    fi

    # Checkout vers le tag
    if git -c advice.detachedHead=false checkout "$latest_tag"; then
        # Restauration des fichiers ignorés
        if [[ -f /tmp/ignored_backup.tar.gz ]]; then
            echo
            echo "♻️  ... Retour des fichiers personnalisables."
            tar xzf /tmp/ignored_backup.tar.gz -C "$SCRIPT_DIR"
            rm -f /tmp/ignored_backup.tar.gz
            echo "✅  Les fichiers personnalisables sont heureux de faire leur retour !"
            echo
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


###############################################################################
# Fonction : Mise à jour forcée avec possibilité de switch de branche
###############################################################################
update_forced() {
    # 1. Si FORCE_BRANCH défini → passer dessus
    if [[ -n "${FORCE_BRANCH:-}" ]]; then
        echo "🔀 Switch forcé vers la branche : $FORCE_BRANCH"
        cd "$SCRIPT_DIR" || { echo "❌ Impossible d'accéder au dossier du script"; return 1; }
        git fetch origin --quiet
        if ! git checkout -f "$FORCE_BRANCH"; then
            echo "❌ Échec du switch vers $FORCE_BRANCH"
            return 1
        fi
    fi

    # 2. Récupérer infos git
    fetch_git_info || { echo "❌ Impossible de récupérer les infos Git."; return 1; }

    # 3. Afficher résumé
    git_summary $?  

    # 4. Déterminer si mise à jour nécessaire
    local need_update=0
    if [[ "$branch_real" == "main" ]]; then
        [[ "$head_commit" != "$latest_tag_commit" ]] && ! git merge-base --is-ancestor "$latest_tag_commit" "$head_commit" && need_update=1
    else
        [[ "$head_commit" != "$remote_commit" ]] && need_update=1
    fi

    if [[ $need_update -eq 0 ]]; then
        print_fancy --theme "success" "✅ Aucune mise à jour nécessaire pour la branche '$branch_real'."
        return 0
    fi

    echo
    print_fancy --theme "info" --align "center" "⚡ Mise à jour détectée sur la branche '$branch_real'"

    # 5. Appliquer la mise à jour appropriée
    if [[ "$branch_real" == "main" ]]; then
        update_to_latest_tag
    else
        update_to_latest_branch
    fi
}