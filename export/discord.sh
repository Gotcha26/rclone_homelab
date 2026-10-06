#!/usr/bin/env bash

###############################################################################
# Fonction : envoyer une notification Discord avec sujet + log attaché
###############################################################################
send_discord_notification() {
    local log_file="$1"

    # Si pas de webhook défini → sortir silencieusement
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && return 0

    # Sujet calculé pour CE job
    local subject_raw
    subject_raw=$(calculate_subject_raw_for_job "$log_file")

    local message="🗞️  **$subject_raw** – $NOW"

    # jq est optionnel pour le projet mais requis ici (construction JSON sûre)
    if ! command -v jq >/dev/null 2>&1; then
        print_fancy --theme error --align "center" "Notification Discord impossible : jq n'est pas installé."
        ERROR_CODE=28
        return 1
    fi

    # Envoi du message + du log en pièce jointe (JSON construit via jq pour éviter l'injection)
    local json_payload
    json_payload=$(jq -n --arg content "$message" '{content: $content}')
    if curl -fsS --max-time 30 -X POST "$DISCORD_WEBHOOK_URL" \
        -F "payload_json=$json_payload" \
        -F "file=@$log_file" \
        > /dev/null; then
        print_fancy --theme ok --align "center" "Notification Discord envoyée."
    else
        print_fancy --theme error --align "center" "Échec de la notification Discord (webhook invalide ou réseau)."
        ERROR_CODE=28
        return 1
    fi
}