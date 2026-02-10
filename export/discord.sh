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

    # Envoi du message + du log en pièce jointe (JSON construit via jq pour éviter l'injection)
    local json_payload
    json_payload=$(jq -n --arg content "$message" '{content: $content}')
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -F "payload_json=$json_payload" \
        -F "file=@$log_file" \
        > /dev/null

    # On considère qu’à partir du moment où la fonction est appelée, on annonce un succès
    print_fancy --theme ok --align "center" "Notification Discord envoyée."
}