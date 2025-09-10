#!/usr/bin/env bash

###############################################################################
# Si aucun argument fourni → affichage d’un menu interactif
###############################################################################
RUN_ALL_FROM_MENU=false

while true; do
    # --- Détection des dépendances ---
    MISSING_RCLONE=false
    MISSING_MSMTP=false

    command -v rclone >/dev/null 2>&1 || MISSING_RCLONE=true
    command -v msmtp >/dev/null 2>&1 || MISSING_MSMTP=true

    # --- Construction dynamique du menu ---
    MENU_OPTIONS=()
    MENU_ACTIONS=()

    # Fonction pour ajouter des options
    add_option() {
        MENU_OPTIONS+=("$1")
        MENU_ACTIONS+=("$2")
    }

    # --- Options de configuration ---

    add_option "Ajouter des remotes" "menu_jobs"


    if rclone_configured; then
        add_option "Afficher la configuration rclone" "menu_show_rclone_config"
    fi

    if msmtp_configured; then
        add_option "Afficher la configuration msmtp" "menu_show_msmtp_config"
    fi

    # --- Options jobs ---
    if jobs_configured; then
        add_option "Lancer tous les jobs (sans plus attendre ni options)" "menu_run_all_jobs"
        add_option "Lister les jobs configurés" "menu_list_jobs"
    fi

    # --- Installation des dépendances manquantes ---
    if [[ "$MISSING_RCLONE" == true || "$MISSING_MSMTP" == true ]]; then
        add_option "Installer les dépendances manquantes (rclone/msmtp)" "menu_install_missing_deps"
    fi

    # --- Options mises à jour dynamiques ---
    fetch_git_info || { echo "⚠️ Impossible de récupérer l'état Git"; continue; }

    # Analyse si mise à jour nécessaire
    update_status_code=$(analyze_update_status)

    # --- Branche main ---
    if [[ "$branch_real" == "main" ]]; then
        if (( latest_tag_epoch > head_epoch )); then
            add_option "Mettre à jour vers la dernière release (tag)" "menu_update_to_latest_tag"
        fi
    else
        # --- Branche dev ou expérimentale ---
        if (( head_epoch < remote_epoch )); then
            add_option "Mettre à jour la branche '$branch_real' (force branch)" "menu_update_force_branch"
        fi
    fi

        LAST_LOG_FILE=$(get_last_log)
    if [[ -n "$LAST_LOG_FILE" ]]; then
        add_option "Afficher les logs du dernier run" "menu_show_last_log"
    fi

    # --- Option de dev après une MAJ : init config locale ---
    if [[ ! -f "$SCRIPT_DIR/config/config.dev.sh" && "$branch_real" == "dev" ]]; then
        add_option "[DEV] Initialiser config locale" "menu_init_config_local"
    fi

    add_option "Afficher l'aide" "menu_show_help"
    add_option "Quitter" "menu_exit_script"

    # --- Affichage du menu ---
    echo
    echo "======================================="
    echo "     🚀  Rclone Homelab Manager"
    echo "======================================="
    echo

    # Affichage des options
    for i in "${!MENU_OPTIONS[@]}"; do
        echo "$((i+1))) ${MENU_OPTIONS[$i]}"
    done
    echo
    read -e -rp "Votre choix [1-${#MENU_OPTIONS[@]}] : " choice </dev/tty

    # --- Validation et exécution ---
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#MENU_OPTIONS[@]} )); then
        action="${MENU_ACTIONS[$((choice-1))]}"
        case "$action" in
            menu_jobs)
                if ! init_jobs_file; then
                    echo "❌ Impossible de créer jobs.txt, édition annulée."
                    continue
                fi
                echo "Ouverture de $JOBS_FILE..."
                exec nano "$JOBS_FILE"
                ;;
            menu_run_all_jobs)
                RUN_ALL_FROM_MENU=true
                ;;
            menu_list_jobs)
                list_jobs
                ;;
            menu_show_last_log)
                tail -n 500 "$LAST_LOG_FILE" > /dev/tty
                ;;
            menu_show_rclone_config)
                [[ -f "$RCLONE_CONF" ]] && cat "$RCLONE_CONF" || echo "⚠️ Fichier rclone introuvable ($RCLONE_CONF)"
                ;;
            menu_show_msmtp_config)
                [[ -f "$MSMTP_CONF" ]] && cat "$MSMTP_CONF" || echo "⚠️ Fichier msmtp introuvable ($MSMTP_CONF)"
                ;;
            menu_show_help)
                show_help
                ;;
            menu_install_missing_deps)
                install_missing_deps
                ;;
            menu_update_to_latest_tag)
                update_to_latest_tag
                ;;
            menu_update_force_branch)
                update_force_branch
                ;;
            menu_exit_script)
                echo "Bye 👋"
                exit 0
                ;;
            menu_init_config_local)
                echo "⚡  [DEV] Initialiser config locale"
                init_config_local
                ;;
            *)
                echo "Choix invalide."
                ;;
        esac
    else
        echo "Choix invalide."
    fi
done
