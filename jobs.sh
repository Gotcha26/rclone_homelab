#!/bin/bash

# ---------------------------------------------------------------------------
# jobs.sh - Exécution des jobs rclone
# ---------------------------------------------------------------------------

# re-charger les fonctions
source "$SCRIPT_DIR/functions/core.sh"

# Déclarer les tableaux globaux
declare -a JOBS_LIST       # Liste des jobs src|dst
declare -A JOB_STATUS      # idx -> OK / PROBLEM
declare -A REMOTE_STATUS   # remote_name -> OK / PROBLEM

# Charger les remotes rclone configurés
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')


# ---------------------------------------------------------------------------
# 1. Parser les jobs et initialiser les statuts
# ---------------------------------------------------------------------------



parse_jobs "$DIR_JOBS_FILE"


# ---------------------------------------------------------------------------
# 2. Vérifier les remotes et mettre à jour JOB_STATUS
# ---------------------------------------------------------------------------

# Attribution d'un ID à chaque ligne de job
for idx in "${!JOBS_LIST[@]}"; do
    JOB_ID=$(generate_job_id "$idx")     # <- ID unique pour ce job
    init_job_logs "$JOB_ID"              # <- logs prêts à l’emploi
done

# Boucle d'affichage pour les options reçues et prise en compte par rclone
if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    echo
    echo "===== Variables RCLONE_OPTS ====="
    if [[ -n "${RCLONE_OPTS[*]:-}" ]]; then
        for ((i=0; i<${#RCLONE_OPTS[@]}; i++)); do
            opt="${RCLONE_OPTS[$i]}"

            # Si l'option commence par -- et qu'il y a un argument après
            if [[ "$opt" == --* ]] && [[ $((i+1)) -lt ${#RCLONE_OPTS[@]} ]] && [[ "${RCLONE_OPTS[$((i+1))]}" != --* ]]; then
                val="${RCLONE_OPTS[$((i+1))]}"
                printf "    %s \"%s\"\n" "$opt" "$val"
                ((i++))  # sauter la valeur
            else
                printf "    %s\n" "$opt"
            fi
        done
    else
        echo "    (aucune option globale définie)"
    fi

    echo
    read -p "⏸ Pause : appuie sur Entrée pour continuer..." _
fi

check_remotes


# ---------------------------------------------------------------------------
# 3. Variables globales pour exécution
# ---------------------------------------------------------------------------
GLOBAL_HTML_BLOCK=""          # Initialisation du HTML global
JOB_COUNTER=1                 # Compteur de jobs pour le label [JOBxx]

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"


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
    print_fancy --style "bold" --align "center" "[$JOB_ID] $src → $dst"
    print_fancy --style "bold" --align "center" "$MSG_TASK_LAUNCH ${NOW}"
    echo

    {
        echo "[$JOB_ID] $src → $dst"
        echo "$MSG_TASK_LAUNCH ${NOW}"
        echo
    } > "$TMP_JOB_LOG_RAW"

    # Fonction utilitaire locale pour écrire dans le log
    log_only() {
        local msg="$1"
        echo "$msg" >> "$TMP_JOB_LOG_RAW"
    }

    # === Vérification du statut du job ===
    if [[ "${JOB_STATUS[$idx]}" == "PROBLEM" ]]; then
        # Utiliser directement le type enregistré dans JOB_MSG_LIST pour l'affichage
        if [[ -n "${JOB_MSG_LIST[$idx]}" ]]; then
            warn_remote_problem "${JOB_REMOTE[$idx]}" "${JOB_MSG_LIST[$idx]}" "$idx" "$TMP_JOB_LOG_RAW"
        else
            warn_remote_problem "${JOB_REMOTE[$idx]}" "unknown" "$idx" "$TMP_JOB_LOG_RAW"
        fi
        job_rc=1
    else
        # === Exécution rclone ===
        rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_RAW" 2>&1 &
        RCLONE_PID=$!
        spinner $RCLONE_PID
        wait $RCLONE_PID
        job_rc=$?

        # Détecter si le job a échoué
        if (( job_rc != 0 )); then
            ERROR_CODE=8
            # Analyse rapide du log pour détecter token expiré ou remote inaccessible
            if grep -q -i "unauthenticated\|invalid_grant\|couldn't fetch token" "$TMP_JOB_LOG_RAW"; then
                JOB_MSG_LIST[$idx]="token_expired"
            else
                JOB_MSG_LIST[$idx]="rclone_error"
            fi
        else
            JOB_STATUS[$idx]="OK"
            JOB_MSG_LIST[$idx]="ok"
        fi
    fi

    # === Affichage colorisé à l'écran et génération logs ===
    colorize "$TMP_JOB_LOG_RAW" | tail -n +4
    cat "$TMP_JOB_LOG_RAW" >> "$DIR_LOG_FILE_INFO"

    # Génération des logs HTML / PLAIN
    generate_logs "$TMP_JOB_LOG_RAW" "$TMP_JOB_LOG_HTML" "$TMP_JOB_LOG_PLAIN"

    # === Assemblage HTML global ===
    if (( JOB_COUNTER > 1 )); then
        GLOBAL_HTML_BLOCK+="<br><hr style='border:none; border-top:1px solid #ccc; margin:2em 0;'><br>"
    fi
    GLOBAL_HTML_BLOCK+=$(cat "$TMP_JOB_LOG_HTML")

    print_fancy --align "center" "====="

    # === Notification Discord ===
    echo
    send_discord_notification "$TMP_JOB_LOG_PLAIN"

    # === Incrément compteur ===
    (( job_rc == 0 )) && ((EXECUTED_JOBS++))   # Compte uniquement si succès
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo
done
