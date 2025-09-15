#!/usr/bin/env bash

###############################################################################
# Fonction : Vérifier la présence de jobs configurés
###############################################################################
check_jobs_configured() {
    [[ -f "$DIR_JOBS_FILE" ]] || return 1
    # Vérifie qu’il existe au moins une ligne non vide qui ne commence pas par "#"
    grep -qE '^[[:space:]]*[^#[:space:]]' "$DIR_JOBS_FILE"
}


