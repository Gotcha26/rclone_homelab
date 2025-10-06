#!/usr/bin/env bash
#
# reset-history.sh
#
# Réinitialise l’historique Git de la branche principale tout en
# conservant le contenu actuel du projet.
#
# 🔹 Crée une sauvegarde optionnelle de l’ancienne branche main.
# 🔹 Supprime tout l’historique et repart d’un seul commit propre.
# 🔹 Force la mise à jour du dépôt distant.
#
# ⚠️ Opération destructive : les anciens commits de 'main' seront perdus.
# ⚠️ À exécuter uniquement sur un dépôt dont on comprend les conséquences.
#
# Auteur : Julien Moreau
# Version : 1.1
# ---------------------------------------------------------------

set -euo pipefail

main_branch="main"
backup_branch="main_backup"

echo
echo "============================================================"
echo "🧹  Réinitialisation complète de la branche '$main_branch'"
echo "============================================================"
echo
echo "**** Infos Git ****"
git status --short
echo "****"
echo

# Vérifier la présence de la branche main
if ! git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    echo "⚠️  La branche '$main_branch' n'existe pas."
    exit 1
fi

# --- Confirmation avec valeurs par défaut ---
confirm_prompt() {
    local prompt="$1"
    local default="$2"
    local answer
    echo
    read -rp "$prompt" answer
    echo
    case "${answer,,}" in
        q) echo "❌  Opération annulée."; exit 0 ;;
        y|"") [[ "$default" == "Y" ]] && return 0 || return 1 ;;
        n) [[ "$default" == "N" ]] && return 0 || return 1 ;;
        *) echo "⚠️  Réponse invalide."; confirm_prompt "$prompt" "$default" ;;
    esac
}

# Sauvegarde optionnelle (par défaut : oui)
if confirm_prompt "Souhaitez-vous créer une sauvegarde de l'ancien '$main_branch' avant réinitialisation ? (Y/n/q) : " "Y"; then
    echo "📦  Création de la sauvegarde locale '$backup_branch'..."
    git branch -f "$backup_branch" "$main_branch"
    git push origin "$backup_branch" || echo "ℹ️  Impossible de pousser '$backup_branch' (peut-être sans remote)."
    echo "✅  Sauvegarde prête : '$backup_branch'"
else
    echo "⏭️  Aucune sauvegarde créée."
fi

# Créer une nouvelle branche orpheline
echo
echo "🚧  Création d'une nouvelle base propre..."
git checkout --orphan temp_clean
git add -A
git commit -m "Réinitialisation : base propre"

# Remplacer main par la nouvelle branche
git branch -M "$main_branch" old_main
git branch -m temp_clean "$main_branch"
git branch -D old_main 2>/dev/null || true

# Push forcé (par défaut : oui)
if confirm_prompt "⚠️  Cette opération va écraser la branche '$main_branch' distante. Confirmer le push forcé ? (Y/n/q) : " "Y"; then
    echo "🚀 Envoi forcé vers le dépôt distant..."
    git push origin "$main_branch" --force
    echo "✅  Nouvelle base publiée sur '$main_branch'."
else
    echo "⏹️  Push forcé annulé. La réinitialisation reste locale."
fi

echo
echo "============================================================"
echo "✨ Branche '$main_branch' nettoyée et réinitialisée."
git log --oneline -n 1
echo "============================================================"
