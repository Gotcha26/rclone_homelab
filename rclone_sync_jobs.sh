#!/bin/bash

# Charger les fonctions et configurations
source "$SCRIPT_DIR/rclone_sync_functions.sh"

# Charger les remotes rclone configurés
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

###############################################################################
# Préparer les jobs
###############################################################################

# Parser le fichier jobs dans JOBS_LIST
parse_jobs "$JOBS_FILE"

# Variables
GLOBAL_HTML_BLOCK=""          # Initialisation du HTML global
JOB_COUNTER=1                 # Compteur de jobs pour le label [JOBxx]
JOBS_COUNT=0
NO_CHANGES_ALL=true
PREVIOUS_JOB_PRESENT=false    # Variable pour savoir si un job précédent a été ajouté

###############################################################################
# Exécution des jobs
###############################################################################
for job in "${JOBS_LIST[@]}"; do
    src="${job%%|*}"
    dst="${job##*|}"
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")    # Identifiant du job [JOB01], [JOB02], ...

    # Affichage header (terminal uniquement si pas --dry-run et pas --auto)
    if [[ "$DRY_RUN" != true && "$LAUNCH_MODE" != "automatique" ]]; then
        print_fancy --bg "blue" --fill "=" --align "center" "$MSG_WAITING1"
        print_fancy --bg "blue" --fill "=" --align "center" "$MSG_WAITING2"
        print_fancy --bg "blue" --fill "=" --align "center" "$MSG_WAITING3"
        echo
    fi

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${JOB_ID}_raw.log"
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${JOB_ID}_html.log"
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${JOB_ID}_plain.log"

    # Affichage header job et redirection vers le log temporaire
    # Affichage filtré vers le HTML pour supprimer les balises ANSI
    TMP_JOB_LOG_INFO="$(mktemp)"
    {
        print_fancy --align "center" "[$JOB_ID] $src → $dst"
        print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
        echo ""
    } | tee -a "$LOG_FILE_INFO" >> "$TMP_JOB_LOG_INFO"

        # Header HTML + ligne vide
    {
        echo "<b>[$JOB_ID]</b> $src → $dst<br>"
        echo "$MSG_TASK_LAUNCH $NOW<br>"
        echo "<br>"
    } > "$TMP_JOB_LOG_HTML"

    # === Exécution rclone en arrière-plan ===
    rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_RAW" 2>&1 &
    RCLONE_PID=$!

    # Afficher le spinner tant que rclone tourne
    spinner $RCLONE_PID

    # Attendre fin rclone et récupérer code retour
    wait $RCLONE_PID
    job_rc=$?
    (( job_rc != 0 )) && ERROR_CODE=8

    # Affichage colorisé après exécution dans la console
    colorize < "$TMP_JOB_LOG_RAW" | tee -a "$LOG_FILE_INFO"

    # Génération logs HTML & plain
    prepare_mail_html "$TMP_JOB_LOG_RAW" >> "$TMP_JOB_LOG_HTML"
    make_plain_log "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_PLAIN"

    # Assemblage HTML global
    # Ajouter un séparateur seulement si ce n'est pas le premier job
    if $PREVIOUS_JOB_PRESENT; then
        GLOBAL_HTML_BLOCK+="<br><br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")
    PREVIOUS_JOB_PRESENT=true

    # On marque qu’un job a déjà été ajouté
    PREVIOUS_JOB_PRESENT=true

    # Notification Discord
    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    # Incrément du compteur pour le prochain job
    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo

done