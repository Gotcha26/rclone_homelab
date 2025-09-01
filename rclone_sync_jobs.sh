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
    # Extraire le statut du job (dernier champ après le dernier '|')
    job="${JOBS_LIST[$idx]}"
    status="${job##*|}"

    if [[ "$status" == "OK" ]]; then
        VALID_JOBS+=("$job")
    else
        # Affichage info job écarté
        print_fancy --theme "warning" "Job écarté : $job (remote inaccessible ou token expiré)"
    fi
done

###############################################################################
# Exécution des jobs filtrés
###############################################################################
for job in "${JOBS_LIST[@]}"; do
    src="${job%%|*}"
    dst="${job##*|}"
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")    # Identifiant du job [JOB01], [JOB02], ...

    # Affichage d'attente
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING1"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING2"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING3"
    echo

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${JOB_ID}_raw.log"
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${JOB_ID}_html.log"
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${JOB_ID}_plain.log"

    # Vérifier remote si nécessaire
    remote="${dst%%:*}"
    skip_job=false
    if [[ "$dst" == *":"* ]]; then
        if [[ "${REMOTE_STATUS[$remote]}" != "OK" ]]; then
            # Remote problématique, écarter job mais générer logs simulés
            skip_job=true
            echo "⚠️  Remote '$remote' inaccessible ou token expiré" > "$TMP_JOB_LOG_RAW"
            echo "→ Job affecté : $job" >> "$TMP_JOB_LOG_RAW"
        fi
    fi

    # Header job
    {
        print_fancy --align "center" "[$JOB_ID] $src → $dst"
        if $skip_job; then
            print_fancy --theme "warning" "Job écarté à cause d'un remote inaccessible."
        else
            print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
        fi
        echo ""
    } | tee -a "$LOG_FILE_INFO" | tee -a "$TMP_JOB_LOG_RAW"

    # Header HTML + ligne vide
    {
        echo "<b>[$JOB_ID]</b> $src → $dst<br>"
        if $skip_job; then
            echo "⚠️ Job écarté à cause d'un remote inaccessible<br>"
        else
            echo "$MSG_TASK_LAUNCH $NOW<br>"
        fi
        echo "<br>"
    } > "$TMP_JOB_LOG_HTML"

    # === Exécution rclone si job valide ===
    if ! $skip_job; then
        rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_RAW" 2>&1 &
        RCLONE_PID=$!
        spinner $RCLONE_PID
        wait $RCLONE_PID
        job_rc=$?
        (( job_rc != 0 )) && ERROR_CODE=8
    else
        job_rc=1    # Job simulé comme échoué
        ERROR_CODE=8
    fi

    # Colorisation et génération logs
    colorize < "$TMP_JOB_LOG_RAW" | tee -a "$LOG_FILE_INFO"
    prepare_mail_html "$TMP_JOB_LOG_RAW" >> "$TMP_JOB_LOG_HTML"
    make_plain_log "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_PLAIN"

    # Assemblage HTML global
    if $PREVIOUS_JOB_PRESENT; then
        GLOBAL_HTML_BLOCK+="<br><br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")
    PREVIOUS_JOB_PRESENT=true

    # Notification Discord
    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    # Incrément compteur
    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo
done