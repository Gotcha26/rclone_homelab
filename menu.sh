#!/usr/bin/env bash

first_time=true
DISPLAY_MODE=simplified        # <verbose|simplified|none>
                               # Utilisé pour l'affichage d'infos lors des MAJ
VARS_TO_VALIDATE+=("DISPLAY_MODE:none|simplified|verbose:simplified")

# === Initialisation minimale ===

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/config/global.conf"
source "$SCRIPT_DIR/functions/debug.sh"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/core.sh"
source "$SCRIPT_DIR/update/updater.sh"

# Surchage via configuration local
load_optional_configs

# ===

# sourcing spécifique pour le menu
source "$SCRIPT_DIR/functions/menu_f.sh"

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################

while true; do

    # Réaffichage de la bannière mais jamais au premier passage.
    if [ "$first_time" = false ]; then
        print_logo   # ta bannière
    fi
    first_time=false
    
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
    if check_jobs_file soft; then
        add_option "🔂  Lancer tous les jobs (sans plus attendre ni options)" "menu_run_all_jobs"
    fi

    # 3) Configurations
    # Jobs
    if check_jobs_file soft; then
        add_option "✏️  Éditer la liste des jobs (rclone)" "menu_jobs"
    else
        add_option "⌨️  Configurer la liste des jobs (rclone)" "menu_jobs"
    fi
    # rclone
    if ! check_rclone_installed soft >/dev/null 2>&1; then
        # Cas 1 : rclone absent
        add_option "📦  Installer rclone" "menu_install_rclone"
    else
        # Mode "soft" pour le menu : pas de die
        if ! check_rclone_configured soft >/dev/null 2>&1; then
            # Cas 2 : rclone présent → vérifier la config
            add_option "⚙️  Configurer rclone" "menu_config_rclone"
        else
            # Config OK ou vide
            add_option "✏️  Éditer la configuration rclone" "menu_show_rclone_config"
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
            add_option "✏️  Éditer la configuration msmtp" "menu_show_msmtp_config"
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
    # Option de configuration locale
    if ! check_config_local soft >/dev/null 2>&1; then
        add_option "💻  Installer une configuration locale" "menu_init_config_local"
    else
        add_option "✏️  Éditer la configuration locale - vos réglages personnels" "menu_edit_config_local"
    fi
    # Propose l'édition de configuration locale pour dev seulement si présente
    if check_config_dev soft >/dev/null 2>&1; then
        add_option "✏️  Éditer la configuration locale - orienté développeurs" "menu_edit_config_dev"
    fi
    # Option pour installer/editer un fichier secrets.env
    if ! check_secrets_conf soft >/dev/null 2>&1; then
        add_option "💻  Installer un fichier secrets.env pour vos mdp / tockens (optionnel)" "menu_add_secrets_file"
    else
        add_option "✏️  Éditer la configuration secrète" "menu_edit_config_secrets"
    fi

    # 5) Choix permanents

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
                    --raw "Relancer le script pour appliquer la mise à jour !")
                printf "%b\n" "$label"
                echo
                exit 99
                ;;
            menu_update_to_latest_branch)
                update_to_latest_branch
                label=$(print_fancy --theme "follow" --bg "white" --fg "red" \
                    --style "bold italic underline" --align "center" --highlight \
                    --raw "Relancer le script pour appliquer la mise à jour !")
                printf "%b\n" "$label"
                echo
                exit 99
                ;;
            menu_run_all_jobs)
                # On quitte la boucle, on quitte le sous-shell, pour renir à l'exécution normale de main.sh
                break
                ;;
            menu_jobs)
                scroll_down
                echo "▶️  Edition de la liste des jobs pour rclone."
                if ! init_jobs_file; then
                    echo "❌  Impossible de créer $DIR_JOBS_FILE, édition annulée."
                    continue
                fi
                echo "▶️  Ouverture de $JOBS_FILE..."
                nano "$DIR_JOBS_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_install_rclone)
                scroll_down
                echo "▶️  Installation de rclone..."
                if install_rclone soft; then
                    echo "✅  ... rclone a été installé avec succès !"
                else
                    echo "⚠️  ... Échec de l'installation de rclone (mode soft)."
                fi
                ;;
            menu_show_rclone_config)
                scroll_down
                # Détecte le fichier configuré
                if conf_file=$(check_rclone_configured 2>/dev/null); then
                    echo -e "▶️  Affichage du fichier de configuration rclone : ${GREEN}$conf_file${RESET}"
                    # Utilisation de nano pour visualiser/éditer sans polluer le log
                    nano "$conf_file"
                    echo "✅  ... Édition terminée > retour au menu."
                else
                    echo "⚠️  Aucun fichier de configuration rclone trouvé."
                fi
                ;;
            menu_config_rclone)
                scroll_down
                echo "▶️  Lancement de la configuration rclone..."
                rclone config
                echo "✅  ... Configuration terminée > retour au menu."
                ;;
            menu_install_msmtp)
                scroll_down
                echo "▶️  Installation de msmtp..."
                if install_msntp soft; then
                    echo "✅  ... msmtp a été installé avec succès !"
                else
                    echo "⚠️  ... Échec de l'installation de msmtp (mode soft)."
                fi
                ;;
            menu_show_msmtp_config)
                scroll_down
                # Détecte le fichier configuré
                if conf_file=$(check_msmtp_configured 2>/dev/null); then
                    echo "▶️  Affichage du fichier de configuration msmtp : $conf_file"
                    # Utilisation de nano pour visualiser/éditer sans polluer le log
                    nano "$conf_file"
                    echo "✅  ... Édition terminée > retour au menu."
                else
                    echo "⚠️  Aucun fichier de configuration msmtp trouvé."
                fi
                ;;
            menu_config_msmtp)
                scroll_down
                echo "▶️  Lancement de la configuration msmtp..."
                edit_msmtp_config
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_show_last_log)
                echo "▶️  Affichage des 500 dernières lignes de $LAST_LOG_FILE..."
                # Utilisation d'un pager pour ne pas polluer le log principal
                tail -n 500 "$LAST_LOG_FILE" | less -R
                echo "✅  ... Fin de l'affichage > retour au menu."
                ;;
            menu_init_config_local)
                scroll_down
                echo "▶️  Installation la configuration locale."
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_config_local
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_config_local)
                scroll_down
                echo "▶️  Édition du fichiers $CONF_LOCAL_FILE"
                nano "$DIR_CONF_LOCAL"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_edit_config_dev)
                scroll_down
                echo "▶️  Édition du fichiers $CONF_DEV_FILE"
                nano "$DIR_CONF_DEV_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_add_secrets_file)
                scroll_down
                echo "▶️  Installation d'un fichier $SECRET_FILE (optionnel)."
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_secrets_local
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_config_secrets)
                scroll_down
                echo "▶️  Édition du fichiers $SECRET_FILE"
                nano "$SECRET_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_show_help)
                scroll_down
                show_help
                ;;
            menu_exit_script)
                exit 99
                ;;
            *)
                scroll_down
                echo "Choix invalide."
                ;;
        esac
    else
        scroll_down
        echo "Choix invalide."
    fi
done