#!/usr/bin/env bash

DISPLAY_MODE=none

# === Initialisation minimale ===

ERROR_CODE=0
EXECUTED_JOBS=0

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/config/global.conf"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/core.sh"
source "$SCRIPT_DIR/update/updater.sh"

# Initialise (sourcing) et informe de la branch en cours utilisée
# (basé sur la seule présence du fichier config/config.xxx.sh)
detect_config

# ===

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################

while true; do
    
    MISSING_RCLONE=false
    MISSING_MSMTP=false

    command -v rclone >/dev/null 2>&1 || MISSING_RCLONE=true
    command -v msmtp >/dev/null 2>&1 || MISSING_MSMTP=true

    # --- Plan de construction dynamique du menu ---
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # --- Fonction pour ajouter des options ---
    add_option() {
        MENU_OPTIONS+=("$1")
        MENU_ACTIONS+=("$2")
    }
    # Construction nécessaire pour l'affichage des MAJ (branche / release)
    fetch_git_info || { echo "⚠️  Impossible de récupérer l'état Git"; continue; }
    update_status_code=$(analyze_update_status)

    # === Options transmises à la fonciton précédente pour une mises à jour dynamiques ===

    # --- Options de configuration ---

    # 1) MAJ
    # Branche main
    if [[ "$branch_real" == "main" ]]; then
        if (( latest_tag_epoch > head_epoch )); then
            label=$(print_fancy --fg "blue" "↗️  Mettre à jour vers la dernière release (tag)")
            add_option "$label" "menu_update_to_latest_tag"
        fi
    else
        # Branche dev ou expérimentale
        if (( head_epoch < remote_epoch )); then
            label=$(print_fancy --fg "blue" "↗️  Mettre à jour la branche '$branch_real' (force branch)")
            add_option "$label" "menu_update_to_latest_branch"
        fi
    fi

    # 2) Jobs (lancement)
    if check_jobs_configured; then
        add_option "🔂  Lancer tous les jobs (sans plus attendre ni options)" "menu_run_all_jobs"
    fi

    # 3) Configurations
    # Jobs
    add_option "⌨️  Afficher/éditer des remotes" "menu_jobs"
    # rclone
    if ! command -v rclone >/dev/null 2>&1; then
        # Cas 1 : rclone absent
        add_option "📦  Installer rclone" "menu_install_rclone"
    else
        # Cas 2 : rclone présent → vérifier la config
        if ! check_rclone_configured >/dev/null 2>&1; then
            # Config absente ou vide
            add_option "🤖  Configurer rclone" "menu_config_rclone"
        else
            # Config OK
            add_option "📄  Afficher/éditer la configuration rclone" "menu_show_rclone_config"
        fi
    fi
    # msmtp
    if ! command -v msmtp >/dev/null 2>&1; then
        # Cas 1 : msmtp absent → proposer l'installation
        add_option "📦  Installer msmtp" "menu_install_msmtp"
    else
        # Cas 2 : msmtp présent → vérifier la configuration
        if conf_file=$(check_msmtp_configured 2>/dev/null); then
            # Fichier valide trouvé → afficher/éditer
            add_option "📄  Afficher/éditer la configuration msmtp" "menu_show_msmtp_config"
        else
            # Aucun fichier valide → configurer
            add_option "⚙️  Configurer msmtp" "menu_config_msmtp"
        fi
    fi
    # Affichage du log précédent
    LAST_LOG_FILE=$(get_last_log)
    if [[ -n "$LAST_LOG_FILE" && -f "$LAST_LOG_FILE" ]]; then
        add_option "💾  Afficher les logs du dernier run (touche q pour quitter !!!)" "menu_show_last_log"
    fi

    # 4) Actions
    # Options de configuration locale
    if [[ ! -f "$DIR_FILE_CONF_LOCAL" || ! -f "$DIR_FILE_CONF_DEV" ]]; then
        add_option "💻  Installer une configuration locale" "menu_init_config_local"
    fi

    #Option d'édition direct du fichier de configuration local/dev
    if [[ -f "$DIR_FILE_CONF_LOCAL" || -f "$DIR_FILE_CONF_DEV" ]]; then
        add_option "✏️  Éditer la configuration locale" "menu_edit_config_local"
    fi

    # Choix permanents
    add_option "📖  Afficher l'aide" "menu_show_help"
    add_option "👋  Quitter" "menu_exit_script"

    # === Affichage du menu ===

    echo
    print_fancy --align "center" "======================================="
    print_fancy --align "center" "🚀  Rclone Homelab Manager"
    print_fancy --align "center" "======================================="
    echo

    # --- Affichage des options ---
    for i in "${!MENU_OPTIONS[@]}"; do
        echo "$((i+1))) ${MENU_OPTIONS[$i]}"
    done
    echo
    read -e -rp "Votre choix [1-${#MENU_OPTIONS[@]}] : " choice </dev/tty

    # --- Validation et exécution ---
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#MENU_OPTIONS[@]} )); then
        action="${MENU_ACTIONS[$((choice-1))]}"
        case "$action" in
            menu_update_to_latest_tag)
                update_to_latest_tag
                label=$(print_fancy --theme "follow" --bg "white" --fg "red" \
                    --style "bold italic underline" --align "center" --highlight \
                    --raw "Vous devez RELANCER LE SCRIPT pour terminer appliquer la mise à jour !")
                printf "%b\n" "$label"
                echo
                exit 0
                ;;
            menu_update_to_latest_branch)
                update_to_latest_branch
                label=$(print_fancy --theme "follow" --bg "white" --fg "red" \
                    --style "bold italic underline" --align "center" --highlight \
                    --raw "Vous devez RELANCER LE SCRIPT pour terminer appliquer la mise à jour !")
                printf "%b\n" "$label"
                echo
                exit 0
                ;;
            menu_run_all_jobs)
                # On quitte la boucle pour renir à l'exacution normale de main.sh
                break
                ;;
            menu_jobs)
                if ! init_jobs_file; then
                    echo "❌  Impossible de créer "$DIR_JOBS_FILE", édition annulée."
                    break
                fi
                echo "▶️  Ouverture de $JOBS_FILE..."
                # Lancement de nano dans un shell indépendant
                nano "$DIR_JOBS_FILE"
                echo "✅  ... Édition terminée : retour au menu."
                ;;
            menu_install_rclone)
                install_rclone
                ;;
            menu_config_rclone)
                echo "▶️  Lancement de la configuration rclone..."
                rclone config
                echo "✅  ... Configuration terminée : retour au menu."
                ;;
            menu_show_rclone_config)
                echo "▶️  Ouverture de $RCLONE_CONF..."
                nano "$RCLONE_CONF"
                echo "✅  ... Édition terminée : retour au menu."
                ;;
            menu_install_msmtp)
                echo "▶️  Installation de msmtp..."
                install_msmtp
                echo "✅  ... Installation terminée : retour au menu."
                ;;
            menu_show_msmtp_config)
                # Détecte le fichier configuré
                if conf_file=$(check_msmtp_configured 2>/dev/null); then
                    echo "▶️ Affichage du fichier de configuration msmtp : $conf_file"
                    # Utilisation de nano pour visualiser/éditer sans polluer le log
                    nano "$conf_file"
                    echo "✅  ... Fin de l'affichage : retour au menu."
                else
                    echo "⚠️  Aucun fichier de configuration msmtp trouvé."
                fi
                ;;
            menu_config_msmtp)
                echo "▶️  Lancement de la configuration msmtp..."
                # Utilise la variable MSMTPRC si définie, sinon ~/msmtprc
                conf_file="${MSMTPRC:-$HOME/.msmtprc}"
                # Ouverture dans nano directement, sans polluer le log
                nano "$conf_file"
                echo "✅ ... Configuration terminée : retour au menu."
                ;;
            menu_show_last_log)
                echo "▶️  Affichage des 500 dernières lignes de $LAST_LOG_FILE..."
                # Utilisation d'un pager pour ne pas polluer le log principal
                tail -n 500 "$LAST_LOG_FILE" | less -R
                echo "✅ ... Fin de l'affichage : retour au menu."
                ;;
            menu_init_config_local)
                echo "▶️  Installation de la configuration locale."
                echo "Ces fichiers sont préservés lors des mises à jours automatiques."
                init_config_local
                ;;
            menu_edit_config_local)
                echo "▶️  Édition des fichiers de configuration locaux/dev existants"
                edit_config_local
                ;;
            menu_show_help)
                show_help
                ;;
            menu_exit_script)
                echo "👋  Bonne journée à vous. 👋"
                echo
                exit 0
                ;;
            *)
                echo "Choix invalide."
                ;;
        esac
    else
        echo "Choix invalide."
    fi
done
