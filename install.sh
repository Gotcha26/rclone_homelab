#!/bin/bash

# =========================================================================== #
#           Installateur GIT pour projet RCLONE_HOMELAB par Gotcha            #
# =========================================================================== #

REPO_URL="https://github.com/Gotcha26/rclone_homelab.git"
INSTALL_DIR="/opt/rclone_homelab"
GITHUB_API_URL="https://api.github.com/repos/Gotcha26/rclone_homelab/releases/latest"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

check_dependencies() {
    for dep in git curl; do
        if ! command -v "$dep" &>/dev/null; then
            echo -e "${RED}Erreur : $dep n'est pas installé.${RESET}"
            exit 1
        fi
    done
}

get_latest_release() {
    LATEST_TAG=$(curl -s "$GITHUB_API_URL" | grep '"tag_name":' | cut -d'"' -f4)
    LATEST_DATE=$(curl -s "$GITHUB_API_URL" | grep '"published_at":' | cut -d'"' -f4 | cut -d'T' -f1)
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}Impossible de récupérer la dernière release.${RESET}"
        exit 1
    fi
    echo "Dernière release : $LATEST_TAG ($LATEST_DATE)"
}

get_installed_release() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR" || return
        INSTALLED_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
        INSTALLED_DATE=$(git log -1 --format=%cd --date=short 2>/dev/null)
        if [ -n "$INSTALLED_TAG" ]; then
            echo "Version installée : $INSTALLED_TAG ($INSTALLED_DATE)"
        else
            echo "Version installée : inconnue"
        fi
        cd - >/dev/null || return
    fi
}

handle_existing_dir() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo -e "${YELLOW}Le répertoire $INSTALL_DIR existe déjà.${RESET}"
        get_installed_release
        echo
        echo "Que voulez-vous faire ?"
        echo "  [1] Supprimer et réinstaller la dernière release"
        echo "  [2] Mettre à jour vers la dernière release"
        echo "  [3] Ne rien faire et quitter"
        read -rp "Choix (1/2/3) : " choice
        case "$choice" in
            1)
                sudo rm -rf "$INSTALL_DIR"
                ;;
            2)
                cd "$INSTALL_DIR" || exit 1
                git fetch --tags
                git checkout -q "$LATEST_TAG" || {
                    echo -e "${RED}Impossible de passer sur la release $LATEST_TAG${RESET}"
                    exit 1
                }
                echo -e "${GREEN}✅ Mise à jour vers $LATEST_TAG réussie !${RESET}"
                exit 0
                ;;
            3|*)
                echo "Abandon."
                exit 0
                ;;
        esac
    fi
}

install() {
    echo -e "${GREEN}Installation de rclone_homelab (version $LATEST_TAG)...${RESET}"
    sudo mkdir -p "$INSTALL_DIR"
    if [ "$(id -u)" -ne 0 ]; then
        sudo chown "$(whoami)" "$INSTALL_DIR"
    fi
    cd "$INSTALL_DIR" || exit 1
    git -c advice.detachedHead=false clone --branch "$LATEST_TAG" --depth 1 "$REPO_URL" . || exit 1
    chmod +x main.sh
    echo -e "${GREEN}✅ Installation réussie !${RESET}"
    echo "Pour démarrer :"
    echo "  cd $INSTALL_DIR && ./main.sh"
}

# Execution
check_dependencies
get_latest_release
handle_existing_dir
install

exit



# =========================================================================== #
# Notes
# =========================================================================== #

# Les variables définies içi n'influent en rien le script une fois installé.
# Installation toujours basée sur le dernier tag (release).
# Prise en compte du root.


# Lien à communiquer pour l'installation :
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh)