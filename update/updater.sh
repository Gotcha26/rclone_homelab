# === Initialisation des variables globales (protège set -u) ===
# Sinon les placer dans fetch_git_info()
: "${branch_real:=}"
: "${head_commit:=}"
: "${head_epoch:=0}"
: "${remote_commit:=}"
: "${remote_epoch:=0}"
: "${latest_tag:=}"
: "${latest_tag_commit:=}"
: "${latest_tag_epoch:=0}"
: "${current_tag:=}"
: "${GIT_OFFLINE:=false}"
: "${LOCAL_VERSION:=}"


###############################################################################
# Fonction principale : update_check
# → Vérifie si une mise à jour est disponible et affiche le statut
###############################################################################
update_check() {
    fetch_git_info || return 1
    analyze_update_status
    return 0
}


###############################################################################
# Fonction : Juste pour lire le contenu de .version
###############################################################################
get_local_version() {
    local version_file="$DIR_VERSION_FILE"
    if [[ -f "$version_file" ]]; then
        cat "$version_file"
    else
        echo ""
    fi
}


###############################################################################
# Fonction : Juste pour écrire le tag dans le fichier .version
###############################################################################
write_version_file() {
    local branch="${1:-main}"  # main par défaut
    local json latest_tag latest_date commit date_commit owner repo api_commits_url

    if [[ -z "$GITHUB_API_URL" ]]; then
        echo "⚠️  GITHUB_API_URL non défini !" >&2
        echo "unknown" > "$DIR_VERSION_FILE"
        return 1
    fi

    # Extraire owner et repo depuis GITHUB_API_URL
    # Exemple : https://api.github.com/repos/Gotcha26/rclone_homelab/releases/latest
    if [[ "$GITHUB_API_URL" =~ /repos/([^/]+)/([^/]+)/ ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        echo "❌ Impossible de parser GITHUB_API_URL" >&2
        echo "unknown" > "$DIR_VERSION_FILE"
        return 1
    fi

    if [[ "$branch" == "main" ]]; then
        # Récupérer le dernier tag (release) depuis l'API
        json=$(curl -s "$GITHUB_API_URL" 2>/dev/null)
        latest_tag=$(echo "$json" | jq -r '.tag_name // empty')
        if [[ -z "$latest_tag" ]]; then
            echo "❌ Impossible de récupérer le dernier tag depuis GitHub" >&2
            echo "unknown" > "$DIR_VERSION_FILE"
            return 1
        fi
        echo "$latest_tag" > "$DIR_VERSION_FILE"
        return 0
    fi

    # Pour dev ou autre branche → HEAD distant via GitHub API
    api_commits_url="https://api.github.com/repos/$owner/$repo/commits/$branch"
    json=$(curl -s "$api_commits_url" 2>/dev/null)
    if [[ -z "$json" ]]; then
        echo "❌ Impossible de récupérer les infos de commit depuis GitHub pour la branche $branch" >&2
        echo "$branch - unknown - unknown" > "$DIR_VERSION_FILE"
        return 1
    fi

    commit=$(echo "$json" | jq -r '.sha // empty')
    date_commit=$(echo "$json" | jq -r '.commit.committer.date // empty' | cut -d'T' -f1)

    commit="${commit:0:7}"                # SHA court
    commit="${commit:-unknown}"
    date_commit="${date_commit:-date_inconnue}"

    echo "$branch - $commit - $date_commit" > "$DIR_VERSION_FILE"
}


###############################################################################
# Fonction : Récupère le dernier tag disponible sur le dépôt distant
# → utilisable aussi bien en mode Git que standalone
###############################################################################
get_remote_latest_tag() {
    if [[ -z "${REMOTE_VERSION_URL:-}" ]]; then
        echo ""
        return
    fi
    curl -s "$REMOTE_VERSION_URL" 2>/dev/null || echo ""
}


###############################################################################
# Fonction : collecte les infos Git / remote / tags
# - N'affiche quasiment rien (sauf erreur cd). Met en place des flags/variables.
# - Retourne 1 seulement si cd échoue (impossible d'accéder au répertoire).
###############################################################################
fetch_git_info() {
    # reset / defaults
    HAS_GIT=false
    GIT_OFFLINE=false
    LOCAL_VERSION=""
    head_commit=""
    head_epoch=0
    branch_real=""
    remote_commit=""
    remote_epoch=0
    latest_tag=""
    latest_tag_commit=""
    latest_tag_epoch=0
    current_tag=""

    cd "$SCRIPT_DIR" || { echo "Erreur : impossible d'accéder au répertoire du script"; return 1; }

    if [[ -d ".git" ]]; then
        HAS_GIT=true
        
        # --- Git normal ---
        # --- Récupération des dernières infos du remote avec fallback ---
        # try fetch (non fatal ici : on signale offline mais on continue à remplir ce qu'on peut)
        if ! git fetch origin --tags --prune --quiet; then
            GIT_OFFLINE=true
        fi

        # --- Commit et date HEAD local ---
        head_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
        head_epoch=$(git show -s --format=%ct "$head_commit" 2>/dev/null || echo 0)

        # --- Détection de la branche locale réelle ---
        branch_real=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(détaché)")

        # --- Commit et date HEAD distant ---
        if [[ "$branch_real" != "(détaché)" && "$GIT_OFFLINE" == false ]]; then
            remote_commit=$(git rev-parse "origin/$branch_real" 2>/dev/null || echo "")
            remote_epoch=$(git show -s --format=%ct "$remote_commit" 2>/dev/null || echo 0)
        fi

        # --- Dernier tag disponible (uniquement pour main) ---
        if [[ "$branch_real" == "main" && "$GIT_OFFLINE" == false ]]; then
            latest_tag=$(git tag --merged "origin/main" 2>/dev/null | sort -V | tail -n1 || echo "")
        fi

        if [[ -n "$latest_tag" ]]; then
            latest_tag_commit=$(git rev-parse "$latest_tag" 2>/dev/null || echo "")
            latest_tag_epoch=$(git show -s --format=%ct "$latest_tag_commit" 2>/dev/null || echo 0)
        fi

        current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
    else
        # pas de repo Git : on reste en "local standalone"
        HAS_GIT=false
        LOCAL_VERSION=$(get_local_version)
        branch_real="(local-standalone-version)"
        # optionnel : tenter de récupérer le dernier tag distant via API (fallback non bloquant)
        latest_tag=$(get_remote_latest_tag 2>/dev/null || echo "")
    fi

    return 0    # Rien de bloquant
}


##############################################################################
# Fonction : responsable de tout l'affichage / diagnostic
# - S'appuie sur les variables mises par fetch_git_info()
# - Retourne 0/1 selon la logique que tu veux (ici 0 = OK / 1 = échec de vérification)
##############################################################################
analyze_update_status() {
    local result_code=0

    # --- Mode sans Git : on affiche la version locale et (éventuellement) annonce d'une release ---
    if [[ "$branch_real" == "(local-standalone-version)" ]]; then
        print_fancy --theme "info" --fg "blue" --align "center" \
            "Version locale installée : ${LOCAL_VERSION:-inconnue}"

        if [[ -n "$latest_tag" && "$LOCAL_VERSION" != "$latest_tag" ]]; then
            print_fancy --theme "flash" --bg "blue" --align "center" --style "bold" \
                "Nouvelle version disponible : $latest_tag"
        else
            print_fancy --theme "ok" --align "right" "À jour."
        fi
        return 0
    fi

    # --- Si on a Git mais fetch a échoué (offline) ---
    if [[ "$HAS_GIT" == true && "$GIT_OFFLINE" == true ]]; then
        print_fancy --theme "warning" --fg "yellow" --align "center" \
            "Impossible de contacter le remote Git. Mode offline activé. Informations incomplètes."
        # On peut afficher des infos locales partielles :
        print_fancy "📌  Branche locale : $branch_real"
        print_fancy "📌  Commit local   : ${head_commit:-inconnu}"
        result_code=1   # on considère que la vérification n'est pas complète
        return $result_code
    fi

    # --- Mode Git normal (fetch ok) ---
    # affichages DEBUG si demandé
    if [[ "${DEBUG_INFOS:-false}" == true ]]; then
        print_fancy --align "center" --fill "#" "#"
        print_fancy --align "center" --style "bold" "INFOS GIT"
        echo ""
        print_fancy "📌  Branche locale   : $branch_real"
        print_fancy "📌  Commit local     : $head_commit"
        [[ -n "$remote_commit" ]] && print_fancy "🕒  Commit distant   : $remote_commit"
        [[ -n "$latest_tag" ]] && print_fancy "🏷️  Dernière release : $latest_tag"
    fi

    # --- Analyse des branches / tags ---
    if [[ "$branch_real" == "main" ]]; then
        if [[ -z "$latest_tag" ]]; then
            print_fancy --theme "error" --fg "red" --bg "white" --style "bold underline" \
                "Impossible de vérifier les mises à jour (API GitHub muette ou tag manquant)."
            result_code=1
        elif [[ "$head_commit" == "$latest_tag_commit" ]] || git merge-base --is-ancestor "$latest_tag_commit" "$head_commit" 2>/dev/null; then
            print_fancy --theme "ok" --fg "blue" --align "right" "À jour."
            result_code=0
        elif (( latest_tag_epoch < head_epoch )); then
            print_fancy --theme "ok" --fg "yellow" --align "right" --style "underline" \
                "Votre version est à jour (commit plus récent que la dernière release)."
            result_code=0
        else
            print_fancy --theme "flash" --bg "blue" --align "center" --style "bold" --highlight \
                "Nouvelle release disponible : $latest_tag ($(date -d "@$latest_tag_epoch" 2>/dev/null || echo "date inconnue"))"
            print_fancy --theme "info" --bg "blue" --align "center" --highlight \
                "Pour mettre à jour : relancer le script sans arguments pour accéder au menu."
            result_code=0
        fi
    else
        # branches non-main
        if [[ -z "$remote_commit" ]]; then
            print_fancy --theme "error" --fg "red" --bg "white" --style "bold underline" \
                "Aucune branche distante détectée pour '$branch_real' (mode offline ou fetch échoué)."
            result_code=1
        elif [[ "$head_commit" == "$remote_commit" ]]; then
            print_fancy --theme "ok" --fg "blue" --align "right" "À jour."
            result_code=0
        elif (( head_epoch < remote_epoch )); then
            print_fancy --theme "flash" --bg "blue" --align "center" --style "bold" --highlight \
                "Mise à jour disponible : des commits distants existent."
            print_fancy --bg "blue" --align "center" --highlight \
                "Vous pouvez forcer la MAJ ou utiliser le menu pour mettre à jour."
            print_fancy --theme "warning" --bg "blue" --align "center" --highlight \
                "Les modifications locales (hors .gitignore) seront écrasées."
            result_code=1
        else
            print_fancy --theme "warning" --bg "blue" --align "center" --highlight \
                "Votre commit local est plus récent que origin/$branch_real — attention aux régressions."
            result_code=0
        fi
    fi

    [[ "${DEBUG_INFOS:-false}" == true ]] && print_fancy --align "center" --fill "#" "#"
    return $result_code
}


###############################################################################
# Fonction : Affichage un résumé conditionnel de analyze_update_status()
# → Protège contre mode offline et set -u
###############################################################################
git_summary() {
    # Si DEBUG_INFOS=false, on ne fait rien
    [[ "${DEBUG_INFOS:-false}" == "true" ]] || return

    # Argument : code retour d'analyze_update_status()
    local code="${1:-0}"

    # Cas sans Git
    if [[ "${branch_real:-}" == "(local-standalone-version)" ]]; then
        if [[ -n "$latest_tag" && "$LOCAL_VERSION" != "$latest_tag" ]]; then
            print_fancy --theme "warning" --align "center" \
                "Standalone → mise à jour disponible ($latest_tag)"
        else
            print_fancy --theme "success" --align "center" \
                "Standalone → À jour"
        fi
        return
    fi

    # Cas Git normal
    if [[ "$code" -eq 0 ]]; then
        print_fancy --theme "success" --align "right" \
            "Git → OK"
    else
        print_fancy --theme "warning" --align "center" \
            "Git → Une information sur une éventuelle MAJ est disponible."
    fi
}


###############################################################################
# Fonction : Met à jour (forcée) du script sur la branche en cours
# ou sur une branche spécifiée via FORCE_BRANCH
# → préserve les fichiers ignorés (.gitignore)
###############################################################################
update_to_latest_branch() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # --- Cas pas de Git mais version locale ---
    if [[ "$branch_real" == "(local-standalone-version)" ]]; then
        print_fancy --theme "info" \
            "⚠️  Pas de dépôt Git : mise à jour automatique impossible."
        if [[ -n "$latest_tag" && "$LOCAL_VERSION" != "$latest_tag" ]]; then
            print_fancy --theme "flash" "Nouvelle version disponible : $latest_tag (locale : $LOCAL_VERSION)"
        else
            print_fancy --theme "ok" "Vous êtes à jour."
        fi
        return 0
    fi

    # --- Git normal ---
    # Déterminer la branche réelle
    # Appel obligatoire à fetch_git_info si pas déjà fait
    [[ -z "${branch_real:-}" ]] && fetch_git_info

    # Choix de la branche à utiliser
    local branch="${FORCE_BRANCH:-$branch_real}"

    # Si HEAD détaché ou branche vide → fallback sur main
    if [[ -z "$branch" || "$branch" == "(détaché)" || "$branch" == "HEAD" ]]; then
        print_fancy --theme "warning" \
            "HEAD détaché détecté → fallback automatique sur 'main'"
        branch="main"
    fi

    # Alerte spéciale si mise à jour sur main
    if [[ "$branch" == "main" ]]; then
        print_fancy --theme "warning" --bg "yellow" --align "center" --style "bold underline" \
            "Mise à jour forcée sur HEAD de main ! Les commits locaux peuvent être écrasés."
    fi

    echo
    print_fancy --align "center" --bg "green" --style "italic" --highlight \
        "⚡  Mécanisme automatique de mise à jour forcée sur la branche : $branch. ⚡ "

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
    git checkout -f "$branch" || {
        print_fancy --theme "error" \
            "Erreur lors du checkout de $branch" >&2
        exit 1
        }
    git reset --hard "origin/$branch"
    git clean -fd

    # Restauration éventuelle des fichiers ignorés
    if [[ -f /tmp/ignored_backup.tar.gz ]]; then
        echo
        echo "♻️  ... Retour des fichiers personnalisables."
        tar xzf /tmp/ignored_backup.tar.gz -C "$SCRIPT_DIR"
        rm -f /tmp/ignored_backup.tar.gz
        print_fancy --theme ok --style itlaic "Les fichiers personnalisables sont heureux de faire leur retour !"
    fi

    update_local_configs

    make_scripts_executable

    echo -e "🎉  Mise à jour réussie depuis la branche : ${UNDERLINE}$branch${RESET}"

    # Mise à jour réussie → écrire la version appropriée
    write_version_file "$branch"
    
    echo
    print_fancy --align "center" --bg "green" --style "italic" --highlight \
        "Script mis à jour avec succès."

    return 0
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (tag)
# → préserve les fichiers ignorés (.gitignore)
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # --- Cas pas de Git mais version locale ---
    if [[ "$branch_real" == "(local-standalone-version)" ]]; then
        print_fancy --theme "info" "⚠️  Pas de dépôt Git : mise à jour vers tag impossible."
        if [[ -n "$latest_tag" && "$LOCAL_VERSION" != "$latest_tag" ]]; then
            print_fancy --theme "flash" "Nouvelle version détectée : $latest_tag (locale : $LOCAL_VERSION)"
        else
            print_fancy --theme "ok" "Vous êtes à jour."
        fi
        return 0
    fi

    # --- Git normal ---
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
        print_fancy --theme "warning" \
            "HEAD détaché détecté → fallback automatique sur 'main'"
        branch="main"
    fi

    git fetch origin "$branch" --tags --quiet

    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        print_fancy --theme "error" \
            "Aucun tag trouvé sur la branche $branch"
        return 1
    fi

    local head_commit head_date latest_tag_commit latest_tag_date current_tag
    head_commit=$(git rev-parse HEAD)
    head_date=$(git --no-pager show -s --format=%ci "$head_commit")
    latest_tag_commit=$(git rev-parse "$latest_tag")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit")
    current_tag=$(git --no-pager describe --tags --exact-match 2>/dev/null || echo "")

    # Branche locale
    text=""
    text+=$(print_fancy --raw "📌  Branche locale   : ")
    text+=$(print_fancy --fg "red" --style "bold" --raw "$branch")
    print_fancy "$text"
    echo ""

    # Commit local
    print_fancy "📌  Commit local     : $head_commit"
    print_fancy --align "right" --style "italic" \
        "($(date -d "@$head_date" 2>/dev/null || echo "date inconnue"))"

    # Dernière release
    if [[ -n "$latest_tag" ]]; then
        print_fancy "🏷️  Dernière release : $latest_tag"
        print_fancy --align "right" --style "italic" \
            "($(date -d "@$latest_tag_date" 2>/dev/null || echo "date inconnue"))"
    fi

    if [[ "$head_commit" == "$latest_tag_commit" ]]; then
        print_fancy --theme "ok" \
            "Déjà sur la dernière release : $latest_tag"
        return 0
    fi

    if git merge-base --is-ancestor "$latest_tag_commit" "$head_commit"; then
        print_fancy --theme "warning" \
            "Vous êtes en avance sur la dernière release : ${current_tag:-dev}"
        echo "👉  Pas de mise à jour effectuée"
        return 0
    fi

    echo
    print_fancy --align "center" --bg "green" --style "italic" --highlight \
        "⚡  Mécanisme automatique de mise à jour vers la release : $latest_tag ⚡ "

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
            print_fancy --theme ok --style itlaic "Les fichiers personnalisables sont heureux de faire leur retour !"
        fi

        update_local_configs

        make_scripts_executable

        echo -e "🎉  Mise à jour réussie depuis le tag : ${UNDERLINE}$latest_tag${RESET}"

        # Mise à jour réussie → écrire la version
        if [[ -n "$latest_tag" ]]; then
            write_version_file "$latest_tag"
        else
            write_version_file "$branch_real"
        fi

        echo
    print_fancy --align "center" --bg "green" --style "italic" --highlight \
        "Script mis à jour avec succès."

        return 0

    else
        print_fancy --theme "error" \
            "Échec lors du passage à $latest_tag"
        return 1
    fi
}


###############################################################################
# Fonction : Mise à jour forcée avec possibilité de switch de branche
# → Utilise GIT_OFFLINE pour éviter les erreurs bloquantes
###############################################################################
update_forced() {
    cd "$SCRIPT_DIR" || { print_fancy --theme "error" "Impossible d'accéder au dossier du script"; return 1; }

    # === Cas pas de Git mais fichier .version ===
    if [[ "$branch_real" == "(local-standalone-version)" ]]; then
        print_fancy --theme "info" \
            "⚠️  Installation locale détectée, version : ${LOCAL_VERSION:-inconnue}"

        if [[ -n "$latest_tag" ]]; then
            print_fancy --theme "info" "Version distante disponible : $latest_tag"
            if [[ "$LOCAL_VERSION" != "$latest_tag" ]]; then
                print_fancy --theme "flash" \
                    "Nouvelle version détectée ! Vous pouvez remplacer votre installation locale."
                # ici, tu pourrais appeler un script de mise à jour local si nécessaire
            else
                print_fancy --theme "ok" "Vous êtes à jour."
            fi
        fi
        return 0
    fi

    # --- 1. Si FORCE_BRANCH défini → switch ---
    if [[ -n "${FORCE_BRANCH:-}" ]]; then
        echo "🔀 Switch forcé vers la branche : $FORCE_BRANCH"
        cd "$SCRIPT_DIR" || {
            print_fancy --theme "error" \
                "Impossible d'accéder au dossier du script"; return 1;
        }
        if ! git fetch origin --quiet; then
            print_fancy --theme "warning" --fg "yellow" \
            "Impossible de contacter GitHub pour le fetch. Mode offline activé."
            GIT_OFFLINE=true
        fi
        if ! git checkout -f "$FORCE_BRANCH"; then
            print_fancy --theme "error" \
                "Échec du switch vers $FORCE_BRANCH"
            return 1
        fi
    fi

    # --- 2. Récupérer infos Git ---
    fetch_git_info || {
        print_fancy --theme "error" \
            "Impossible de récupérer les infos Git."; return 1;
    }

    # --- 3. Afficher résumé ---
    git_summary $?

    # --- 4. Déterminer si mise à jour nécessaire ---
    local need_update=0
    if [[ "$branch_real" == "main" ]]; then
        if [[ "$GIT_OFFLINE" == true ]]; then
            print_fancy --theme "warning" --fg "yellow" \
                "Mode offline : impossible de vérifier les dernières releases."
            need_update=0
        else
            [[ "$head_commit" != "$latest_tag_commit" ]] && ! git merge-base --is-ancestor "$latest_tag_commit" "$head_commit" && need_update=1
        fi
    else
        [[ "$head_commit" != "$remote_commit" ]] && need_update=1
    fi

    if [[ $need_update -eq 0 ]]; then
        print_fancy --theme "success" \
            "✅ Aucune mise à jour nécessaire pour la branche '$branch_real'."
        return 0
    fi

    echo
    print_fancy --theme "info" --align "center" \
        "⚡ Mise à jour détectée sur la branche '$branch_real'"

    # --- 5. Appliquer la mise à jour appropriée ---
    if [[ "$branch_real" == "main" && "${FORCE_UPDATE:-false}" == "true" ]]; then
        echo
        print_fancy --theme "warning" --bg "yellow" --align "center" --style "bold underline" \
            "Attention : vous forcez la mise à jour sur HEAD de la branche 'main'."
        echo
        read -rp "Confirmez-vous la mise à jour sur HEAD de main ? (y/N) : " user_confirm
        case "$user_confirm" in
            y|Y|yes|YES)
                echo "🔄 Mise à jour en cours..."
                update_to_latest_branch  # HEAD de main
                ;;
            *)
                print_fancy --theme "error" \
                    "Mise à jour annulée par l'utilisateur."
                return 1
                ;;
        esac
    elif [[ "$branch_real" == "main" ]]; then
        if [[ "$GIT_OFFLINE" == true ]]; then
            print_fancy --theme "warning" --fg "yellow" \
                "Mode offline : impossible de mettre à jour vers le dernier tag."
            return 1
        fi
        update_to_latest_tag     # Comportement classique
    else
        update_to_latest_branch
    fi
}