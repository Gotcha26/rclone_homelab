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

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

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
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$SCRIPT_DIR" || {
    echo -e "${RED}❌  Impossible d'accéder au répertoire projet ($SCRIPT_DIR)${RESET}"
    exit 1
}

# ---------------------------------------------------------------------------- #
# 3. Détection sudo
# ---------------------------------------------------------------------------- #
if [[ $(id -u) -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

# --------------------------------------------------------------------------- #
# 4. Dépendances minimales
# --------------------------------------------------------------------------- #
for bin in git curl rsync; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  $bin n'est pas installé.${RESET}"
        if command -v apt >/dev/null 2>&1; then
            if [ "$(id -u)" -eq 0 ]; then
                apt update && apt install -y "$bin" || { echo -e "${RED}❌ Impossible d'installer $bin${RESET}"; exit 2; }
            else
                $SUDO apt update && $SUDO apt install -y "$bin" || { echo -e "${RED}❌ Impossible d'installer $bin${RESET}"; exit 2; }
            fi
        else
            echo -e "${RED}❌ Installez $bin manuellement.${RESET}"
            exit 3
        fi
    fi
done

# --------------------------------------------------------------------------- #
# 5. Vérif connexion Internet
# --------------------------------------------------------------------------- #
if ! curl -Is https://github.com >/dev/null 2>&1; then
    echo -e "${RED}❌  Pas de connexion Internet ou GitHub inaccessible.${RESET}"
    exit 4
fi

# --------------------------------------------------------------------------- #
# 6. Vérification dépôt Git et branche active
# --------------------------------------------------------------------------- #
if [ ! -d "$SCRIPT_DIR/.git" ]; then
    echo -e "${RED}❌  Aucun dépôt Git détecté dans $SCRIPT_DIR !${RESET}"
    echo -e "   → Exécutez le script une première fois en mode --force pour cloner proprement.${RESET}"
    exit 7
fi

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
    echo -e "${RED}❌  HEAD détaché détecté, impossible de déterminer la branche active.${RESET}"
    echo -e "   → Exécutez le script en mode --force pour réinitialiser le dépôt.${RESET}"
    exit 8
fi
echo -e "🔎  Branche détectée : ${GREEN}$CURRENT_BRANCH${RESET}"

# --------------------------------------------------------------------------- #
# 7. Mise à jour (mode normal ou --force)
# --------------------------------------------------------------------------- #
if [[ "$FORCE_MODE" == true ]]; then
    echo -e "${YELLOW}⚠️  Mode FORCÉ activé : réinstallation complète depuis $REPO_URL ($CURRENT_BRANCH)${RESET}"
    TMP_DIR=$(mktemp -d)
    git clone --branch "$CURRENT_BRANCH" "$REPO_URL" "$TMP_DIR" || {
        echo -e "${RED}❌  Impossible de cloner le dépôt.${RESET}"
        rm -rf "$TMP_DIR"
        exit 5
    }

    if [ "$(id -u)" -eq 0 ] || [ -w "$SCRIPT_DIR" ]; then
        rsync -a --delete "$TMP_DIR"/ "$SCRIPT_DIR"/
    else
        $SUDO rsync -a --delete "$TMP_DIR"/ "$SCRIPT_DIR"/
    fi

    rm -rf "$TMP_DIR"
    echo -e "${GREEN}✅  Projet réinstallé en mode FORCÉ.${RESET}"

    # Ré-appliquer les permissions essentielles
    for file in "$SCRIPT_DIR/main.sh" "$SCRIPT_DIR/update/standalone_updater.sh"; do
        [[ -f "$file" ]] && chmod +x "$file" && echo -e "${GREEN}   → $file rendu exécutable ✅${RESET}"
    done

    exit 0
else
    echo -e "🔄  Vérification des mises à jour Git...${RESET}"
    git fetch --all --tags || { echo -e "${RED}❌ Impossible d'accéder au dépôt Git.${RESET}"; exit 6; }

    LOCAL_HASH=$(git rev-parse HEAD)
    REMOTE_HASH=$(git rev-parse "origin/$CURRENT_BRANCH")

    if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
        echo -e "📥  Mise à jour vers la dernière révision de $CURRENT_BRANCH...${RESET}"
        git reset --hard "origin/$CURRENT_BRANCH"
        echo -e "${GREEN}✅  Mise à jour terminée.${RESET}"
    else
        echo -e "${GREEN}✅  Aucune mise à jour disponible.${RESET}"
    fi
fi

# --------------------------------------------------------------------------- #
# 8. Ré-application des permissions essentielles
# --------------------------------------------------------------------------- #
echo -e "🔧  Vérification des permissions...${RESET}"

for file in "$SCRIPT_DIR/main.sh" "$SCRIPT_DIR/update/standalone_updater.sh"; do
    if [[ -f "$file" ]]; then
        if [[ -w "$file" ]]; then
            chmod +x "$file"
        else
            $SUDO chmod +x "$file"
        fi
        echo -e "${GREEN}   → $file rendu exécutable ✅${RESET}"
    fi
done

# --------------------------------------------------------------------------- #
# 9. Création symlink principal
# --------------------------------------------------------------------------- #
create_symlink() {
    SYMLINK="/usr/local/bin/rclone_homelab"
    if [ -w "$(dirname "$SYMLINK")" ]; then
        ln -sf "$SCRIPT_DIR/main.sh" "$SYMLINK"
    else
        $SUDO ln -sf "$SCRIPT_DIR/main.sh" "$SYMLINK"
    fi
    chmod +x "$SCRIPT_DIR/main.sh"
    echo -e "${GREEN}✅  Symlink créé : $SYMLINK → $SCRIPT_DIR/main.sh${RESET}"
}

# --------------------------------------------------------------------------- #
# 10. Création symlink updater
# --------------------------------------------------------------------------- #
create_updater_symlink() {
    UPDATER_SCRIPT="$SCRIPT_DIR/update/standalone_updater.sh"
    UPDATER_SYMLINK="/usr/local/bin/rclone_homelab-updater"

    if [ -f "$UPDATER_SCRIPT" ]; then
        chmod +x "$UPDATER_SCRIPT"
        if [ -w "$(dirname "$UPDATER_SYMLINK")" ]; then
            ln -sf "$UPDATER_SCRIPT" "$UPDATER_SYMLINK"
        else
            $SUDO ln -sf "$UPDATER_SCRIPT" "$UPDATER_SYMLINK"
        fi
        echo -e "${GREEN}✅  Updater exécutable et symlink créé : $UPDATER_SYMLINK → $UPDATER_SCRIPT${RESET}"
    else
        echo -e "${YELLOW}⚠️  Fichier $UPDATER_SCRIPT introuvable.${RESET}"
    fi
}

echo -e "\n✅  Mise à jour terminée. Vous pouvez maintenant relancer le projet avec :${RESET}"
echo -e "   rclone_homelab${RESET}\n"
exit 0
