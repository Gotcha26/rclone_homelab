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

set -uo pipefail

clear
echo "+==============================================================================+"
echo "|            Installateur GIT pour projet RCLONE_HOMELAB par Gotcha            |"
echo "+==============================================================================+"
echo


# =========================================================================== #
#           Installateur GIT pour projet RCLONE_HOMELAB par Gotcha            #
# =========================================================================== #

REPO_URL="https://github.com/Gotcha26/rclone_homelab.git"
INSTALL_DIR="/opt/rclone_homelab"
LOCAL_DIR="$INSTALL_DIR/local"
VERSION_FILE="$LOCAL_DIR/.version"
GITHUB_API_URL="https://api.github.com/repos/Gotcha26/rclone_homelab/releases/latest"
SAFE_EXEC_EXIT_ON_FAIL=true

# --- Argument pour mode dev ---
FORCED=""
FORCED_BRANCH="main"

if [[ "${1:-}" == "--force" ]]; then
    FORCED="--force"
    FORCED_BRANCH="${2:-main}"
fi
# ---

installed_tag="${installed_tag:-}"
LATEST_TAG="${LATEST_TAG:-}"

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
    safe_exec "✅  Dossier $LOCAL_DIR créé." \
              "❌  Impossible de créer ${BOLD}$LOCAL_DIR${RESET}" \
              mkdir -p "$LOCAL_DIR"
}

write_version_file() {
    local tag="$1"
    echo "$tag" > "$VERSION_FILE"
}

read_version_file() {
    [[ -f "$VERSION_FILE" ]] && cat "$VERSION_FILE" || echo ""
}

# --------------------------------------------------------------------------- #
# Vérification des dépendances
# --------------------------------------------------------------------------- #
check_dependencies() {
    echo ""
    echo -e "📦  Contrôle des dépendances..."
    local deps=(git curl unzip perl jq)
    local missing=()

    # Vérifie toutes les dépendances
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    # Installer les dépendances manquantes automatiquement
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "⚠️  Dépendances manquantes : ${YELLOW}${missing[*]}${RESET}"
        echo "Installation automatique..."
        safe_exec "✅ apt update OK" \
                  "❌ apt update échoué" \
                  apt update
        
        safe_exec "✅ Dépendances installées." \
                  "❌ Impossible d’installer..." \
                  apt install -y "${missing[@]}"

    else
        echo -e "✅  Toutes les dépendances sont présentes."
    fi
}


# --------------------------------------------------------------------------- #
# Vérification et installation de rclone
# --------------------------------------------------------------------------- #
check_rclone() {
    local local_version latest_version yn
    echo ""
    echo "📦  Contrôle de la présence de rclone..."

    if ! command -v rclone &>/dev/null; then
        echo -e "⚠️  ${RED}L'outil ${UNDERLINE}rclone${RESET}${RED} n'est pas encore installé, il est ${BOLD}indispensable${RESET}."
        echo "Plus d'infos sur rclone : https://rclone.org/"
        echo ""
        read -rp "Voulez-vous installer rclone maintenant ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_rclone ;;
            *) echo -e "${RED}${BOLD}Impossible de continuer sans rclone.${RESET}"; exit 1 ;;
        esac
        return
    fi

    # Version locale
    local_version=$(rclone version 2>/dev/null | head -n1 | awk '{print $2}')

    # Version distante via GitHub API
    safe_exec "✅  Récupération des infos GitHub" \
              "❌  Impossible de récupérer les informations de release rclone." \
              curl -s https://api.github.com/repos/rclone/rclone/releases/latest -o /tmp/rclone_release.json

    latest_version=$(jq -r '.tag_name // empty' /tmp/rclone_release.json 2>/dev/null)
    safe_exec "✅  Nettoyage du fichier temporaire" \
              "❌  Impossible de supprimer le fichier temporaire" \
              rm -f /tmp/rclone_release.json

    # Normalisation (suppression éventuelle du "v")
    latest_version="${latest_version#v}"
    local_version="${local_version#v}"

    [ -z "$latest_version" ] && latest_version="inconnue"

    echo -e "✔️  rclone détecté."
    echo -e "📌 Version installée : ${ITALIC}${local_version}${RESET}"
    echo -e "📌 Version disponible : ${ITALIC}${latest_version}${RESET}"

    if [[ "$local_version" != "$latest_version" ]] && [[ "$latest_version" != "inconnue" ]]; then
        echo "ℹ️  Nouvelle version rclone disponible : $latest_version"
        echo ""
        read -rp "Voulez-vous mettre à jour rclone ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_rclone ;;
            *) echo "👉  Vous gardez la version existante." ;;
        esac
    fi
}

install_rclone() {
    local arch arch_tag
    echo ""
    echo "📦  Installation / mise à jour de rclone..."

    # Détection architecture
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch_tag="linux-amd64" ;;
        aarch64|arm64) arch_tag="linux-arm64" ;;
        *) echo -e "❌  Architecture $arch non supportée."; return 1 ;;
    esac

    local zip_file="rclone-current-${arch_tag}.zip"
    local url="https://downloads.rclone.org/${zip_file}"

    safe_exec "✅  Téléchargement OK" \
              "❌  Échec du téléchargement de $zip_file" \
              curl -fsSL -O "$url"

    safe_exec "✅  Fichier validé" \
              "❌  Fichier téléchargé invalide ou vide : $zip_file" \
              test -s "$zip_file"

    safe_exec "✅  Extraction OK" \
              "❌  Échec de l'extraction du zip rclone" \
              unzip -o "$zip_file"

    safe_exec "✅  Copie OK" \
              "❌  Impossible de copier rclone dans /usr/local/bin" \
              cp -f rclone-*-${arch_tag}/rclone /usr/local/bin/

    safe_exec "✅  Rendu exécutable" \
              "❌  Impossible de rendre rclone exécutable" \
              chmod +x /usr/local/bin/rclone

    safe_exec "✅  Suppression de zip." \
              "❌  Impossible de supprimer le zip." "--no-exit" \
              rm -rf rclone-*-${arch_tag} "$zip_file"

    echo "✅  rclone installé/mis à jour avec succès."
}

# --------------------------------------------------------------------------- #
# Vérification optionnelle de msmtp
# --------------------------------------------------------------------------- #
check_msmtp() {
    local local_version yn
    echo ""
    echo "📦  Contrôle de la présence de msmtp..."

    if ! command -v msmtp &>/dev/null; then
        echo -e "⚠️  ${YELLOW}Le composant ${UNDERLINE}msmtp${RESET}${YELLOW} non détecté (optionnel).${RESET}"
        echo -e "ℹ️  Il sera néanmoins obligatoire pour pouvoir envoyer des rapports ${UNDERLINE}par email.${RESET}"
        echo ""
        read -rp "Voulez-vous installer msmtp ? (y/N) : " yn
        case "$yn" in
            [Yy]*)
                echo "📥  Installation de msmtp..."
                safe_exec "✅  msmtp installé." \
                          "❗  Échec de l'installation de msmtp, ${UNDERLINE}ce n'est pas bloquant.${RESET}" "--no-exit" \
                          bash -c "$SUDO apt update && $SUDO apt install -y msmtp"
                ;;
            *) echo "👌  msmtp (optionnel) ne sera pas installé." ;;
        esac
    else
        local_version=$(msmtp --version 2>/dev/null | head -n1 | awk '{print $2}')
        echo -e "✔️  msmtp détecté. Version locale : ${ITALIC}${local_version:-inconnue}${RESET}."
    fi
}


# --------------------------------------------------------------------------- #
# Vérification et installation/mise à jour de micro (éditeur)
# --------------------------------------------------------------------------- #
check_micro() {
    local local_version latest_version yn
    echo ""
    echo "📦  Contrôle de la présence de micro..."

    if ! command -v micro &>/dev/null; then
        echo -e "⚠️  ${YELLOW}Le composant ${UNDERLINE}micro${RESET}${YELLOW} non détecté (éditeur ${BOLD}optionnel${RESET}${YELLOW}).${RESET}"
        echo -e "Il s'agit d'une alternative plus fournie à l'éditeur ${BOLD}nano${RESET}."
        echo ""
        read -rp "Voulez-vous installer micro ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_micro ;;
            *) echo "👌  micro (optionnel) ne sera pas installé." ;;
        esac
        return
    fi

    # Récupération version locale
    local_version=$(micro --version 2>/dev/null | head -n1 | grep -oP '\d+(\.\d+)+')
    [ -z "$local_version" ] && local_version="inconnue"

    # Récupération version distante
    safe_exec "✅  Récupération de la dernière version de micro" \
              "❌  Impossible de récupérer la dernière version de micro." \
              latest_version=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest \
                                 | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
    [ -z "$latest_version" ] && latest_version="inconnue"

    # Affichage final des versions
    echo -e "✔️  micro détecté."
    echo -e "📌 Version installée : ${ITALIC}${local_version}${RESET}"
    echo -e "📌 Version disponible : ${ITALIC}${latest_version}${RESET}"

    # Comparaison versions
    if [ "$local_version" != "$latest_version" ] && [ "$latest_version" != "inconnue" ]; then
        echo "ℹ️  Nouvelle version de micro disponible : $latest_version"
        echo ""
        read -rp "Voulez-vous mettre à jour micro ? (y/N) : " yn
        case "$yn" in
            [Yy]*) install_micro "$latest_version" ;;
            *) echo "👌  Vous gardez la version existante." ;;
        esac
    fi
}

install_micro() {
    local version="${1:-latest}"
    echo
    echo "📦  Installation / mise à jour de micro..."

    # Déterminer la dernière version si "latest"
    if [ "$version" = "latest" ]; then
        version=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest \
                  | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
        safe_exec "✅  Dernière version : ${BOLD}$version${RESET}" \
                  "❌  Impossible de récupérer la dernière version de micro" "--no-exit" \
                  test -n "$version"
    fi

    # Détection architecture
    local arch micro_arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) micro_arch="linux64" ;;
        aarch64) micro_arch="linux-arm64" ;;
        armv7l) micro_arch="linux-arm" ;;
        *) echo -e "❌  ${RED}Architecture $arch non supportée.${RESET}"; return 1 ;;
    esac

    # Téléchargement et extraction
    local archive="micro-${version}-${micro_arch}.tar.gz"
    local url="https://github.com/zyedidia/micro/releases/download/v${version}/${archive}"

    safe_exec "✅  Téléchargement OK" \
              "❌  Échec du téléchargement de $archive" \
              curl -fsSL -o "$archive" "$url"

    safe_exec "✅  Extraction OK" \
              "❌  Échec de l'extraction de $archive" \
              tar -xzf "$archive"

    # Installation binaire
    safe_exec "✅  Copie OK" \
              "❌  Impossible de copier micro dans /usr/local/bin" \
              cp "micro-${version}/micro" /usr/local/bin/

    safe_exec "✅  Est bien rendu exécutable" \
              "❌  Impossible de rendre micro exécutable" \
              chmod +x /usr/local/bin/micro

    safe_exec "✅  Suppression du zip." \
              "❌  Impossible de supprimer le zip" \
              rm -rf "micro-${version}" "$archive"
    
    echo -e "✅  micro installé/mis à jour avec succès (version $version)."

    # Proposer de définir comme éditeur par défaut
    if command -v micro >/dev/null 2>&1; then
        echo ""
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
        "$INSTALL_DIR/examples_files/config.main.txt"   # correction typo
        "$INSTALL_DIR/local/config.local.conf"
    )

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            if grep -q '^EDITOR=' "$f"; then
                safe_exec "✅  Mise à jour des préférences" \
                          "❌  Impossible de mettre à jour $f" \
                          sed -i "s|^EDITOR=.*|EDITOR=$new_editor|" "$f"
            else
                safe_exec "✅  Ajout de la préférence dans le fichier" \
                          "❌  Impossible d'ajouter EDITOR à $f" \
                          bash -c "echo 'EDITOR=$new_editor' >> '$f'"
            fi
            echo "✔ $f mis à jour → EDITOR=$new_editor"
        else
            echo "ℹ $f absent, ignoré."
        fi
    done

    echo -e "✔️  Éditeur par défaut mis à jour : ${BOLD}$new_editor${RESET}"
}

# --------------------------------------------------------------------------- #
# Récupération dernière release GitHub
# --------------------------------------------------------------------------- #
get_latest_release() {
    local json

    # Récupération JSON
    safe_exec "✅  Récupération d'information sur GitHub" \
              "❌  Impossible de récupérer les informations de release depuis GitHub." \
              curl -s "$GITHUB_API_URL" > >(cat) | { read -r json; }

    # Extraction directe
    LATEST_TAG=$(echo "$json" | jq -r '.tag_name')
    LATEST_DATE=$(echo "$json" | jq -r '.published_at' | cut -d'T' -f1)

    if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
        echo -e "❌  ${RED}Impossible de récupérer la dernière release.${RESET}"
        exit 1
    fi

    echo -e "ℹ️  Script ${BOLD}rclone_homelab${RESET} - \
${UNDERLINE}Dernière release${RESET} : $LATEST_TAG ${ITALIC}($LATEST_DATE)${RESET}"
}


# --------------------------------------------------------------------------- #
# Gestion d'un répertoire existant
# --------------------------------------------------------------------------- #
handle_existing_dir() {
    echo ""
    echo -e "📦  Cas 2-3/ Installation sur dossier existant détécté..."

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # Dossier Git existant
        echo ""
        echo -e "❓  ${YELLOW}Le répertoire ${BOLD}$INSTALL_DIR${RESET}${YELLOW} contient un dépôt Git.${RESET}"
        get_installed_release
        echo ""
        echo "Que voulez-vous faire ?"
        echo "  [1] Supprimer et réinstaller la dernière release"
        echo "  [2] Mettre à jour vers la dernière release"
        echo "  [3] Ne rien faire et quitter"
        echo ""
        read -rp "Choix (1/2/3) : " choice
        case "$choice" in
            1)
                safe_exec "✅  $INSTALL_DIR supprimé avec succès." \
                          "❌  Impossible de supprimer $INSTALL_DIR" \
                          rm -rf "$INSTALL_DIR"
                ;;
            2)
                safe_exec "✅  Se placer dans $INSTALL_DIR" \
                          "❌  Impossible d’entrer dans $INSTALL_DIR" \
                          cd "$INSTALL_DIR"

                safe_exec "✅  Tags récupérés." \
                          "❌  Échec fetch tags" \
                          git fetch --tags

                safe_exec "✅  Passage sur $LATEST_TAG réussi." \
                          "❌  Impossible de passer sur $LATEST_TAG" \
                          git checkout -q "$LATEST_TAG"

                echo "✅  Mise à jour vers $LATEST_TAG réussie !"
                return 0
                ;;
            3|*)
                echo "Abandon. Ciao 👋"
                exit 0
                ;;
        esac

    elif [[ -f "$VERSION_FILE" ]]; then
        # Installation minimale avec .version mais sans .git : Cas 3 
        update_minimal_if_needed

    else
        # Cas singulier : dossier existant mais ni .git ni .version : Cas 2
        # Se transforme en Cas 1 après avoir fait le choix.
        echo ""
        echo -e "📦  Cas 2/ Installation sur dossier existant détécté, incomplet/correct..."
        echo ""
        echo -e "❗  ${RED}Le répertoire $INSTALL_DIR existe mais semble incomplet ou corrompu.${RESET}"
        echo "Que voulez-vous faire ?"
        echo "  [1] Supprimer le contenu et installer depuis la dernière release"
        echo "  [2] Installer 'par-dessus' le contenu existant (risque de conflits)"
        echo "  [3] Ne rien faire et quitter"
        echo ""
        read -rp "Choix (1/2/3) : " choice
        case "$choice" in
            1)
                safe_exec "✅  $INSTALL_DIR supprimé avec succès." \
                          "❌  Impossible de supprimer $INSTALL_DIR" \
                          rm -rf "$INSTALL_DIR"

                safe_exec "✅  Installation minimale terminée." \
                          "❌  Échec installation minimale." \
                          install_minimal "$LATEST_TAG"
                ;;
            2)
                echo "ℹ️  Installation par-dessus existant..."
                safe_exec "✅  Installation minimale terminée." \
                          "❌  Échec installation minimale." \
                          install_minimal "$LATEST_TAG"
                ;;
            3|*)
                echo "Abandon. Ciao 👋"
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
            echo -e "📌 Version installée : ${ITALIC}$INSTALLED_TAG${BOLD}${ITALIC} ($INSTALLED_DATE)${RESET}."
        else
            echo -e "📌 Version installée : ${ITALIC}${BOLD}inconnue${RESET}."
        fi
        cd - >/dev/null || return
    fi
}

# --------------------------------------------------------------------------- #
# Installation minimale depuis une release
# --------------------------------------------------------------------------- #
install_minimal() {
    local tag="$1"
    echo ""
    echo -e "📦  Cas 1/ Installation minimale de ${BOLD}RCLONE_HOMELAB : $tag${RESET}"

    # Création du dossier local
    safe_exec "✅  Dossier $INSTALL_DIR prêt." \
              "❌  Impossible de créer $INSTALL_DIR" \
              bash -c create_local_dir

    # --- Backup si des fichiers existent déjà ---
    if [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        local backup_dir="${INSTALL_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
        echo "⚠️  Des fichiers existent déjà dans $INSTALL_DIR. Création d'un backup : $backup_dir"

        safe_exec "✅  Dossier backup créé : $backup_dir" \
                  "❌  Impossible de créer : $backup_dir" \
                  mkdir -p "$backup_dir"

        safe_exec "✅  Déplacement effectué avec succès : $INSTALL_DIR/* → $backup_dir" \
                  "❌  Impossible de déplacer : $INSTALL_DIR → $backup_dir" \
                  mv "$INSTALL_DIR"/* "$backup_dir"/
    fi

    # Téléchargement de la release ZIP
    local zip_url="https://github.com/Gotcha26/rclone_homelab/archive/refs/tags/${tag}.zip"
    local zip_file="$INSTALL_DIR/release.zip"

    safe_exec "✅  Téléchargement de la release terminé." \
              "❌  Échec téléchargement release" \
              curl -fsSL -O "$zip_file" "$zip_url"

    # Extraction et nettoyage
    safe_exec "✅  Extraction terminée." \
              "❌  Échec extraction release" \
              unzip -o "$zip_file" -d "$INSTALL_DIR"

    safe_exec "✅  Suppression du fichier zip OK" \
              "❌  Impossible de supprimer le fichier ZIP" \
              rm -f "$zip_file"

    # Déplacement des fichiers extraits à la racine
    local extracted_dir="$INSTALL_DIR/rclone_homelab-${tag}"
    safe_exec "✅  Déplacement OK" \
              "❌  Impossible de déplacer les fichiers extraits à la racine" \
              mv "$extracted_dir"/* "$INSTALL_DIR"/

    safe_exec "✅  Suppression OK" \
              "❌  Impossible de supprimer le dossier temporaire $extracted_dir" \
              rm -rf "$extracted_dir" || true

    # Création fichier version
    safe_exec "✅  Ecriture OK" \
              "❌  Impossible d'écrire le fichier de version" \
              write_version_file "$tag"

}

# --------------------------------------------------------------------------- #
# Mise à jour minimale si .version présente
# --------------------------------------------------------------------------- #
update_minimal_if_needed() {
    local installed_tag
    installed_tag=$(read_version_file)
    echo ""
    echo -e "📦  Cas 3/ Mise à jour minimale, si nécessaire..."

    if [[ -z "$installed_tag" ]]; then
        echo -e "${YELLOW}⚠️  Version installée : inconnue.${RESET}"
        return 1
    fi

    if [[ "$installed_tag" == "$LATEST_TAG" ]]; then
        echo "✅  Installation déjà à jour."
    else
        echo "ℹ️  Mise à jour disponible : $installed_tag → $LATEST_TAG"
        echo ""
        read -rp "Voulez-vous mettre à jour vers $LATEST_TAG ? (y/N) : " yn
        if [[ "$yn" =~ ^[Yy] ]]; then
            safe_exec "✅  Mise à jour vers $LATEST_TAG terminée." \
                      "❌  Échec de la mise à jour vers $LATEST_TAG" \
                      install_minimal "$LATEST_TAG"
        else
            echo "ℹ️  Mise à jour annulée"
        fi
    fi

    # Affichage récapitulatif des versions
    echo -e "📌 Version installée : ${ITALIC}${installed_tag}${RESET}"
    echo -e "📌 Version disponible : ${ITALIC}${LATEST_TAG}${RESET}"
}

# --------------------------------------------------------------------------- #
# Gestion du mode dev : clone Git complet d'une branche
# --------------------------------------------------------------------------- #
install_dev_branch() {
    local branch="${1:-main}"
    echo ""
    echo -e "📦  ${UNDERLINE}Mode développement${RESET} - Installation via clone Git complet de la branche ${BOLD}$branch${RESET}"
    
    # Nettoyage de l’ancien dossier
    safe_exec "✅  Nettoyage de $INSTALL_DIR effectué." \
              "❌  Impossible de supprimer $INSTALL_DIR" \
              rm -rf "$INSTALL_DIR"

    # Création du dossier
    safe_exec "✅  Dossier $INSTALL_DIR créé." \
              "❌  Impossible de créer $INSTALL_DIR" \
              mkdir -p "$INSTALL_DIR"

    # Vérifie si la branche existe côté distant
    if git ls-remote --heads "$REPO_URL" "$branch" | grep -q "refs/heads/$branch"; then
        safe_exec "✅  Clone de la branche $branch terminé." \
                  "❌  Échec clone de la branche $branch" \
                  git clone --branch "$branch" --single-branch "$REPO_URL" "$INSTALL_DIR"
    else
        echo -e "❌  ${RED}La branche '${BOLD}$branch${RESET}${RED}' n'existe pas dans le dépôt.${RESET}"
        return 1
    fi

    # --- Bloc de finalisation commun ---
    safe_exec "✅  Se placer dans $INSTALL_DIR" \
              "❌  Impossible d’entrer dans $INSTALL_DIR" \
              cd "$INSTALL_DIR"

    safe_exec "✅  Récupération des tags effectuée." \
              "❌  Échec fetch tags" \
              git fetch --tags

}

# --------------------------------------------------------------------------- #
# Installation principale
# --------------------------------------------------------------------------- #
install_old() {
    echo ""
    echo -e "📦  Installation de ${BOLD}rclone_homelab${RESET} sur le dernier tag de main..."

    # Création du dossier si nécessaire
    if [ ! -d "$INSTALL_DIR" ]; then
        safe_exec "✅  Dossier $INSTALL_DIR créé." \
                  "❌  Impossible de créer $INSTALL_DIR" \
                  mkdir -p "$INSTALL_DIR"
    fi

    # Nettoyage avant clone (supprime contenu mais garde le dossier)
    safe_exec "✅  Nettoyage de $INSTALL_DIR" \
              "❌  Impossible de nettoyer $INSTALL_DIR" \
              rm -rf "$INSTALL_DIR"/*

    # Vérifier droits écriture
    if [ ! -w "$INSTALL_DIR" ]; then
        safe_exec "✅  Droits accordés à $(whoami) sur $INSTALL_DIR" \
                  "❌  Impossible de prendre possession de $INSTALL_DIR" \
                  chown "$(whoami)" "$INSTALL_DIR"
    fi

    # Clone du dépôt directement dans $INSTALL_DIR
    safe_exec "✅  Clone complet du dépôt" \
              "❌  Clone échoué" \
              git -c advice.detachedHead=false clone --branch main "$REPO_URL" "$INSTALL_DIR"

    # Entrer dans le dépôt cloné
    safe_exec "✅  Se placer dans $INSTALL_DIR" \
              "❌  Impossible d’entrer dans $INSTALL_DIR après clone" \
              cd "$INSTALL_DIR"

    # Récupérer tous les tags
    safe_exec "✅  Récupération des tags" \
              "❌  Échec fetch tags" \
              git fetch --tags

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
        safe_exec "✅  Branche locale 'main' positionnée sur $LATEST_TAG" \
                  "❌  Impossible de checkout main" \
                  git checkout main

        safe_exec "✅  Reset main sur $LATEST_TAG" \
                  "❌  Impossible de reset main sur $LATEST_TAG" \
                  git reset --hard "$LATEST_TAG"
    else
        safe_exec "✅  Branche locale 'main' créée sur $LATEST_TAG" \
                  "❌  Impossible de créer main sur $LATEST_TAG" \
                  git checkout -b main "$LATEST_TAG"
    fi
}

# --------------------------------------------------------------------------- #
# Création des symlink
# --------------------------------------------------------------------------- #
create_symlinks() {
    echo ""
    echo "🏹  Création de symlink(s)..."

    # Tableau des couples [cible] [symlink]
    local links=(
        "$INSTALL_DIR/main.sh:/usr/local/bin/rclone_homelab"
        "$INSTALL_DIR/update/standalone_updater.sh:/usr/local/bin/rclone_homelab-updater"
    )

    for entry in "${links[@]}"; do
        local target="${entry%%:*}"
        local symlink="${entry##*:}"

        if [ ! -f "$target" ]; then
            echo -e "⚠️  ${YELLOW}Fichier ${BOLD}$target${RESET}${YELLOW} introuvable.${RESET}"
            continue
        fi

        safe_exec "✅  Symlink créé : $symlink → $target" \
                  "❌  Impossible de créer le symlink $symlink" \
                  ln -sf "$target" "$symlink"
    done
}

# --------------------------------------------------------------------------- #
# Rende les scripts exécutables
# --------------------------------------------------------------------------- #
create_executables() {
    echo ""
    echo "🏹  Rendre les scripts exécutables..."

    local files=()
    files+=("$INSTALL_DIR/main.sh")

    local UPDATER_SCRIPT="$INSTALL_DIR/update/standalone_updater.sh"
    [[ -f "$UPDATER_SCRIPT" ]] && files+=("$UPDATER_SCRIPT")

    safe_exec \
        "❌  ${BOLD}${files[*]}${RESET} : n'a pas pu être rendu exécutable." \
        "✅  ${BOLD}${files[*]}${RESET} → rendu(s) exécutable(s)." \
        chmod +x "${files[@]}"
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

    # === Choix du mode d'installation ===
    if [[ "${FORCED:-}" == "--force" ]]; then
        # Cas 4 : Mode forcé : clone complet depuis la branche demandée
        echo -e "${YELLOW}⚠️  Mode forcé demandé → branche : ${BOLD}${FORCED_BRANCH}${RESET}"
        install_dev_branch "$FORCED_BRANCH" && echo -e "${GREEN}✅  Clone complet branch $FORCED_BRANCH terminé${RESET}"

    elif [[ -d "$INSTALL_DIR" ]]; then
        # Cas 2 ou 3 : Dossier existant → gestion selon contenu (.git / .version / corrompu)
        handle_existing_dir "" echo -e "${GREEN}✅  Installation atypique terminée.${RESET}";

    else
        # Cas 1 : Dossier absent → installation minimale depuis le dernier tag
        install_minimal "$LATEST_TAG" && echo -e "${GREEN}✅  Installation minimale terminée - tag $LATEST_TAG${RESET}";
    fi

    # === Étapes communes à exécuter uniquement si l'installation a réussi ===
    # (set -e fera sauter le script si une des fonctions échoue)
    create_symlinks
    create_executables

    echo ""
    echo -e "${GREEN}🎉 Installation terminée.${RESET}"
    echo -e "Pour lancer : $INSTALL_DIR/main.sh ou via le symlink ${BLUE}rclone_homelab${RESET}"
    echo ""
}

main "$@"
exit 0

# --------------------------------------------------------------------------- #
# safe_exec : exécute une commande avec sudo si nécessaire, avec messages et 
# gestion d'erreurs flexibles.
# --------------------------------------------------------------------------- #
# Arguments :
#   $1 : message succès (optionnel)
#   $2 : message échec (optionnel, sinon message par défaut)
#   $3…$n : options (--critical|--no-exit) puis commande et ses arguments
# --------------------------------------------------------------------------- #
# Variables globales :
#   SAFE_EXEC_EXIT_ON_FAIL : si true, toutes les commandes critiques feront exit
# --------------------------------------------------------------------------- #
# Exemples d'utilisation :
# safe_exec "Dossier $INSTALL_DIR créé" "Impossible de créer $INSTALL_DIR" mkdir -p "$INSTALL_DIR"
# safe_exec "Fichiers déplacés vers $backup_dir" "" mv "$INSTALL_DIR"/* "$backup_dir"/
# safe_exec "" "" rm -rf "$INSTALL_DIR"
# safe_exec "Succès" "Échec" bash -c 'commande complexe avec > et &&'
# safe_exec "Création d'un lien" "Échec du lien" --critical ln -sf "$target" "$symlink"
# --------------------------------------------------------------------------- #

SAFE_EXEC_EXIT_ON_FAIL="${SAFE_EXEC_EXIT_ON_FAIL:-false}"

safe_exec() {
    local msg_success="$1"
    local msg_fail="$2"
    shift 2

    local critical_override=""
    # Vérifier si le prochain argument est --critical ou --no-exit
    if [[ "$1" == "--critical" || "$1" == "--no-exit" ]]; then
        critical_override="$1"
        shift
    fi

    [ -z "$msg_fail" ] && msg_fail="Échec de la commande : $*"

    local status
    if [ -n "$SUDO" ]; then
        "$SUDO" "$@"
        status=$?
    else
        "$@"
        status=$?
    fi

    if [ $status -eq 0 ]; then
        [ -n "$msg_success" ] && echo -e "✅  $msg_success"
        return 0
    else
        echo -e "${YELLOW}⚠️  ${RED}$msg_fail${RESET}"

        # Gestion de l'exit selon les règles : argument ou variable globale
        if [[ "$critical_override" == "--critical" ]]; then
            exit 1
        elif [[ "$critical_override" == "--no-exit" ]]; then
            return 1
        elif [[ "$SAFE_EXEC_EXIT_ON_FAIL" == "true" ]]; then
            exit 1
        fi

        return 1
    fi
}








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

# Pour les utilisateur aguerris (dev) :
bash <(curl -s https://raw.githubusercontent.com/Gotcha26/rclone_homelab/main/install.sh) --force dev
