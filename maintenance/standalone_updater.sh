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
#                → Écrase tous les fichiers du projet
#                → Préserve les fichiers utilisateur (local/, logs/, tmps/)
#                → Conserve uniquement la branche locale active (main si indéterminable)
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
#   - Script rendu exécutable via l'installation. Sinon la commande est :
#   chmod +x /opt/rclone_homelab/maintenance/standalone_updater.sh
#   - Un symlink est aussi créé automatiquement via install.sh Sinon  la commande est :
#   ln -sf /opt/rclone_homelab/maintenance/standalone_updater.sh /usr/local/bin/rclone_homelab-updater
#
# ============================================================================ #


set -euo pipefail

REPO_URL="https://github.com/Gotcha26/rclone_homelab.git"

# Couleurs texte
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'
BLACK='\033[0;30m'; WHITE='\033[1;37m'

# Couleurs de fond
BG_WHITE='\033[47m'; BG_BLACK='\033[40m'

# Styles
RESET='\033[0m'; BOLD="\033[1m"; ITALIC="\033[3m"; UNDERLINE="\033[4m"


clear
echo "+------------------------------------------------------------------------------+"
echo -e "|              ${BOLD}Programme de mise à jour autonome pour le script :${RESET}              |"
echo -e "|                          ${BOLD}${UNDERLINE}rclone_homelab${RESET} par ${ITALIC}GOTCHA !${RESET}                         |"
echo "+------------------------------------------------------------------------------+"
echo
echo -e "${BLACK}${BG_WHITE} ▌║█║▌│║▌│║▌║▌█║ $REPO_URL ▌│║▌║▌│║║▌█║▌║█ ${RESET}"
echo
echo
echo -e " ${BOLD}Mise en garde${RESET} : Ne fonctionne que sur une installation clonée via GitHub !..."
echo
echo
sleep 0.5

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
# 6. Détection mode Git ou standalone
# --------------------------------------------------------------------------- #
LOCAL_VERSION_FILE="$SCRIPT_DIR/local/.version"

# Fichiers utilisateur à ne jamais supprimer lors d'un rsync --delete
RSYNC_EXCLUDES=(--exclude '/local/' --exclude '/logs/' --exclude '/tmps/')

if [ -d "$SCRIPT_DIR/.git" ]; then
    MODE="git"
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")
    if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
        if [[ "$FORCE_MODE" == true ]]; then
            echo -e "${YELLOW}⚠️  HEAD détaché détecté : réinitialisation sur la branche main.${RESET}"
            CURRENT_BRANCH="main"
        else
            echo -e "${RED}❌  HEAD détaché détecté, impossible de déterminer la branche active.${RESET}"
            echo -e "   → Exécutez le script en mode --force pour réinitialiser le dépôt.${RESET}"
            exit 8
        fi
    fi
    echo -e "🔎  Branche détectée : ${GREEN}$CURRENT_BRANCH${RESET}"

elif [[ -f "$LOCAL_VERSION_FILE" ]]; then
    MODE="standalone"
    CURRENT_BRANCH="main"   # par convention, on suit la branche main
    LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE")
    echo -e "🔎  Mode ${YELLOW}standalone${RESET}, version locale : ${GREEN}$LOCAL_VERSION${RESET}"

elif [[ "$FORCE_MODE" == true ]]; then
    MODE="unknown"
    CURRENT_BRANCH="main"
    echo -e "${YELLOW}⚠️  Mode d'installation indéterminé : réinstallation depuis la branche main.${RESET}"

else
    echo -e "${RED}❌  Impossible de déterminer le mode de mise à jour (ni .git ni .version trouvés).${RESET}"
    echo -e "   → Exécutez le script une première fois en mode --force.${RESET}"
    exit 7
fi

# --------------------------------------------------------------------------- #
# 7. Mise à jour selon le mode
# --------------------------------------------------------------------------- #
if [[ "$FORCE_MODE" == true ]]; then
    echo -e "${YELLOW}⚠️  Mode FORCÉ activé : réinstallation complète depuis $REPO_URL ($CURRENT_BRANCH)${RESET}"
    TMP_DIR=$(mktemp -d)
    git clone --branch "$CURRENT_BRANCH" "$REPO_URL" "$TMP_DIR" || {
        echo -e "${RED}❌  Impossible de cloner le dépôt.${RESET}"
        rm -rf "$TMP_DIR"
        exit 5
    }
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$TMP_DIR"/ "$SCRIPT_DIR"/
    rm -rf "$TMP_DIR"
    echo "✅  Réinstallation complète effectuée."
    mkdir -p "$(dirname "$LOCAL_VERSION_FILE")"
    echo "$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "unknown")" > "$LOCAL_VERSION_FILE"

else
    if [[ "$MODE" == "git" ]]; then
        echo "🔄  Vérification des mises à jour Git..."
        git fetch --all --tags
        LOCAL_HASH=$(git rev-parse HEAD)
        REMOTE_HASH=$(git rev-parse "origin/$CURRENT_BRANCH")
        if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
            echo -e "📥  Mise à jour vers la dernière révision de ${GREEN}$CURRENT_BRANCH${RESET}..."
            git reset --hard "origin/$CURRENT_BRANCH"
            echo "✅  Clonage terminé."
        else
            echo "✅  Aucune mise à jour disponible."
        fi

    elif [[ "$MODE" == "standalone" ]]; then
        echo "🔄  Vérification des nouvelles releases GitHub..."
        REMOTE_VERSION=$(curl -s "https://api.github.com/repos/Gotcha26/rclone_homelab/releases/latest" \
                         | grep -oP '"tag_name": "\K(.*)(?=")' || true)
        if [[ -z "$REMOTE_VERSION" ]]; then
            echo -e "${YELLOW}⚠️  Impossible de récupérer la version distante.${RESET}"
            exit 6
        fi

        if [[ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]]; then
            echo -e "📥  Nouvelle release disponible : ${GREEN}$REMOTE_VERSION${RESET} (actuelle : ${RED}$LOCAL_VERSION${RESET})"
            TMP_DIR=$(mktemp -d)
            # Clone du tag de la release (et non du HEAD de main), sans historique git
            git -c advice.detachedHead=false clone --depth 1 --branch "$REMOTE_VERSION" "$REPO_URL" "$TMP_DIR"
            rsync -a --delete --exclude '/.git' "${RSYNC_EXCLUDES[@]}" "$TMP_DIR"/ "$SCRIPT_DIR"/
            rm -rf "$TMP_DIR"
            echo "$REMOTE_VERSION" > "$LOCAL_VERSION_FILE"
            echo "✅  Mise à jour standalone terminée."
        else
            echo -e "✅  Aucune mise à jour disponible (version ${GREEN}$LOCAL_VERSION${RESET})."
        fi
    fi
fi

# --------------------------------------------------------------------------- #
# 8. Ré-application des permissions essentielles
# --------------------------------------------------------------------------- #
echo -e "🔧  Vérification et mise en place des scripts...${RESET}"

for file in "$SCRIPT_DIR/main.sh" "$SCRIPT_DIR/maintenance/standalone_updater.sh"; do
    if [[ -f "$file" ]]; then
        # Rendre exécutable
        if [[ -w "$file" ]]; then
            $SUDO chmod +x "$file"
        else
            echo -e "${RED}❌  Un problème est survenu pour rendre exécutable : $file${RESET}"
        fi
        echo "   > Est rendu exécutable : $file ✓"

        # Déterminer le symlink associé
        case "$file" in
            "$SCRIPT_DIR/main.sh")
                symlink="/usr/local/bin/rclone_homelab"
                ;;
            "$SCRIPT_DIR/maintenance/standalone_updater.sh")
                symlink="/usr/local/bin/rclone_homelab-updater"
                ;;
            *) symlink=""
                ;;
        esac

        # Création du symlink si défini
        if [[ -n "$symlink" ]]; then
            if [[ -w "$(dirname "$symlink")" ]]; then
                ln -sf "$file" "$symlink"
            else
                $SUDO ln -sf "$file" "$symlink"
            fi
            echo "   >> Son symlink associé : $symlink"
            echo "                          → $file"
        fi
    else
        echo -e "${YELLOW}⚠️  Fichier introuvable : $file${RESET}"
    fi
done


echo -e "\n${GREEN}🎉  Mise à jour complète !${RESET}"
echo -e "Vous pouvez maintenant relancer le projet via : ${BLUE}${BOLD}rclone_homelab${RESET}\n"
exit 0