#!/usr/bin/env bash


###############################################################################
# Fonction : Affiche des informations d'aide au débugage en entête
###############################################################################
show_debug_header() {
    if [[ "${DEBUG_MODE,,}" == "true" ]]; then
        debug_header_total
    elif [[ "${DEBUG_INFOS,,}" == "true" ]]; then
        debug_header_partial
    fi
}

# Montage DEBUG_MODE
debug_header_complet () {
    debug_header_start
    debug_header_1
    debug_header_2
    debug_header_3
    debug_header_4
    debuh_header_stop
    echo
    read -p "⏸ Pause : appuie sur Entrée pour continuer..." _
}

#Montage DEBUG_INFO
debug_header_partial () {
    debug_header_1
    debug_header_3

}




debug_header_start() {
    echo "================================================================================"
    print_fancy --highlight --bg "green" --align "center" --style "bold" --fill "=" " DÉBUT DU DEBUG DE TÊTE "
}

debug_header_1() {
    # Debug affichage
    echo
    print_fancy --align "center" "********************"
    print_fancy --align "center" "Tableau des variables locales prise en compte"
    print_fancy -align "center" "********************"
    for var in "${VARS_TO_VALIDATE[@]}"; do
        echo "-> $var"
    done
    print_fancy --align "center" "********************"
}

debug_header_2() {
    # Dossier temporaire unique
    TMP_JOBS_DIR="$SCRIPT_DIR/tmp_jobs_debug"

    echo
    if mkdir -p "$TMP_JOBS_DIR"; then
        print_fancy --theme "success" "Répertoire temporaire créé avec succès : $TMP_JOBS_DIR"
    else
        print_fancy --theme "error" "Erreur lors de la création du répertoire : $TMP_JOBS_DIR" >&2
    fi
}

debug_header_3() {
    echo
    print_fancy --theme "info" --fg "black" --bg "white" "DEBUG: DIR_LOG_FILE_SCRIPT = $DIR_LOG_FILE_SCRIPT"
}

debug_header_4() {
    echo
    print_fancy --highlight --bg "green" --align "center" --style "bold" --fill "=" " FIN DU DEBUG DE TÊTE "
}

debuh_header_stop() {
    echo
    print_fancy --theme "info" --fg "black" --bg "white" "DEBUG: DIR_LOG_FILE_SCRIPT = $DIR_LOG_FILE_SCRIPT"
}