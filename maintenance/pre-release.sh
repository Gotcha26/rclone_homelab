#!/usr/bin/env bash
#
# pre-release.sh
#
# Script interactif pour préparer le dépôt Git avant publication d'une release.
#
# 🔹  Permet de synchroniser la branche de travail (ex: 'dev') avec 'main'
#     sans importer tout l'historique intermédiaire :
#        → crée un seul commit de synchronisation sur 'main'
#        → aligne ensuite la branche de travail pour éviter les divergences
# 🔹  Nettoie les branches locales déjà fusionnées dans 'main'
# 🔹  Propose la suppression des tags locaux obsolètes
# 🔹  Synchronise avec le dépôt distant et supprime les références périmées
# 🔹  Expire le reflog et compacte agressivement l'historique
# 🔹  Affiche la taille du dépôt avant et après chaque étape
#
# 🧭  Usage typique :
#    1. Se placer sur la branche de travail (ex: 'dev')
#    2. Lancer ce script avant une release
#    3. Confirmer la synchronisation de 'main' avec l’état actuel de la branche
#    4. Pousser le résultat : git push origin main --tags
#
# ⚠️  Ce script n’écrase pas l’historique de 'main' ni ne force de push.
# ⚠️  Ne pas l’automatiser dans un cron : les opérations interactives sont voulues.
#
# Auteur : Julien Moreau
# Version : 2.1
#
# ---------------------------------------------------------------

set -euo pipefail

export HOME=/root
export SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-""}
export DEBUG_MODE=${DEBUG_MODE:-false}

if [[ "$DEBUG_MODE" == "true" ]]; then
    echo "🔧 [DEBUG] HOME=$HOME"
    echo "🔧 [DEBUG] SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    ls -l "$HOME/.ssh/"
fi

# --- Se replacer à la racine du dépôt ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$REPO_ROOT" ]]; then
    echo "❌ Impossible de trouver la racine du dépôt Git depuis : $SCRIPT_DIR"
    exit 1
fi

pushd "$REPO_ROOT" >/dev/null

echo
echo "============================================================"
echo "🚀  Préparation du dépôt Git pour publication"
echo "============================================================"
echo

# --- Vérification du remote et configuration SSH ---
remote_url="$(git remote get-url origin 2>/dev/null || true)"
skip_push=false

if [[ -z "$remote_url" ]]; then
    echo "⚠️  Aucun remote 'origin' détecté. Les opérations distantes seront ignorées."
    skip_push=true
else
    echo "🌐  Remote actuel : $remote_url"

    # Si remote HTTPS, conversion automatique en SSH
    if [[ "$remote_url" =~ ^https://github\.com ]]; then
        echo "⚙️  Conversion du remote GitHub HTTPS → SSH..."
        ssh_url="git@github.com:Gotcha26/rclone_homelab.git"
        git remote set-url origin "$ssh_url"
        remote_url="$ssh_url"
        echo "✅  Remote mis à jour : $remote_url"
    fi

    echo
    echo "🔍  Vérification des clés SSH locales..."
    ssh_key=""
    for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
        if [[ -f "$key" ]]; then
            ssh_key="$key"
            break
        fi
    done

    if [[ -z "$ssh_key" ]]; then
        echo "❌  Aucune clé SSH trouvée dans ~/.ssh/"
        echo "   → Créez-en une avec : ssh-keygen -t ed25519 -C 'votre_email_github'"
        echo "   Puis ajoutez la clé publique sur GitHub : https://github.com/settings/keys"
        echo "⏹️  Opération annulée."
        exit 1
    fi

    echo "✅  Clé détectée : $ssh_key"

    if [[ ! -f "${ssh_key}.pub" ]]; then
        echo "⚠️  Clé publique absente (${ssh_key}.pub)."
        echo "   Impossible de vérifier votre identité auprès de GitHub."
        echo "⏹️  Opération annulée."
        exit 1
    fi

    # Test de la connexion SSH réelle
    echo "🔐  Test de connexion SSH à GitHub..."
    ssh -i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=no -T git@github.com >/tmp/ssh_test.log 2>&1 || true

    if grep -q "successfully authenticated" /tmp/ssh_test.log; then
        echo "✅  Connexion SSH à GitHub opérationnelle."
    else
        echo "❌  Échec d’authentification SSH."
        echo "   Vérifiez votre clé publique sur GitHub et réessayez : ssh -i $ssh_key -T git@github.com"
        echo "---- Détails ----"
        cat /tmp/ssh_test.log
        echo "-----------------"
        exit 1
    fi
fi

# --- Debug info pour les variables Git et taille du dépôt ---
get_size_kb() { du -sk .git | awk '{print $1}'; }
get_size_human() { du -sh .git | awk '{print $1}'; }

# --- Fonctions utilitaires ---
confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local answer
    echo
    read -rp "$prompt (Y/n/q) : " answer
    echo
    answer="${answer,,}"  # minuscule

    # valeur par défaut
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi

    case "$answer" in
        q) echo; echo "🚪 Sortie demandée. Abandon du script."; echo; exit 0 ;;
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        *) echo "❓ Réponse non reconnue. Utilisez y/n/q."; confirm "$prompt" "$default" ;;
    esac
}

# --- Fonction d'explication du stockage Git ---
explain_git_storage() {
    echo
    echo "📊  Interprétation des statistiques Git :"
    echo "------------------------------------------"

    local count size in_pack packs size_pack prune garbage size_garbage
    count=$(git count-objects -vH | awk '/^count:/ {print $2}')
    size=$(git count-objects -vH | awk '/^size:/ {print $2, $3}')
    in_pack=$(git count-objects -vH | awk '/^in-pack:/ {print $2}')
    packs=$(git count-objects -vH | awk '/^packs:/ {print $2}')
    size_pack=$(git count-objects -vH | awk '/^size-pack:/ {print $2, $3}')
    prune=$(git count-objects -vH | awk '/^prune-packable:/ {print $2}')
    garbage=$(git count-objects -vH | awk '/^garbage:/ {print $2}')
    size_garbage=$(git count-objects -vH | awk '/^size-garbage:/ {print $2, $3}')

    cat <<EOF
- 🟢  Ojets non empaquetés (encore individuels dans .git/objects).  → count: $count
- 📦  Taille totale de ces objets bruts.                            → size: $size
- 📚  Objets déjà compressés dans les fichiers pack.                → in-pack: $in_pack
- 🧩  Nombre de fichiers pack utilisés.                             → packs: $packs
- 💾  Taille totale des fichiers pack.                              → size-pack: $size_pack
- 🧹  Objets éligibles à la suppression (souvent 0).                → prune-packable: $prune
- 🚮  Données inutiles ou corrompues.                               → garbage: $garbage
- ⚙️  Taille de ces données perdues.                                → size-garbage: $size_garbage

💡  En résumé : Git stocke la majorité de ses données sous forme d’objets
   compressés dans un ou plusieurs fichiers *.pack*, ce qui explique
   la différence entre la taille brute et celle finale du dépôt.
------------------------------------------
EOF
}

# --- Début du rapport ---
echo -e "\n============================================================"
echo "📂  Dépôt : $PWD"
echo
echo "=== Constat état initial ==="
git status --short
git branch -vv
git tag -l
git count-objects -vH
explain_git_storage

before_total=$(get_size_kb)
echo "Taille .git avant nettoyage : $(get_size_human)"
echo
echo "=== Fin du constat ==="

# --- Branche principale ---
main_branch="main"

if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    echo
    echo "⚠️  En local (ici) la branche '$main_branch' n'existe pas."
    echo "   Tentative de récupération depuis 'origin/$main_branch'..."
    git fetch origin "$main_branch" >/dev/null 2>&1 || true

    if git show-ref --verify --quiet "refs/remotes/origin/$main_branch"; then
        git branch "$main_branch" "origin/$main_branch"
        echo "✅  Branche '$main_branch' recréée localement à partir du remote."
    else
        echo "❌  Impossible de trouver '$main_branch' ni en local ni sur le remote."
        exit 1
    fi
fi

# --- Synchronisation propre de main avec la branche de travail ---
current_branch=$(git symbolic-ref --quiet --short HEAD || echo "detached")

if [[ "$current_branch" != "$main_branch" ]]; then
    echo
    echo "ℹ️  Vous êtes sur la branche '$current_branch'."

    # Vérifier si des modifications locales bloquent le checkout
    if ! git diff-index --quiet HEAD --; then
        echo
        echo "⚠️  Des modifications locales bloqueraient le checkout vers '$main_branch' :"
        git diff --name-only
        echo
        echo "💡  Options pour continuer :"
        echo "   1️⃣  Ignorer les changements de permissions dans ce dépôt (core.fileMode=false)"
        echo "   2️⃣  Stasher temporairement les modifications et les récupérer après"
        echo "   3️⃣  Annuler le checkout (sortie du script)"
        echo
        read -rp "Choisissez une option [1-3] : " opt
        echo
        case "$opt" in
            1)
                git config core.fileMode false
                echo "✅  Git va désormais ignorer les différences de mode. Vous pouvez continuer."
                ;;
            2)
                git stash push -u -m "pre-release temporaire"
                echo "✅  Modifications stashed temporairement."
                ;;
            *)
                echo "🚪  Sortie demandée."
                exit 0
                ;;
        esac
    fi

    if confirm "Souhaitez-vous synchroniser LOCALEMENT '$main_branch' avec l'état actuel de '$current_branch' (commit unique) ?"; then
        echo
        echo "🔀  Synchronisation : '$main_branch' va devenir une copie exacte de '$current_branch'..."

        # 1️⃣ Se placer sur main
        git checkout "$main_branch"

        # 2️⃣ Supprimer tout le contenu actuel
        git rm -rf . >/dev/null 2>&1 || true
        git clean -fd >/dev/null 2>&1 || true

        # 3️⃣ Copier le contenu de dev
        git checkout "$current_branch" -- .

        # 4️⃣ Commit unique
        git commit -m "Pré-release : main alignée avec $current_branch"

        echo "✅  '$main_branch' est désormais une copie de '$current_branch'."

        # Récupérer les modifications stashed si option 2
        if git stash list | grep -q "pre-release temporaire"; then
            git stash pop
            echo "✅  Modifications locales restaurées depuis le stash."
        fi
    else
        echo "ℹ️  Synchronisation ignorée. Le nettoyage se fera sur '$main_branch'."
        git checkout "$main_branch"
    fi
else
    echo "ℹ️  Vous êtes déjà sur '$main_branch'. Pas de synchronisation nécessaire."
fi

# --- Supprimer les branches locales fusionnées dans main (sauf la branche courante) ---
echo -e "\n🧹  Nettoyage des branches locales fusionnées dans '$main_branch'..."
current_branch=$(git symbolic-ref --quiet --short HEAD || echo "detached")

for branch in $(git branch --format='%(refname:short)'); do
    # Ne pas toucher à main ni à la branche courante
    if [[ "$branch" != "$main_branch" && "$branch" != "$current_branch" ]]; then
        merge_base=$(git merge-base "$main_branch" "$branch")
        branch_head=$(git rev-parse "$branch")
        if [[ "$merge_base" == "$branch_head" ]]; then
            echo "   Suppression de la branche locale fusionnée : $branch"
            git branch -D "$branch"
        fi
    fi
done
after_branches=$(get_size_kb)
echo "💡 Gain après nettoyage branches : $((before_total - after_branches)) KB ($(get_size_human))"

# --- Supprimer certains tags (& branches) locaux obsolètes (optionnel) ---
echo -e "\n🧹  Gestion des tags locaux obsolètes..."
git tag -l
echo
if confirm "Voulez-vous supprimer certains tags locaux ?"; then
    echo
    read -rp "Liste des tags à supprimer (séparés par espaces, ou Entrée pour annuler) : " tags_to_delete
    echo
    [[ "$tags_to_delete" == "q" ]] && { echo; echo "🚪 Sortie demandée. Abandon du script."; echo; exit 0; }
    echo
    for tag in $tags_to_delete; do
        if git rev-parse "$tag" >/dev/null 2>&1; then
            git tag -d "$tag"
            echo "   Tag supprimé : $tag"
        else
            echo "   ⚠️  Tag non trouvé : $tag"
        fi
    done
fi
after_tags=$(get_size_kb)
echo "💡  Gain après suppression tags : $((after_branches - after_tags)) KB ($(get_size_human))"

# --- Synchronisation avec le remote ---
echo -e "\n🌐  Synchronisation avec le remote..."
git fetch --prune --all --tags
echo "✅  Synchronisation terminée."

# --- Expiration du reflog ---
echo -e "\n🧹  Expiration du reflog..."
git reflog expire --expire=now --all

# --- Nettoyage et compactage agressif ---
echo -e "\n🧹  Nettoyage et compactage agressif du dépôt..."
git gc --prune=now --aggressive
after_gc=$(get_size_kb)
echo "💡  Gain après compactage : $((after_tags - after_gc)) KB ($(get_size_human))"

# --- Vérification du dernier tag sur main ---
echo -e "\n🔖  Dernier tag sur '$main_branch' :"
latest_tag=$(git describe --tags --abbrev=0 "$main_branch" 2>/dev/null || echo "aucun")
echo "   $latest_tag"

# --- État final ---
echo -e "\n=== État final après nettoyage ==="
git status --short
git branch -vv
git tag -l
git count-objects -vH
explain_git_storage

echo "Taille .git après nettoyage : $(get_size_human)"
echo "💡  Gain total : $((before_total - after_gc)) KB ($(numfmt --to=iec $(((before_total - after_gc)*1024))))"
echo "============================================================"
echo "🎉  Dépôt préparé pour release et installation minimaliste."
echo

# --- Proposition de push vers le remote ---
if [[ "$skip_push" == "false" ]]; then
    echo
    echo "🚨  Vous êtes sur le point de pousser 'main' vers GitHub."
    echo "⚠️  Cela écrasera le contenu actuel de 'main' sur Github avec le commit unique local."
    echo

    if confirm "Confirmez-vous le push de 'main' sur GitHub ?"; then
        echo
        echo "🔄  Push en cours..."
        git push origin main --force
        echo "✅  Push terminé : 'main' sur GitHub est désormais aligné avec votre branche locale."
    else
        echo "ℹ️  Push annulé. 'main' reste uniquement local."
    fi
else
    echo "ℹ️  Aucun remote détecté, push impossible."
fi


popd >/dev/null
