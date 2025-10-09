#!/usr/bin/env bash
#
# maintenance.sh
#
# Script de maintenance pour nettoyer et compacter l’historique Git.
#
# 🔹 Fonctionnement :
#   1. Analyse les stats Git des dépôts sélectionnés et les affiche.
#   2. Propose à l’utilisateur de lancer un nettoyage agressif (`git gc --prune=now --aggressive`).
#   3. Affiche un comparatif avant/après nettoyage (taille .git, count-objects, etc.).
#
# 🔹 Mode batch :
#   - Si plusieurs dépôts sont fournis, le script fait un résumé global avant traitement,
#     demande confirmation unique, puis traite tous les dépôts.
#
# 🔹 Ajout de dépôts supplémentaires :
#   - Le script propose d’ajouter un ou plusieurs dossiers Git supplémentaires
#     à traiter dans la même session.
#   - Pour en fournir plusieurs, séparez-les avec le symbole " | ".
#     Exemple : /opt/projet1 | /srv/app_git | ~/perso/monrepo
#
# 🔹 Important :
#   - Script à exécution manuelle uniquement (pas prévu pour cron).
#   - Chaque dépôt est traité individuellement mais le mode batch fait un résumé global.

set -euo pipefail

# --- Helpers ---
get_size_kb() { du -sk "$1/.git" | awk '{print $1}'; }
get_size_human() { du -sh "$1/.git" | awk '{print $1}'; }

# === Script principal ===

# 1. Toujours inclure le dossier courant
repo_list=("$PWD")

# 2. Proposer d’ajouter d’autres dépôts
read -rp $'\nVoulez-vous ajouter un ou plusieurs dossiers Git supplémentaires ? (séparés par " | ") : ' extra_repos
if [[ -n "${extra_repos// }" ]]; then
    IFS="|" read -ra extra_array <<< "$extra_repos"
    for r in "${extra_array[@]}"; do
        repo_list+=("$(realpath "${r// }")")
    done
fi

# 3. Déterminer si mode batch
batch_mode=false
if (( ${#repo_list[@]} > 1 )); then
    batch_mode=true
fi

# --- Résumé global avant traitement si batch ---
total_before=0
if [[ "$batch_mode" == true ]]; then
    echo -e "\n📊 Résumé global avant nettoyage (mode batch) :"
    for repo in "${repo_list[@]}"; do
        if [[ -d "$repo/.git" ]]; then
            size_kb=$(get_size_kb "$repo")
            size_h=$(get_size_human "$repo")
            echo "  $repo : $size_h"
            total_before=$(( total_before + size_kb ))
        else
            echo "⚠️  $repo n’est pas un dépôt Git valide."
        fi
    done
    echo "  Taille totale : $(numfmt --to=iec $((total_before*1024)))"
    read -rp $'\n👉  Lancer le nettoyage agressif pour tous les dépôts listés ? (y/N) : ' yn
    if [[ ! "$yn" =~ ^[Yy] ]]; then
        echo "❎  Nettoyage annulé pour tous les dépôts."
        exit 0
    fi
fi

# --- Suivi global des tailles ---
total_after=0

# 4. Boucle sur chaque dépôt
for repo in "${repo_list[@]}"; do
    echo -e "\n============================================================"
    echo "📂 Dépôt : $repo"

    if [[ ! -d "$repo/.git" ]]; then
        echo "⚠️  Ce dossier n’est pas un dépôt Git valide."
        continue
    fi

    # --- État avant ---
    before_size=$(get_size_kb "$repo")
    before_human=$(get_size_human "$repo")
    echo "=== État avant nettoyage ==="
    git -C "$repo" count-objects -vH
    echo "Taille avant nettoyage : $before_human"

    # --- Nettoyage ---
    if [[ "$batch_mode" == false ]]; then
        read -rp $'\n👉  Nettoyer ce dépôt (y/N) ? : ' yn
        if [[ ! "$yn" =~ ^[Yy] ]]; then
            echo "❎  Nettoyage annulé pour $repo."
            total_before=$(( total_before + before_size ))
            total_after=$(( total_after + before_size ))
            continue
        fi
    fi

    echo "🧹  Nettoyage de $repo ..."
    git -C "$repo" gc --prune=now --aggressive
    echo "✅  Nettoyage terminé."

    # --- État après ---
    after_size=$(get_size_kb "$repo")
    after_human=$(get_size_human "$repo")
    echo
    echo "=== État après nettoyage ==="
    git -C "$repo" count-objects -vH
    echo "Taille après nettoyage : $after_human"

    # --- Comparaison ---
    gain=$((before_size - after_size))
    if [ "$gain" -gt 0 ]; then
        gain_human=$(numfmt --to=iec "$((gain*1024))")
        echo "💡 Gain obtenu : $gain_human (${before_human} → ${after_human})"
    else
        echo "ℹ️  Aucun gain obtenu (dépôt déjà optimisé)."
    fi

    # --- Mise à jour des totaux ---
    total_before=$(( total_before + before_size ))
    total_after=$(( total_after + after_size ))
done

# --- Résumé global ---
if [[ "$batch_mode" == true ]]; then
    echo -e "\n============================================================"
    echo "📊 Résumé global après traitement :"
    echo "   Taille totale avant nettoyage : $(numfmt --to=iec $((total_before*1024)))"
    echo "   Taille totale après nettoyage : $(numfmt --to=iec $((total_after*1024)))"
    echo "   Gain total                   : $(numfmt --to=iec $(((total_before-total_after)*1024)))"
    echo "============================================================"
fi

echo "🎉 Maintenance terminée."
