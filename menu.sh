#!/usr/bin/env bash

# === Initialisation minimale ===
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
source "$SCRIPT_DIR/bootstrap.sh"

# ===

# sourcing spécifique pour le menu
source "$SCRIPT_DIR/functions/menu_f.sh"
source "$SCRIPT_DIR/functions/cron_f.sh"

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
first_time=true

while true; do

    # Réaffichage de la bannière mais jamais au premier passage.
    if [ "$first_time" = false ]; then
        load_optional_configs                        # Venir recharger la configuration locale après une édition
        if print_table_vars_invalid VARS_TO_VALIDATE; then 
            display_msg "verbose|hard" --theme success "Vérification des variables locales passées !"
        else
            display_msg "soft|verbose|hard" ""
            display_msg "soft|verbose|hard" --theme follow --fg yellow \
                "Vous êtes invité à revoir/corriger votre configuration locale."   # Affichage si nécessaire
        fi
    fi
    first_time=false
    
    MISSING_RCLONE=false
    MISSING_MSMTP=false

    command -v rclone >/dev/null 2>&1 || MISSING_RCLONE=true
    command -v msmtp >/dev/null 2>&1 || MISSING_MSMTP=true

    # --- Plan de construction dynamique du menu ---
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # Construction nécessaire pour l'affichage des MAJ (branche / release), lancement de menu.sh via bash !
    fetch_git_info
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
            label=$(print_fancy --bg "blue" "↗️  Mettre à jour depuis la branche '$branch_real' (FORCE_BRANCH)")
            add_option "$label" "menu_update_to_latest_branch"
        fi
    fi

    add_separator_if_needed

    # 2) Jobs (lancement)
    check_jobs_file
    jobs_ret=$?
    if (( jobs_ret == 0 )); then
        add_option "🔂  Lancer tous les jobs (sans plus attendre ni options)" "menu_run_all_jobs"
    fi

    add_separator_if_needed

    # 3) Configurations
    # Jobs
    case $jobs_ret in
        0)
            add_option "✏️  Éditer la liste des jobs (rclone)     → modification manuelle" "menu_edit_jobs"
            ;;
        1)
            add_option "⌨️  Configurer la liste des jobs (rclone) → fichier absent" "menu_init_jobs"
            ;;
        2)
            add_option "⚠️  Vérifier le fichier des jobs          → lecture impossible" "menu_edit_jobs"
            ;;
        3)
            add_option "✏️  Éditer la liste des jobs (rclone)     → compléter le fichier" "menu_edit_jobs"
            ;;
    esac
    # rclone
    if ! check_rclone_installed soft >/dev/null 2>&1; then
        # Cas 1 : rclone absent
        add_option "📦  Installer rclone                       → [OBLIGATOIRE]" "menu_install_rclone"
    else
        # Mode "soft" pour le menu : pas de die
        if ! check_rclone_configured soft >/dev/null 2>&1; then
            # Cas 2 : rclone présent → vérifier la config
            add_option "⚙️  Configurer rclone                     → Configuration vierge" "menu_config_rclone"
        else
            # Config OK ou vide
            add_option "✏️  Éditer la configuration rclone        → modification manuelle" "menu_show_rclone_config"
        fi
    fi
    # msmtp
    if ! command -v msmtp >/dev/null 2>&1; then
        # Cas 1 : msmtp absent → proposer l'installation
        add_option "📦  Installer msmtp                       → outil d'envoi mails [optionnel]" "menu_install_msmtp"
    else
        # Cas 2 : msmtp présent → vérifier la configuration
        if conf_file=$(check_msmtp_configured 2>/dev/null); then
            # Fichier valide trouvé → afficher/éditer
            add_option "✏️  Éditer la configuration msmtp         → modification manuelle" "menu_show_msmtp_config"
        else
            # Aucun fichier valide → configurer
            add_option "⚙️  Configurer msmtp                      → fichier à compléter" "menu_config_msmtp"
        fi
    fi

    add_separator_if_needed

    # Cron
    if command -v crontab >/dev/null 2>&1; then
        add_option "📅  Gérer le Crontab                        → tâches automatiques" "menu_cron_management"
    fi

    add_separator_if_needed

    # 4) Actions
    # Option de configuration locale
    if [[ -f "$DIR_CONF_LOCAL_FILE" ]]; then
        add_option "✏️  Éditer la configuration locale        → vos réglages personnels" "menu_edit_config_local"
    else
        add_option "💻  Installer une configuration locale    → vos réglages personnels" "menu_init_config_local"
    fi
    # Propose l'édition de configuration locale pour dev seulement si présente
    if [[ "$branch_real" != "main" && "$branch_real" != *"local-standalone-version"* ]]; then
        if [[ -f "$DIR_CONF_DEV_FILE" ]]; then
            add_option "✏️  Éditer la configuration pour dev      → orienté développeurs" "menu_edit_config_dev"
        else
            add_option "💻  Installer une configuration \"dev\"     → orienté pour les développeurs" "menu_init_config_dev"
        fi
    fi
    # Option pour installer/editer un fichier secrets.env
    if [[ -f "$DIR_SECRET_FILE" ]]; then
        add_option "✏️  Éditer la configuration secrète       → pour vos mdp/tockens [optionnel]" "menu_edit_config_secrets"
    else
        add_option "💻  Installer un fichier secrets.env      → pour vos mdp/tockens [optionnel]" "menu_init_secret_file"
    fi

    add_separator_if_needed

    # 5) Options pour la branche dev
   if [[ "$branch_real" != "main" && "$branch_real" != *"local-standalone-version"* ]]; then
        add_option "🔓  Installer  un composant               → Qui ne serait pas déjà présent..." "menu_dev_install"
        add_option "🔓  Désinstaller un composant             → Irréversible !" "menu_dev_uninstall"
    fi

    add_separator_if_needed

    # 6) Choix permanents

    add_option "📖  Afficher l'aide" "menu_show_help"

    # === Affichage du menu ===

    echo
    print_fancy --align center "======================================="
    print_fancy --align center "🚀  MENU INTERACTIF pour :"
    print_fancy --align center --style "bold|underline" "Rclone Homelab Manager"
    print_fancy --align center "======================================="
    echo

    # --- Affichage des options ---
    declare -A CHOICE_TO_INDEX=()
    num=1
    print_menu MENU_OPTIONS MENU_ACTIONS CHOICE_TO_INDEX num

    echo
    read -e -rp "Votre choix [1-$((num-1)) ou q pour quitter] : " choice </dev/tty

    # --- Validation et exécution ---
    if [[ "$choice" == "q" ]]; then
        echo
        echo "Vous partez déjà..."
        return 99
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < num )); then
        idx="${CHOICE_TO_INDEX[$choice]}"
        action="${MENU_ACTIONS[$idx]}"
        case "$action" in
            menu_update_to_latest_tag)
                update_to_latest_tag
                label=$(print_fancy --theme "follow" --bg "green" --fg "black" --style "bold italic underline" --align "center" --highlight --raw \
                "Relancer le script pour appliquer la mise à jour ! 👈")
                printf "%b\n" "$label"
                echo
                exit 99
                ;;
            menu_update_to_latest_branch)
                update_to_latest_branch
                label=$(print_fancy --theme "follow" --bg "green" --fg "black" --style "bold italic underline" --align "center" --highlight --raw \
                "Relancer le script pour appliquer la mise à jour ! 👈")
                printf "%b\n" "$label"
                echo
                exit 99
                ;;
            menu_run_all_jobs)
                # On quitte la boucle, on quitte le sous-shell, pour renir à l'exécution normale de main.sh
                break
                ;;
            menu_init_jobs)
                scroll_down
                echo "▶️  Installation du fichier des jobs pour rclone."
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_file "jobs"
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_jobs)
                scroll_down
                print_fancy "▶️  Edition du fichier :"
                print_fancy --align right --fg blue "${DIR_JOBS_FILE}"
                $EDITOR "$DIR_JOBS_FILE"
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
                conf_file="$(check_rclone_configured 2>/dev/null)"
                rc=$?
                if (( rc == 0 )); then
                    print_fancy "▶️  Affichage du fichier de configuration rclone :"
                    print_fancy --align right --fg blue "${conf_file}"
                    $EDITOR "$conf_file"
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
                    print_fancy "▶️  Affichage du fichier de configuration msmtp :"
                    print_fancy --align right --fg blue "${conf_file}"
                    $EDITOR "$conf_file"
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
            menu_init_config_local)
                scroll_down
                echo "▶️  Installation la configuration locale."
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_file "conf_local"
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_config_local)
                scroll_down
                print_fancy "▶️  Édition du fichier :"
                print_fancy --align right --fg blue "${CONF_LOCAL_FILE}"
                $EDITOR "$DIR_CONF_LOCAL_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_init_config_dev)
                scroll_down
                echo "▶️  Installation de la configuration pour développeurs."
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_file "conf_dev"
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_config_dev)
                scroll_down
                print_fancy "▶️  Édition du fichier :"
                print_fancy --align right --fg blue "${CONF_DEV_FILE}"
                $EDITOR "$DIR_CONF_DEV_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_init_secret_file)
                scroll_down
                print_fancy "▶️  Installation d'un fichier (optionnel) :"
                print_fancy --align right --fg blue "${SECRET_FILE}"
                echo "Le fichier sera préservé lors des mises à jours automatiques."
                init_file "conf_secret"
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_edit_config_secrets)
                scroll_down
                print_fancy "▶️  Édition du fichier :"
                print_fancy --align right --fg blue "${SECRET_FILE}"
                $EDITOR "$SECRET_FILE"
                echo "✅  ... Édition terminée > retour au menu."
                ;;
            menu_dev_install)
                scroll_down
                echo "▶️  Menu de d'installation de composants additionnels..."
                dev_install
                echo "✅  ... Installation terminée > retour au menu."
                ;;
            menu_dev_uninstall)
                scroll_down
                echo "▶️  Menu de désinstallation..."
                dev_uninstall
                echo "✅  ... Désinstallation terminée > retour au menu."
                ;;
            menu_cron_management)
                scroll_down
                cron_submenu
                echo "✅  ... Retour au menu principal."
                ;;
            menu_show_help)
                scroll_down
                show_help
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