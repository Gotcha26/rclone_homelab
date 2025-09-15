#!/usr/bin/env bash
# ============================================================================ #
#  Standalone updater pour RCLONE_HOMELAB
# ============================================================================ #
# 
# Usage :
#   rclone_homelab-updater [--force]
#
# Options :
#   --force    : Réinstalle complètement le projet depuis GitHub
#                → Écrase tous les fichiers locaux, y compris ceux ignorés
#                → Conserve uniquement la branche locale active
#
# Exemple :
#   rclone_homelab-updater          # Vérifie et applique les mises à jour normalement
#   rclone_homelab-updater --force  # Réinstalle tout depuis GitHub en mode table rase
#
# Pré-requis :
#   - Git et curl doivent être installés
#   - Connexion Internet nécessaire pour accéder à GitHub
#
# Notes :
#   - Le script détecte automatiquement la branche locale active (main, dev, ...)
#   - Sans --force, les fichiers ignorés par Git (.gitignore) ne sont pas touchés
#   - Avec --force, tous les fichiers sont remplacés pour garantir une installation "propre"
#
# Pour créer un accès global :
#   chmod +x /opt/rclone_homelab/update/standalone_updater.sh
#   sudo ln -sf /opt/rclone_homelab/update/standalone_updater.sh /usr/local/bin/rclone_homelab-updater
#
# ============================================================================ #


set -euo pipefail

REPO_URL="https://github.com/Gotcha26/rclone_homelab.git"

# --------------------------------------------------------------------------- #
# 1. Lecture des arguments
# --------------------------------------------------------------------------- #
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_MODE=true
fi

# --------------------------------------------------------------------------- #
# 2. Déterminer le dossier du projet
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR" || {
    echo "❌  Impossible d'accéder au répertoire projet ($SCRIPT_DIR)"
    exit 1
}

# --------------------------------------------------------------------------- #
# 3. Dépendances minimales
# --------------------------------------------------------------------------- #
for bin in git curl rsync; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "⚠️  $bin n'est pas installé."
        if command -v apt >/dev/null 2>&1; then
            if [ "$(id -u)" -eq 0 ]; then
                apt update && apt install -y "$bin" || { echo "❌ Impossible d'installer $bin"; exit 2; }
            else
                sudo apt update && sudo apt install -y "$bin" || { echo "❌ Impossible d'installer $bin"; exit 2; }
            fi
        else
            echo "❌ Installez $bin manuellement."
            exit 3
        fi
    fi
done

# --------------------------------------------------------------------------- #
# 4. Vérif connexion Internet
# --------------------------------------------------------------------------- #
if ! curl -Is https://github.com >/dev/null 2>&1; then
    echo "❌  Pas de connexion Internet ou GitHub inaccessible."
    exit 4
fi

# --------------------------------------------------------------------------- #
# 5. Récupération de la branche locale active
# --------------------------------------------------------------------------- #
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
echo "🔎  Branche détectée : $CURRENT_BRANCH"

# --------------------------------------------------------------------------- #
# 6. Mise à jour (mode normal ou --force)
# --------------------------------------------------------------------------- #
if [[ "$FORCE_MODE" == true ]]; then
    echo "⚠️  Mode FORCÉ activé : réinstallation complète depuis $REPO_URL ($CURRENT_BRANCH)"
    TMP_DIR=$(mktemp -d)

    git clone --branch "$CURRENT_BRANCH" "$REPO_URL" "$TMP_DIR" || {
        echo "❌  Impossible de cloner le dépôt."
        rm -rf "$TMP_DIR"
        exit 5
    }

    # Copier tout en respectant les permissions
    if [ "$(id -u)" -eq 0 ] || [ -w "$SCRIPT_DIR" ]; then
        rsync -a --delete "$TMP_DIR"/ "$SCRIPT_DIR"/
    else
        sudo rsync -a --delete "$TMP_DIR"/ "$SCRIPT_DIR"/
    fi

    rm -rf "$TMP_DIR"
    echo "✅  Projet réinstallé en mode FORCÉ."
    exit 0
else
    echo "🔄  Vérification des mises à jour Git..."
    git fetch --all --tags || { echo "❌ Impossible d'accéder au dépôt Git."; exit 6; }

    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse "origin/$CURRENT_BRANCH")

    if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
        echo "📥  Mise à jour vers la dernière révision de $CURRENT_BRANCH..."
        git reset --hard "origin/$CURRENT_BRANCH"
        echo "✅  Mise à jour terminée."
    else
        echo "✅  Aucune mise à jour disponible."
    fi
fi
