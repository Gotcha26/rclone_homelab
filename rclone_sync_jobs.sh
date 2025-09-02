#!/bin/bash

# ---------------------------------------------------------------------------
# jobs.sh - Exécution des jobs rclone
# ---------------------------------------------------------------------------

# Charger les fonctions
source "$SCRIPT_DIR/rclone_sync_functions.sh"

# Déclarer les tableaux globaux
declare -a JOBS_LIST       # Liste des jobs src|dst
declare -A JOB_STATUS      # idx -> OK / PROBLEM
declare -A REMOTE_STATUS   # remote_name -> OK / PROBLEM

# Charger les remotes rclone configurés
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

# ---------------------------------------------------------------------------
# 1. Parser les jobs et initialiser les statuts
# ---------------------------------------------------------------------------

parse_jobs "$JOBS_FILE"

# ---------------------------------------------------------------------------
# 2. Vérifier les remotes et mettre à jour JOB_STATUS
# ---------------------------------------------------------------------------

check_remotes

# ---------------------------------------------------------------------------
# 3. Variables globales pour exécution
# ---------------------------------------------------------------------------
GLOBAL_HTML_BLOCK=""          # Initialisation du HTML global
JOB_COUNTER=1                 # Compteur de jobs pour le label [JOBxx]
NO_CHANGES_ALL=true

# ---------------------------------------------------------------------------
# 4. Exécution des jobs filtrés
# ---------------------------------------------------------------------------
for idx in "${!JOBS_LIST[@]}"; do
    job="${JOBS_LIST[$idx]}"
    IFS='|' read -r src dst <<< "$job"
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")

    # === Création des fichiers temporaires ===
    init_job_logs "$JOB_ID"

    # === Affichage d’attente coté terminal ===
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING1"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING2"
    print_fancy --bg "blue" --fill "=" --align "center" --highlight "$MSG_WAITING3"
    echo

    # === Header Job ===
    print_fancy --align "center" "[$JOB_ID] $src → $dst"
    print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
    echo

    {
        echo "[$JOB_ID] $src → $dst"
        echo "$MSG_TASK_LAUNCH ${NOW}"
        echo ""
    } > "$TMP_JOB_LOG_RAW"

    # === Exécution rclone ===
    if [[ "${JOB_STATUS[$idx]}" == "PROBLEM" ]]; then
        print_fancy --theme "warning" "Job écarté à cause d'un remote inaccessible. (unauthenticated)"
        
        {
            echo ""
            echo "⚠️  Job écarté à cause d'un remote inaccessible. (unauthenticated)"
        } >> "$TMP_JOB_LOG_RAW"

        job_rc=1
        ERROR_CODE=8
    else
        rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_RAW" 2>&1 &
        RCLONE_PID=$!
        spinner $RCLONE_PID
        wait $RCLONE_PID
        job_rc=$?
        (( job_rc != 0 )) && ERROR_CODE=8
    fi

    # === Colorisation et génération logs ===
    tail -n +3 "$TMP_JOB_LOG_RAW" | colorize | tee -a "$LOG_FILE_INFO"  # On commence à partir de la ligne 3
    generate_logs "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_HTML" "$TMP_JOB_LOG_PLAIN"

    # === Assemblage HTML global ===
    if (( JOB_COUNTER > 1 )); then
        GLOBAL_HTML_BLOCK+="<br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")

    # === Notification Discord ===
    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    # === Incrément compteur ===
    (( job_rc == 0 )) && ((EXECUTED_JOBS++))   # Compte uniquement si succès
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo
done