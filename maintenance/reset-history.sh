#!/usr/bin/env bash
#
# reset-history.sh
#
# Réinitialise l’historique Git de la branche principale tout en
# conservant le contenu actuel du projet.
#
# 🔹  Crée une sauvegarde optionnelle de l’ancienne branche main.
# 🔹  Supprime tout l’historique et repart d’un seul commit propre.
# 🔹  Force la mise à jour du dépôt distant.
#
# ⚠️  Opération destructive : les anciens commits de 'main' seront perdus.
# ⚠️  À exécuter uniquement sur un dépôt dont on comprend les conséquences.
#
# Auteur : Julien Moreau
# Version : 1.2
# ---------------------------------------------------------------

set -euo pipefail

# -- Sécurise l'environnement SSH même sans agent --
export HOME=/root
export SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-""}
export DEBUG_MODE=${DEBUG_MODE:-false}


main_branch="main"
backup_branch="main_backup"

if [[ "$DEBUG_MODE" == "true" ]]; then
    echo "HOME=$HOME"
    echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    ls -l "$HOME/.ssh/"
fi

echo
echo "============================================================"
echo "🧹  Réinitialisation complète de la branche '$main_branch'"
echo "============================================================"
echo
echo "**** Infos Git ****"
git status --short
echo "**** _ ****"
echo

# Vérifier la présence de la branche main
if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    echo "⚠️  La branche '$main_branch' n'existe pas."
    exit 1
fi

# La nouvelle base est construite à partir de la branche COURANTE et de son arbre
# de travail : il faut donc être sur main, avec un arbre propre.
current_branch=$(git symbolic-ref --quiet --short HEAD || echo "detached")
if [[ "$current_branch" != "$main_branch" ]]; then
    echo "❌  Vous êtes sur '$current_branch' : placez-vous d'abord sur '$main_branch' (git checkout $main_branch)."
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "❌  L'arbre de travail contient des modifications non commitées :"
    git status --short
    echo "   Commitez-les ou stashez-les avant de réinitialiser l'historique."
    exit 1
fi

echo "ℹ️  Après réinitialisation, les tags existants ne seront plus dans l'historique de '$main_branch' :"
echo "   pensez à créer un nouveau tag de release, sinon les installations sur main"
echo "   ne détecteront plus de mise à jour."

# Vérifier configuration remote et accès SSH
remote_url="$(git remote get-url origin 2>/dev/null || true)"
skip_push=false

if [[ -z "$remote_url" ]]; then
    echo "⚠️  Aucun remote 'origin' détecté. Le push final sera ignoré."
    skip_push=true
else
    echo "🌐  Remote actuel : $remote_url"

    # Forcer l'utilisation de SSH si le remote est HTTPS
    if [[ "$remote_url" =~ ^https://github\.com ]]; then
        echo "⚙️  Conversion du remote GitHub HTTPS → SSH obligatoire..."
        ssh_url="git@github.com:Gotcha26/rclone_homelab.git"
        git remote set-url origin "$ssh_url"
        remote_url="$ssh_url"
        echo "✅  Remote mis à jour : $remote_url"
    fi

    # Vérifier la présence des clés SSH
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

    # Test de la connexion SSH réelle basé sur le code retour
    echo "🔐  Test de connexion SSH à GitHub..."
    ssh -i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=no -T git@github.com >/tmp/ssh_test.log 2>&1 || true

    if grep -q "successfully authenticated" /tmp/ssh_test.log; then
        echo "✅  Connexion SSH à GitHub opérationnelle."
    else
        echo "❌  Échec d’authentification SSH."
        echo "   Vérifiez votre clé publique sur GitHub et réessayez : ssh -i $ssh_key -T git@github.com"
        echo "⏹️  Arrêt du script : la connexion SSH est obligatoire pour pousser les changements."
        echo "---- Détails ----"
        cat /tmp/ssh_test.log
        echo "-----------------"
        exit 1
    fi
fi

# Confirmation création sauvegarde
echo
echo "Souhaitez-vous créer une sauvegarde de l'ancien '$main_branch' avant réinitialisation ?"
echo
read -rp "Votre réponse : (Y/n/q) : " yn
echo
[[ -z "$yn" || "$yn" =~ ^[Yy]$ ]] && yn="Y"
[[ "$yn" =~ ^[Qq]$ ]] && { echo "👋  Sortie."; exit 0; }

echo
if [[ "$yn" =~ ^[Yy]$ ]]; then
    echo "📦  Création de la sauvegarde locale '$backup_branch'..."
    git branch -f "$backup_branch" "$main_branch"
    if [[ $skip_push == false ]]; then
        git push origin "$backup_branch" || echo "ℹ️  Impossible de pousser '$backup_branch' (peut-être sans accès)."
    fi
    echo "✅  Sauvegarde prête : '$backup_branch'"
else
    echo "⏭️  Aucune sauvegarde créée."
fi

# Création de la nouvelle base
echo
echo "🚧  Création d'une nouvelle base propre..."
git checkout --orphan temp_clean
git add -A
git commit -m "Réinitialisation : base propre"

# Remplacer main
git branch -M "$main_branch" old_main
git branch -m temp_clean "$main_branch"
git branch -D old_main 2>/dev/null || true

# Push forcé
if [[ $skip_push == false ]]; then
    echo
    echo "⚠️  Cette opération va écraser la branche '$main_branch' distante (GitHub)."
    echo
    read -rp "Confirmer le push forcé ? (Y/n/q) : " confirm
    echo
    [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]] && confirm="Y"
    [[ "$confirm" =~ ^[Qq]$ ]] && { echo "👋 Sortie."; exit 0; }

    echo
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "🚀  Envoi forcé vers le dépôt distant..."
        if git push origin "$main_branch" --force; then
            echo "✅  Nouvelle base publiée sur '$main_branch'."
        else
            echo "❌  Échec du push distant. Vérifiez vos identifiants ou droits d’accès."
        fi
    else
        echo "⏹️  Push forcé annulé. La réinitialisation reste locale."
    fi
else
    echo "⚠️  Aucun push distant effectué (remote manquant ou ignoré)."
fi

echo
echo "============================================================"
echo "✨ Branche '$main_branch' nettoyée et réinitialisée."
git log --oneline -n 1
echo "============================================================"
echo
