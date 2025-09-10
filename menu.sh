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
    # On récupère les infos pertinentes pour le menu
    current_commit=$(git rev-parse HEAD)
    current_commit_date=$(git show -s --format=%ci "$current_commit")
    current_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
    latest_tag=$(git tag --merged "origin/$BRANCH" | sort -V | tail -n1)
    latest_tag_commit=$(git rev-parse "$latest_tag" 2>/dev/null || echo "")
    latest_tag_date=$(git show -s --format=%ci "$latest_tag_commit" 2>/dev/null || echo "")
    remote_commit=$(git rev-parse "origin/$BRANCH")
    remote_commit_date=$(git show -s --format=%ci "$remote_commit")

    # --- Branche main ---
    if [[ "$BRANCH" == "main" ]]; then
        if [[ -n "$latest_tag" ]]; then
            # Comparaison horodatage pour savoir si MAJ pertinente
            head_epoch=$(date -d "$current_commit_date" +%s)
            tag_epoch=$(date -d "$latest_tag_date" +%s)
            if (( tag_epoch > head_epoch )); then
                add_option "Mettre à jour vers la dernière release (tag)" "menu_update_to_latest_tag"
            fi
        fi
    else
        # --- Branche dev ou expérimentale ---
        if [[ "$current_commit" != "$remote_commit" ]]; then
            add_option "Mettre à jour la branche '$BRANCH' (force branch)" "menu_update_force_branch"
        fi
    fi

    # --- Options classiques ---

    # --- Nouveau : affichage du dernier log terminé ---
    LAST_LOG_FILE=$(get_last_log)
    if [[ -n "$LAST_LOG_FILE" ]]; then
        add_option "Afficher les logs du dernier run" "menu_show_last_log"
    fi

    add_option "Afficher l'aide" "menu_show_help"
    add_option "Quitter" "menu_exit_script"

    # --- option invisible : init config locale ---
    if [[ ! -f "$SCRIPT_DIR/config/config.dev.sh" ]]; then
        MENU_ACTIONS+=("menu_init_config_local")  # ajout à la liste des actions, pas d'affichage
    fi

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
