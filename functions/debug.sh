#!/usr/bin/env bash


###############################################################################
# Fonction : Affiche des informations d'aide au débugage en entête
###############################################################################
debug_1_header () {    
    echo "================================================================================"
    print_fancy --highlight --bg "green" --align "center" --style "bold" --fill "=" " DÉBUT DU DEBUG DE TÊTE "
    echo

    # Debug affichage
    print_fancy --fg "green" --align "center" "********************"
    print_fancy --fg "green" --align "center" "Tableau des variables locales prise en compte"
    print_fancy --fg "green" --align "center" "********************"
    print_vars_table VARS_TO_VALIDATE
    print_fancy --fg "green" --align "center" "********************"

    # Dossier temporaire unique
    TMP_JOBS_DIR="$SCRIPT_DIR/tmp_jobs_debug"
    if mkdir -p "$TMP_JOBS_DIR"; then
        print_fancy --theme "success" "Répertoire temporaire créé avec succès : $TMP_JOBS_DIR"
    else
        print_fancy --theme "error" "Erreur lors de la création du répertoire : $TMP_JOBS_DIR" >&2
    fi

    if [[ "$DEBUG_INFOS" == "true" ]]; then 
        print_fancy --theme "info" --fg "black" --bg "white" "DEBUG: DIR_LOG_FILE_SCRIPT = $DIR_LOG_FILE_SCRIPT"
    fi

    echo
    print_fancy --highlight --bg "green" --align "center" --style "bold" --fill "=" " FIN DU DEBUG DE TÊTE "
}