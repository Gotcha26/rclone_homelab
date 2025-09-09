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
# Fonction : Met à jour le script vers la dernière release (dernier tag
# présent sur la branche courante définie dans la config)
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # Déterminer la branche active
    local branch="${FORCE_BRANCH:-$BRANCH}"

    echo
    echo "⚡ Vérification de la dernière release sur la branche '$branch'..."

    # Récupérer les infos distantes et tags
    git fetch origin "$branch" --tags --quiet

    # Dernier tag disponible sur la branche
    local latest_tag
    latest_tag=$(git tag --merged "origin/$branch" | sort -V | tail -n1)

    if [[ -z "$latest_tag" ]]; then
        echo "❌ Aucun tag trouvé sur la branche $branch"
        return 1
    fi

    # Tag actuel (si HEAD est exactement sur un tag)
    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")

    if [[ -z "$current_tag" ]]; then
        echo "ℹ️ Vous n’êtes pas sur un tag (probablement en avance sur la branche)."
        echo "👉 Dernière release stable publiée : $latest_tag"
        echo "✅ Aucune action effectuée (vous restez sur votre commit actuel)."
        return 0
    fi

    if [[ "$current_tag" == "$latest_tag" ]]; then
        echo "✅ Déjà sur la dernière release : $current_tag"
        return 0
    fi

    echo "⚡ Nouvelle release détectée : $latest_tag (actuellement $current_tag)"

    # Checkout sécurisé du tag
    if git -c advice.detachedHead=false checkout "$latest_tag"; then
        chmod +x "$SCRIPT_DIR/main.sh"
        echo "🎉 Mise à jour réussie vers $latest_tag"
        return 0
    else
        echo "❌ Échec lors du passage à $latest_tag"
        return 1
    fi
}


###############################################################################
# Fonction : Vérifie s'il existe une nouvelle release ou branche
# NE MODIFIE PAS le dépôt
###############################################################################
update_check() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; return 1; }

    # Récupérer les infos distantes
    git fetch origin "$BRANCH" --tags --quiet

    # Dernier tag disponible sur la branche
    local latest_tag
    latest_tag=$(git tag --merged "origin/$BRANCH" | sort -V | tail -n1)

    # Tag actuel (si on est sur un tag exact)
    local current_tag
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "dev")

    if [[ -z "$latest_tag" ]]; then
        print_fancy --fg "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
        return 1
    fi

    if [[ "$current_tag" != "$latest_tag" ]]; then
        MSG_MAJ_UPDATE1=$(printf "$MSG_MAJ_UPDATE_TEMPLATE" "$latest_tag" "$current_tag")
        echo
        print_fancy --align "left" --fg "green" --style "italic" "$MSG_MAJ_UPDATE1"
        print_fancy --align "right" --fg "green" --style "italic" "$MSG_MAJ_UPDATE2"
    fi
}