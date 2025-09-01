#!/bin/bash

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
# Filtrer les jobs valides (remotes OK)
###############################################################################
declare -a VALID_JOBS
for idx in "${!JOBS_LIST[@]}"; do
    # Vérifier si le job est marqué comme OK
    if [[ "${JOBS_STATUS[$idx]}" == "OK" ]]; then
        VALID_JOBS+=("${JOBS_LIST[$idx]}")
    else
        # Affichage info job écarté
        print_fancy --theme "warning" "Job écarté : ${JOBS_LIST[$idx]} (remote inaccessible ou token expiré)"
    fi
done

###############################################################################
# Exécution des jobs filtrés
###############################################################################
PREVIOUS_JOB_PRESENT=false
for job in "${VALID_JOBS[@]}"; do
    src="${job%%|*}"
    dst="${job##*|}"
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")    # Identifiant du job [JOB01], [JOB02], ...

    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING1"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING2"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING3"
    echo

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${JOB_ID}_raw.log"
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${JOB_ID}_html.log"
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${JOB_ID}_plain.log"

    TMP_JOB_LOG_INFO="$(mktemp)"
    {
        print_fancy --align "center" "[$JOB_ID] $src → $dst"
        print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
        echo ""
    } | tee -a "$LOG_FILE_INFO" | tee -a "$TMP_JOB_LOG_INFO"

    {
        echo "<b>[$JOB_ID]</b> $src → $dst<br>"
        echo "$MSG_TASK_LAUNCH $NOW<br>"
        echo "<br>"
    } > "$TMP_JOB_LOG_HTML"

    # === Exécution rclone en arrière-plan ===
    rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_RAW" 2>&1 &
    RCLONE_PID=$!

    spinner $RCLONE_PID
    wait $RCLONE_PID
    job_rc=$?
    (( job_rc != 0 )) && ERROR_CODE=8

    colorize < "$TMP_JOB_LOG_RAW" | tee -a "$LOG_FILE_INFO"
    prepare_mail_html "$TMP_JOB_LOG_RAW" >> "$TMP_JOB_LOG_HTML"
    make_plain_log "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_PLAIN"

    # Assemblage HTML global
    if $PREVIOUS_JOB_PRESENT; then
        GLOBAL_HTML_BLOCK+="<br><br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")
    PREVIOUS_JOB_PRESENT=true

    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo
done
