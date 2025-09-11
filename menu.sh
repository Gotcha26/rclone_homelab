#!/usr/bin/env bash

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
RUN_ALL_FROM_MENU=false

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
    # Construction nécessaire pour l'affichage des MAJ (bracnhe / release)
    fetch_git_info || { echo "⚠️ Impossible de récupérer l'état Git"; continue; }
    update_status_code=$(analyze_update_status)

    # === Options transmises à la fonciton précédente pour une mises à jour dynamiques ===

    # --- Options de configuration ---

    # 1) MAJ
    # Branche main
    if [[ "$branch_real" == "main" ]]; then
        if (( latest_tag_epoch > head_epoch )); then
            add_option "Mettre à jour vers la dernière release (tag)" "menu_update_to_latest_tag"
        fi
    else
        # Branche dev ou expérimentale
        if (( head_epoch < remote_epoch )); then
            add_option "Mettre à jour la branche '$branch_real' (force branch)" "menu_update_force_branch"
        fi
    fi

    # 2) Jobs (lancement)
    if jobs_configured; then
        add_option "Lancer tous les jobs (sans plus attendre ni options)" "menu_run_all_jobs"
    fi

    # 3) Configurations
    # Jobs
    add_option "Afficher/éditer des remotes" "menu_jobs"
    # rclone
    if rclone_configured; then
        add_option "Afficher/éditer la configuration rclone" "menu_show_rclone_config"
    fi
    #msmtp
    if msmtp_configured; then
        add_option "Afficher la configuration msmtp" "menu_show_msmtp_config"
    fi
    # Affichage du log précédent
    LAST_LOG_FILE=$(get_last_log)
    if [[ -n "$LAST_LOG_FILE" && -f "$LAST_LOG_FILE" ]]; then
        add_option "Afficher les logs du dernier run" "menu_show_last_log"
    fi

    # 4) Actions
    # Installation des dépendances manquantes
    if [[ "$MISSING_RCLONE" == true || "$MISSING_MSMTP" == true ]]; then
        add_option "Installer les dépendances manquantes (rclone/msmtp)" "menu_install_missing_deps"
    fi

    # Option de dev après une MAJ : init config locale
    if [[ ! -f "$SCRIPT_DIR/config/config.dev.sh" && "$branch_real" == "dev" ]]; then
        add_option "[DEV] Initialiser config locale" "menu_init_config_local"
    fi

    # Choix permanents
    add_option "Afficher l'aide" "menu_show_help"
    add_option "Quitter" "menu_exit_script"

    # === Affichage du menu ===

    echo
    echo "======================================="
    echo "     🚀  Rclone Homelab Manager"
    echo "======================================="
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
                ;;
            menu_update_force_branch)
                update_force_branch
                ;;
            menu_run_all_jobs)
                RUN_ALL_FROM_MENU=true
                ;;
            menu_jobs)
                if ! init_jobs_file; then
                    echo "❌ Impossible de créer jobs.txt, édition annulée."
                    break  # ou return si dans une fonction, ou continue pour passer au menu suivant
                fi
                echo "⚡ Ouverture de $JOBS_FILE..." >&3
                # Lancement de nano dans un shell indépendant
                (exec </dev/tty >/dev/tty 2>/dev/tty; nano "$JOBS_FILE")
                echo "✅ Édition terminée, retour au menu..." >&3
                ;;
            menu_show_rclone_config)
                echo "⚡ Ouverture de $RCLONE_CONF..." >&3
                # Lancement de nano dans un shell indépendant
                (exec </dev/tty >/dev/tty 2>/dev/tty; nano "$RCLONE_CONF")
                echo "✅ Édition terminée, retour au menu..." >&3
                ;;
            menu_show_msmtp_config)
                [[ -f "$MSMTP_CONF" ]] && cat "$MSMTP_CONF" || echo "⚠️ Fichier msmtp introuvable ($MSMTP_CONF)"
                ;;            
            menu_show_last_log)
                tail -n 500 "$LAST_LOG_FILE" > /dev/tty
                ;;
            menu_install_missing_deps)
                install_missing_deps
                ;;
            menu_init_config_local)
                echo "⚡  [DEV] Initialiser config locale"
                init_config_local
                ;;    
            menu_show_help)
                show_help
                ;;
            menu_exit_script)
                echo "Bye 👋"
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
