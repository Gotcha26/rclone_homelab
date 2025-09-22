#!/bin/bash
#
# install.sh
#
# Installateur RCLONE_HOMELAB par Gotcha
#
# 4 modes gérés :
#   Cas 1 : dossier d'installation absent → installation minimale à partir de la dernière release (ZIP)
#   Cas 2 : dossier d'installation présent, pas de fichier .version → proposition de nettoyage ou quitter
#   Cas 3 : dossier d'installation présent avec .version → mise à jour minimale si nouvelle release disponible
#   Cas 4 : argument --dev <branch> → clone complet Git de la branche indiquée (historique limité à cette branche)
#
# ⚠️ Le fichier .version contient le tag installé pour permettre les mises à jour minimales
# ⚠️ Les installations minimalistes ne conservent pas le .git, donc pas d'historique complet
# ⚠️ Le mode --force <branche> permet de travailler avec Git complet mais limité à la branche demandée

set -euo pipefail

clear
echo "================================================================================"
echo "*            Installateur GIT pour projet RCLONE_HOMELAB par Gotcha            *"
echo "================================================================================"
echo


# =========================================================================== #
#           Installateur GIT pour projet RCLONE_HOMELAB par Gotcha            #
# =========================================================================== #

REPO_URL="https://github.com/Gotcha26/rclone_homelab.git"
INSTALL_DIR="/opt/rclone_homelab"
LOCAL_DIR="$INSTALL_DIR/local"
VERSION_FILE="$LOCAL_DIR/.version"
GITHUB_API_URL="https://api.github.com/repos/Gotcha26/rclone_homelab/releases/latest"

# Argument pour mode dev
FORCED="${1:-}"
FORCED_BRANCH="${2:-main}"  # si pas de branche précisée, fallback sur main

# Couleurs / styles
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'
RESET='\033[0m'; BOLD="\033[1m"; ITALIC="\033[3m"; UNDERLINE="\033[4m"

# ---------------------------------------------------------------------------- #
# Détection sudo
# ---------------------------------------------------------------------------- #
if [[ $(id -u) -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
create_local_dir() {
    $SUDO mkdir -p "$LOCAL_DIR"
}

write_version_file() {
    local tag="$1"
    echo "$tag" > "$VERSION_FILE"
}

read_version_file() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------- #
# Mode FORCED / DEV → clone complet direct
# ---------------------------------------------------------------------------- #
if [[ "$FORCED" == "--force" || "$FORCED" == "--dev" ]]; then
    echo -e "⚡ Mode ${BOLD}développement forcé${RESET} → clone Git complet de la branche : ${ITALIC}$FORCED_BRANCH${RESET}"
    $SUDO rm -rf "$INSTALL_DIR"
    git clone --branch "$FORCED_BRANCH" --single-branch --depth 1 "$REPO_URL" "$INSTALL_DIR"
    echo -e "✅ Dépôt cloné depuis ${UNDERLINE}$REPO_URL${RESET} (branche ${BOLD}$FORCED_BRANCH${RESET})"
    exit 0
fi

# --------------------------------------------------------------------------- #
# Vérification des dépendances
# --------------------------------------------------------------------------- #
check_dependencies() {
    local deps=(git curl)
    local missing=()

    # Vérifie git et curl
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "⚠️  ${RED}Erreur :${RESET} dépendances manquantes : ${YELLOW}${missing[*]}${RESET}"
        echo
        echo "Installez-les avec : sudo apt install ${missing[*]}"
        exit 1
    fi

    # Gestion spéciale pour unzip
    if ! command -v unzip &>/dev/null; then
        echo -e "⚠️  ${RED}Le composant ${UNDERLINE}unzip${RESET}${RED} est requis mais n'est pas installé.${RESET}"
        echo
        read -rp "Voulez-vous installer unzip maintenant ? (y/N) : " yn
        case "$yn" in
            [Yy]*)
                if $SUDO apt update && $SUDO apt install -y unzip; then
                    echo -e "✅  unzip installé avec succès."
                else
                    echo -e "${RED}❌  Impossible d'installer unzip.${RESET}"
                    exit 1
                fi
                ;;
            *)
                echo -e "${RED}❌  Impossible de continuer sans unzip.${RESET}"
                exit 1
                ;;
        esac
    fi
}

# --------------------------------------------------------------------------- #
# Vérification et installation de rclone
# --------------------------------------------------------------------------- #
check_rclone() {
    if ! command -v rclone &>/dev/null; then
        echo -e "⚠️  ${RED}L'outil ${UNDERLINE}rclone${RESET}${RED} n'est pas encore installé, il est ${BOLD}indispensable${RESET}."
        echo "Plus d'infos sur rclone : https://rclone.org/"
        echo
        read -rp "Voulez-vous installer rclone maintenant ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_rclone ;;
            *) echo -e "${RED}${BOLD}Impossible de continuer sans rclone.${RESET}"; exit 1 ;;
        esac
    else
        local local_version latest_version
        local_version=$(rclone version 2>/dev/null | head -n1 | awk '{print $2}')
        
        # Récupération de la dernière version stable de rclone
        latest_version=$(curl -s https://rclone.org/downloads/ \
            | grep 'Current stable version:' \
            | awk '{print $4}')

        # Vérification des versions
        if [[ -z "$latest_version" ]]; then
            echo -e "${YELLOW}⚠️  Impossible de récupérer la dernière version de rclone.${RESET}"
            echo -e "  Version locale détectée : ${local_version:-inconnue}"
            echo -e "  Version stable récupérée : ${latest_version:-inconnue}"
            return
        fi

        echo -e "✔️  rclone détecté. Version locale : ${ITALIC}${local_version}${RESET}, version stable : ${ITALIC}${latest_version}${RESET}"

        if [[ "$local_version" != "$latest_version" ]]; then
            echo "ℹ️  Nouvelle version rclone disponible : $latest_version"
            echo
            read -rp "Voulez-vous mettre à jour rclone ? (y/N) : " yn
            case "$yn" in
                [Yy]*) install_rclone ;;
                *) echo "👉  Vous gardez la version existante." ;;
            esac
        fi
    fi
}

install_rclone() {
    echo "📦  Installation / mise à jour de rclone..."

    # Détection architecture pour télécharger le bon binaire
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch_tag="linux-amd64" ;;
        aarch64|arm64) arch_tag="linux-arm64" ;;
        *) echo -e "${RED}❌  Architecture $arch non supportée.${RESET}"; exit 1 ;;
    esac

    # Téléchargement du zip officiel
    zip_file="rclone-current-${arch_tag}.zip"
    curl -Of "https://downloads.rclone.org/${zip_file}" || { 
        echo -e "${RED}❌  Échec du téléchargement de rclone.${RESET}"; 
        exit 1; 
    }

    # Vérifie que le fichier existe et n’est pas vide
    if [ ! -s "$zip_file" ]; then
        echo -e "${RED}❌  Fichier téléchargé invalide ou vide : $zip_file${RESET}"
        exit 1
    fi

    # Extraction
    unzip -o "$zip_file" || { 
        echo -e "${RED}❌  Échec de l'extraction du zip rclone.${RESET}"; 
        exit 1; 
    }

    # Copie du binaire
    if [ -w "/usr/local/bin" ]; then
        cp rclone-*-${arch_tag}/rclone /usr/local/bin/ || { echo "❌  Impossible de copier rclone"; exit 1; }
    else
        $SUDO cp rclone-*-${arch_tag}/rclone /usr/local/bin/ || { echo "❌  Impossible de copier rclone"; exit 1; }
    fi
    chmod +x /usr/local/bin/rclone

    # Nettoyage
    rm -rf rclone-*-${arch_tag} "$zip_file"

    echo "✅  rclone installé/mis à jour avec succès."
}


# --------------------------------------------------------------------------- #
# Vérification optionnelle de msmtp
# --------------------------------------------------------------------------- #
check_msmtp() {
    if ! command -v msmtp &>/dev/null; then
        echo -e "⚠️  ${YELLOW}Le compostant ${UNDERLINE}msmtp${RESET}${YELLOW} non détecté (optionnel).${RESET}"
        echo -e "Il sera néanmoins obligatoire pour pouvoir envoyer des rapports ${UNDERLINE}par email.${RESET}"
        echo
        read -rp "Voulez-vous installer msmtp ? (y/N) : " yn
        case "$yn" in
            [Yy]*)
                echo "Installation de msmtp..."
                if [ "$(id -u)" -eq 0 ] || $SUDO apt update && $SUDO apt install -y msmtp; then
                    echo -e "${GREEN}✅  msmtp installé.${RESET}"
                else
                    echo -e "${YELLOW}⚠️  Échec installation msmtp, ce n'est pas bloquant.${RESET}"
                fi
                ;;
            *) echo "👉  msmtp ne sera pas installé (optionnel)." ;;
        esac
    else
        local local_version
        local_version=$(msmtp --version | head -n1 | awk '{print $2}')
        echo -e "✔️  msmtp détecté. Réputé : ${ITALIC}à jour${RESET}."
    fi
}

# --------------------------------------------------------------------------- #
# Vérification et installation/mise à jour de micro (éditeur)
# --------------------------------------------------------------------------- #
check_micro() {
    if ! command -v micro &>/dev/null; then
        echo -e "⚠️  ${YELLOW}Le composant ${UNDERLINE}micro${RESET}${YELLOW} non détecté (éditeur ${BOLD}optionnel${RESET}${YELLOW}).${RESET}"
        echo -e "Il s'agit d'une alternative plus fournie à l'éditeur ${BOLD}nano${RESET}."
        echo
        read -rp "Voulez-vous installer micro ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_micro ;;
            *) echo "👉  micro (optionnel) ne sera pas installé." ;;
        esac
    else
        # Récupération version locale (extrait uniquement le numéro principal)
        local local_version latest_version
        local_version=$(micro --version 2>/dev/null | head -n1 | grep -oP '\d+(\.\d+)+')
        latest_version=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest \
                          | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')

        if [ -z "$latest_version" ]; then
            echo -e "${YELLOW}⚠️  Impossible de récupérer la dernière version de micro.${RESET}"
            return
        fi

        echo -e "✔️  micro détecté. Réputé : ${ITALIC}à jour${RESET}."

        # Comparaison versions
        if [ "$local_version" != "$latest_version" ]; then
            echo "ℹ️  Nouvelle version de micro disponible : $latest_version"
            echo
            read -rp "Voulez-vous mettre à jour micro ? (y/N) : " yn
            case "$yn" in
                [Yy]*) install_micro "$latest_version" ;;
                *) echo "👉  Vous gardez la version existante." ;;
            esac
        fi
    fi
}

install_micro() {
    local version="${1:-latest}"
    echo "📦  Installation / mise à jour de micro..."

    # Déterminer la dernière version si "latest"
    if [ "$version" = "latest" ]; then
        version=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest \
                  | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
        if [ -z "$version" ]; then
            echo -e "${RED}❌  Impossible de récupérer la dernière version de micro.${RESET}"
            return 1
        fi
    fi

    # Détection architecture
    local arch micro_arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) micro_arch="linux64" ;;
        aarch64) micro_arch="linux-arm64" ;;
        armv7l) micro_arch="linux-arm" ;;
        *) echo -e "${RED}❌  Architecture $arch non supportée.${RESET}"; return 1 ;;
    esac

    # Téléchargement binaire
    local archive="micro-${version}-${micro_arch}.tar.gz"
    local url="https://github.com/zyedidia/micro/releases/download/v${version}/${archive}"

    curl -L -o "$archive" "$url" || { echo -e "${RED}❌  Échec du téléchargement.${RESET}"; return 1; }
    tar -xzf "$archive" || { echo -e "${RED}❌  Échec de l'extraction.${RESET}"; return 1; }

    if [ -w "/usr/local/bin" ]; then
        cp "micro-${version}/micro" /usr/local/bin/ || return 1
    else
        $SUDO cp "micro-${version}/micro" /usr/local/bin/ || return 1
    fi
    chmod +x /usr/local/bin/micro

    rm -rf "micro-${version}" "$archive"
    echo -e "✅  micro installé/mis à jour avec succès (version $version)."

    # Proposer de définir comme éditeur par défaut
    if command -v micro >/dev/null 2>&1; then
        echo
        read -rp "Souhaitez-vous utiliser micro comme éditeur par défaut ? (y/N) : " yn
        case "$yn" in
            [Yy]*) update_editor_choice "micro" ;;
            *)     update_editor_choice "nano"  ;;
        esac
    fi
}

update_editor_choice() {
    local new_editor="$1"
    local files=(
        "$INSTALL_DIR/config/global.conf"
        "$INSTALL_DIR/exmples_files/config.main.txt"
        "$INSTALL_DIR/local/config.local.conf"
    )

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            if grep -q '^EDITOR=' "$f"; then
                sed -i "s|^EDITOR=.*|EDITOR=$new_editor|" "$f"
            else
                echo "EDITOR=$new_editor" >> "$f"
            fi
            echo "✔ $f mis à jour → EDITOR=$new_editor"
        else
            echo "ℹ $f absent, ignoré."
        fi
    done

    echo -e "✔️  Éditeur par défaut mis à jour : $new_editor"
}


# --------------------------------------------------------------------------- #
# Récupération dernière release GitHub
# --------------------------------------------------------------------------- #
get_latest_release() {
    LATEST_TAG=$(curl -s "$GITHUB_API_URL" | grep '"tag_name":' | cut -d'"' -f4)
    LATEST_DATE=$(curl -s "$GITHUB_API_URL" | grep '"published_at":' | cut -d'"' -f4 | cut -d'T' -f1)
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${RED}Impossible de récupérer la dernière release.${RESET}"
        exit 1
    fi
    echo -e "ℹ️  Script ${BOLD}rclone_homlab${RESET} - ${UNDERLINE}Dernière release${RESET} : $LATEST_TAG ${ITALIC}($LATEST_DATE)${RESET}"
}

# --------------------------------------------------------------------------- #
# Gestion d'un répertoire existant
# --------------------------------------------------------------------------- #
handle_existing_dir() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # Dossier Git existant
        echo -e "${YELLOW}Le répertoire ${BOLD}$INSTALL_DIR${RESET}${YELLOW} contient un dépôt Git.${RESET}"
        get_installed_release
        echo
        echo "Que voulez-vous faire ?"
        echo "  [1] Supprimer et réinstaller la dernière release"
        echo "  [2] Mettre à jour vers la dernière release"
        echo "  [3] Ne rien faire et quitter"
        echo
        read -rp "Choix (1/2/3) : " choice
        case "$choice" in
            1)
                $SUDO rm -rf "$INSTALL_DIR"
                ;;
            2)
                cd "$INSTALL_DIR" || exit 1
                git fetch --tags
                git checkout -q "$LATEST_TAG" || {
                    echo -e "${RED}Impossible de passer sur $LATEST_TAG${RESET}"
                    exit 1
                }
                echo "✅  Mise à jour vers $LATEST_TAG réussie !"
                exit 0
                ;;
            3|*)
                echo "Abandon. Ciao"
                exit 0
                ;;
        esac

    elif [[ -f "$VERSION_FILE" ]]; then
        # Installation minimale avec .version
        update_minimal_if_needed

    else
        # Cas singulier : dossier existant mais ni .git ni .version
        echo -e "${RED}⚠️  Le répertoire $INSTALL_DIR existe mais semble incomplet ou corrompu.${RESET}"
        echo "Que voulez-vous faire ?"
        echo "  [1] Supprimer le contenu et installer depuis la dernière release"
        echo "  [2] Installer 'par-dessus' le contenu existant (risque de conflits)"
        echo "  [3] Ne rien faire et quitter"
        echo
        read -rp "Choix (1/2/3) : " choice
        case "$choice" in
            1)
                $SUDO rm -rf "$INSTALL_DIR"
                install_minimal "$LATEST_TAG"
                ;;
            2)
                echo "ℹ️  Installation par-dessus existant..."
                install_minimal "$LATEST_TAG"
                ;;
            3|*)
                echo "Abandon. Ciao"
                exit 0
                ;;
        esac
    fi
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

# --------------------------------------------------------------------------- #
# Installation minimale depuis une release
# --------------------------------------------------------------------------- #
install_minimal() {
    local tag="$1"
    echo -e "📦  Installation minimale de RCLONE_HOMELAB - tag : $tag"
    create_local_dir

    # --- Backup si des fichiers existent déjà ---
    if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        local backup_dir="${INSTALL_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
        echo "⚠️  Des fichiers existent déjà dans $INSTALL_DIR. Création d'un backup : $backup_dir"
        mkdir -p "$backup_dir"
        mv "$INSTALL_DIR"/* "$backup_dir"/
        echo "✅  Backup créé : $backup_dir"
    fi

    # Téléchargement de la release ZIP
    local zip_url="https://github.com/Gotcha26/rclone_homelab/archive/refs/tags/${tag}.zip"
    local zip_file="$INSTALL_DIR/release.zip"
    curl -L -o "$zip_file" "$zip_url" || { echo -e "${RED}❌  Échec téléchargement release.${RESET}"; exit 1; }

    # Extraction
    unzip -o "$zip_file" -d "$INSTALL_DIR"
    rm -f "$zip_file"

    # Déplacement fichiers extraits à la racine
    mv "$INSTALL_DIR/rclone_homelab-${tag}"/* "$INSTALL_DIR"/
    rmdir "$INSTALL_DIR/rclone_homelab-${tag}" || true

    # Création fichier version
    write_version_file "$tag"

    # Permissions
    chmod +x "$INSTALL_DIR/main.sh"

    echo -e "${GREEN}✅  Installation minimale terminée - tag $tag${RESET}"
}

# --------------------------------------------------------------------------- #
# Mise à jour minimale si .version présente
# --------------------------------------------------------------------------- #
update_minimal_if_needed() {
    local installed_tag
    installed_tag=$(read_version_file)

    if [[ -z "$installed_tag" ]]; then
        echo -e "${YELLOW}⚠️ Version inconnue installée.${RESET}"
        return 1
    fi

    if [[ "$installed_tag" == "$LATEST_TAG" ]]; then
        echo "✅  Installation déjà à jour (tag $installed_tag)"
    else
        echo "ℹ️  Mise à jour disponible : $installed_tag → $LATEST_TAG"
        echo
        read -rp "Voulez-vous mettre à jour vers $LATEST_TAG ? (y/N) : " yn
        if [[ "$yn" =~ ^[Yy] ]]; then
            install_minimal "$LATEST_TAG"
        else
            echo "ℹ️  Mise à jour annulée"
        fi
    fi
}

# --------------------------------------------------------------------------- #
# Gestion du mode dev : clone Git complet d'une branche
# --------------------------------------------------------------------------- #
install_dev_branch() {
    local branch="$1"
    echo -e "📦  Mode développement - Installation via clone Git complet de la branche $branch"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    git clone --branch "$branch" --single-branch "$REPO_URL" "$INSTALL_DIR" || {
        echo -e "${RED}❌  Échec clone de la branche $branch${RESET}"; exit 1
    }
    cd "$INSTALL_DIR" || exit
    git fetch --tags
    chmod +x main.sh
    echo -e "${GREEN}✅  Clone complet branch $branch terminé${RESET}"
}

# --------------------------------------------------------------------------- #
# Installation principale
# --------------------------------------------------------------------------- #
install_old() {
    echo -e "📦  Installation de ${BOLD}rclone_homelab${RESET} sur le dernier tag de main..."

    # Création du dossier si nécessaire
    if [ ! -d "$INSTALL_DIR" ]; then
        if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
            echo "📂  Dossier $INSTALL_DIR créé."
        else
            $SUDO mkdir -p "$INSTALL_DIR" || { echo "❌  Impossible de créer $INSTALL_DIR"; exit 1; }
        fi
    fi

    # Nettoyage avant clone
    rm -rf "$INSTALL_DIR"/*

    # Vérifier droits écriture
    if [ ! -w "$INSTALL_DIR" ]; then
        $SUDO chown "$(whoami)" "$INSTALL_DIR" || { echo "❌  Impossible de prendre possession de $INSTALL_DIR"; exit 1; }
    fi

    cd "$INSTALL_DIR" || exit 1

    echo "⏬ Clone complet du dépôt..."
    git -c advice.detachedHead=false clone --branch main "$REPO_URL" "$INSTALL_DIR" || {
        echo "❌  Clone échoué."
        exit 1
    }

    cd "$INSTALL_DIR" || exit 1

    # Récupérer tous les tags
    git fetch --tags || { echo "❌  Échec fetch tags"; exit 1; }

    # Déterminer le dernier tag sur la branche main
    LATEST_TAG=$(git tag --merged main | sort -V | tail -n1)
    if [[ -z "$LATEST_TAG" ]]; then
        echo "⚠️  Aucun tag trouvé sur la branche main. On restera sur main."
        LATEST_TAG="main"
    else
        echo "🏷️  Dernier tag de main : $LATEST_TAG"
    fi

    # Checkout sur le dernier tag
    if git show-ref --verify --quiet refs/heads/main; then
        echo "⚠️  La branche 'main' existe déjà, on la positionne sur $LATEST_TAG"
        git checkout main || { echo "❌  Impossible de checkout main"; exit 1; }
        git reset --hard "$LATEST_TAG" || { echo "❌  Impossible de reset main sur $LATEST_TAG"; exit 1; }
    else
        git checkout -b main "$LATEST_TAG" || { echo "❌  Impossible de créer main sur $LATEST_TAG"; exit 1; }
    fi

    echo -e "✅  Branche locale 'main' positionnée sur $LATEST_TAG."

    # Rendre le script exécutable
    chmod +x main.sh
    echo -e "✅  chmod appliqué sur ${BOLD}'main.sh'${RESET}. Script exécutable."
}

# --------------------------------------------------------------------------- #
# Création symlink principal
# --------------------------------------------------------------------------- #
create_symlinks() {
    SYMLINK="/usr/local/bin/rclone_homelab"
    if [ -w "$(dirname "$SYMLINK")" ]; then
        ln -sf "$INSTALL_DIR/main.sh" "$SYMLINK"
    else
        $SUDO ln -sf "$INSTALL_DIR/main.sh" "$SYMLINK"
    fi
    echo "✅  Symlink créé : $SYMLINK → $INSTALL_DIR/main.sh"
}

# --------------------------------------------------------------------------- #
# Création symlink updater
# --------------------------------------------------------------------------- #
create_updater_symlink() {
    UPDATER_SCRIPT="$INSTALL_DIR/update/standalone_updater.sh"
    UPDATER_SYMLINK="/usr/local/bin/rclone_homelab-updater"

    if [ -f "$UPDATER_SCRIPT" ]; then
        chmod +x "$UPDATER_SCRIPT"
        echo -e "✅  chmod appliqué sur ${BOLD}'UPDATER_SCRIPT'${RESET}. Script dorénavant exécutable."
        if [ -w "$(dirname "$UPDATER_SYMLINK")" ]; then
            ln -sf "$UPDATER_SCRIPT" "$UPDATER_SYMLINK"
        else
            $SUDO ln -sf "$UPDATER_SCRIPT" "$UPDATER_SYMLINK"
        fi
        echo "✅  Updater exécutable et symlink créé : $UPDATER_SYMLINK → $UPDATER_SCRIPT"
    else
        echo -e "⚠️  ${YELLOW}Fichier ${BOLD}$UPDATER_SCRIPT${RESET}${YELLOW} introuvable.${RESET}"
    fi
}

# --------------------------------------------------------------------------- #
# Execution principale
# --------------------------------------------------------------------------- #
main() {
    check_dependencies
    check_rclone
    check_msmtp
    check_micro
    get_latest_release

    if [[ "$FORCED" == "--force" ]]; then
        # Mode dev / clone Git complet
        install_dev_branch "$FORCED_BRANCH"

    elif [[ -d "$INSTALL_DIR" ]]; then
        # Dossier existant → gestion détaillée selon contenu
        handle_existing_dir

    else
        # Cas classique : dossier absent → installation minimale
        install_minimal "$LATEST_TAG"
    fi

    # Création des symlinks (dans tous les cas)
    create_symlinks
    create_updater_symlink

    echo
    echo -e "${GREEN}🎉 Installation terminée.${RESET}"
    echo -e "Pour lancer : $INSTALL_DIR/main.sh ou via le symlink ${BLUE}rclone_homelab${RESET}"
    echo
}

main "$@"
exit 0




# =========================================================================== #
# Notes
# =========================================================================== #

# Les variables définies içi n'influent en rien le script une fois installé.
# Installation toujours basée sur le dernier tag (release).
# Prise en compte du root.

# Fichier /update/standalone_updater.sh est rendu exécutable avec son symlink
# rclone_homelab-updater <--force>

# Ce fichier permet de mettre à jours le script (basé sur la branche main + release)
# mais aussi les script optionnels !

# Lien à communiquer pour l'installation :
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh)

# Pour les utilisateur aguerris (moi) :
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh) --force dev