#!/bin/bash

# ---------------------------------------------------------------------------
# jobs.sh - Exécution des jobs rclone
# ---------------------------------------------------------------------------

# Charger les fonctions
source "$SCRIPT_DIR/rclone_sync_functions.sh"

# Déclarer les tableaux globaux
declare -a JOBS_LIST       # Liste des jobs src|dst
declare -A JOB_STATUS      # idx -> OK / PROBLEM
declare -A JOBS_SKIP       # idx -> true / false
declare -A REMOTE_STATUS   # remote_name -> OK / PROBLEM

# Charger les remotes rclone configurés
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

# ---------------------------------------------------------------------------
# 1. Parser les jobs et initialiser les statuts
# ---------------------------------------------------------------------------

parse_jobs "$JOBS_FILE"

# Initialiser tous les jobs à OK et JOBS_SKIP à false
for idx in "${!JOBS_LIST[@]}"; do
    JOB_STATUS[$idx]="OK"
    JOBS_SKIP[$idx]=false
done

# ---------------------------------------------------------------------------
# 2. Vérifier les remotes et mettre à jour JOB_STATUS
# ---------------------------------------------------------------------------

check_remotes

# Après check_remotes, mettre JOBS_SKIP à true si JOB_STATUS est PROBLEM
for idx in "${!JOBS_LIST[@]}"; do
    if [[ "${JOB_STATUS[$idx]}" == "PROBLEM" ]]; then
        JOBS_SKIP[$idx]=true
    fi
done

# ---------------------------------------------------------------------------
# 3. Variables globales pour exécution
# ---------------------------------------------------------------------------
GLOBAL_HTML_BLOCK=""          # Initialisation du HTML global
JOB_COUNTER=1                 # Compteur de jobs pour le label [JOBxx]
JOBS_COUNT=0
NO_CHANGES_ALL=true
PREVIOUS_JOB_PRESENT=false    # Variable pour savoir si un job précédent a été ajouté

# ---------------------------------------------------------------------------
# 4. Exécution des jobs filtrés
# ---------------------------------------------------------------------------
for idx in "${!JOBS_LIST[@]}"; do
    job="${JOBS_LIST[$idx]}"
    IFS='|' read -r src dst <<< "$job"

    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")
    skip_job=${JOBS_SKIP[$idx]}

    # Vérif remote si applicable
    if [[ "$dst" == *":"* ]]; then
        remote="${dst%%:*}"
        if [[ "${REMOTE_STATUS[$remote]}" == "PROBLEM" ]]; then
            JOB_STATUS[$idx]="PROBLEM"
            JOBS_SKIP[$idx]=true
            skip_job=true
            print_fancy --theme "warning" "⚠️  [$JOB_ID] Remote $remote inaccessible, job sauté."
        fi
    fi

    # Affichage d’attente
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING1"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING2"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING3"
    echo

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${JOB_ID}_raw.log"
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${JOB_ID}_html.log"
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${JOB_ID}_plain.log"

    # === Header Job ===
    {
        print_fancy --align "center" "[$JOB_ID] $src → $dst"
        if ${JOBS_SKIP[$idx]}; then
            print_fancy --theme "warning" "Job écarté à cause d'un remote inaccessible."
        else
            print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
        fi
        echo ""
    } | tee -a "$LOG_FILE_INFO" | tee -a "$TMP_JOB_LOG_RAW"

    # === Header HTML ===
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
        job_rc=1
        ERROR_CODE=8
    fi

    # === Colorisation et génération logs ===
    colorize < "$TMP_JOB_LOG_RAW" | tee -a "$LOG_FILE_INFO"
    prepare_mail_html "$TMP_JOB_LOG_RAW" >> "$TMP_JOB_LOG_HTML"
    make_plain_log "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_PLAIN"

    # === Assemblage HTML global ===
    if $PREVIOUS_JOB_PRESENT; then
        GLOBAL_HTML_BLOCK+="<br><br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")
    PREVIOUS_JOB_PRESENT=true

    # === Notification Discord ===
    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    # === Incrément compteur ===
    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo
done