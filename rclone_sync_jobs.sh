# Charger les fonctions et configurations
source "$SCRIPT_DIR/rclone_sync_functions.sh"

###############################################################################
# Pré-vérification de tous les jobs avant exécution
###############################################################################

# Charger les remotes rclone configurés
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

# Lecture de chaque ligne du fichier jobs pour vérification
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Nettoyage : trim + uniformisation séparateurs
    line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
    IFS='|' read -r src dst <<< "$line"

    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"

    # Vérif ligne valide
    if [[ -z "$src" || -z "$dst" ]]; then
        echo "$MSG_JOB_LINE_INVALID : $line" >&2
        echo
        ERROR_CODE=6
        exit $ERROR_CODE
    fi

    # Vérif source locale
    if [[ ! -d "$src" ]]; then
        echo "$MSG_SRC_NOT_FOUND : $src" >&2
        echo
        ERROR_CODE=7
        exit $ERROR_CODE
    fi

    # Vérif remote si nécessaire
    if [[ "$dst" == *":"* ]]; then
        remote_name="${dst%%:*}"  # récupère la partie avant le ":"
        check_remote "$remote_name"
    fi

done < "$JOBS_FILE"


###############################################################################
# Exécution des jobs
###############################################################################

# Initialisation du HTML global
GLOBAL_HTML_BLOCK=""

# Compteur de jobs pour le label [JOBxx]
JOB_COUNTER=1
JOBS_COUNT=0
NO_CHANGES_ALL=true

# Lire les jobs en ignorant les lignes vides et les commentaires
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Nettoyage : trim + uniformisation séparateurs
    line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
    IFS='|' read -r src dst <<< "$line"

    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"

    # Identifiant du job [JOB01], [JOB02], ...
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")

    # Affichage header (terminal uniquement si pas --dry-run et pas --auto)
    if [[ "$DRY_RUN" != true && "$LAUNCH_MODE" != "automatique" ]]; then
        print_fancy --bg $BLUE --fill "=" --align "center" "$MSG_WAITING1"
        print_fancy --bg $BLUE --fill "=" --align "center" "$MSG_WAITING2"
        print_fancy --bg $BLUE --fill "=" --align "center" "$MSG_WAITING3"
        echo
    fi

    # Affichage header job et redirection vers le log temporaire
    # Affichage filtré vers le HTML pour supprimer les balises ANSI
    TMP_JOB_LOG_INFO="$(mktemp)"
    {
        print_fancy --align "center" "[$JOB_ID] $src → $dst"
        print_fancy --align "center" "$MSG_TASK_LAUNCH ${NOW}"
        echo ""
    } | tee -a "$LOG_FILE_INFO" >> "$TMP_JOB_LOG_INFO"

    # === Exécution rclone en arrière-plan ===
    rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" >> "$TMP_JOB_LOG_INFO" 2>&1 &
    RCLONE_PID=$!

    # Afficher le spinner tant que rclone tourne
    spinner $RCLONE_PID

    # Attendre fin rclone et récupérer code retour
    wait $RCLONE_PID
    job_rc=$?
    (( job_rc != 0 )) && ERROR_CODE=8

    # Affichage colorisé après exécution dans la console
    colorize < "$TMP_JOB_LOG_INFO" | tee -a "$LOG_FILE_INFO"

    # Créer une version sans ANSI pour l'email
    JOB_LOG_EMAIL="${TMP_RCLONE}_${JOB_ID}_email_${LOG_TIMESTAMP}.log"
    make_plain_log "$TMP_JOB_LOG_INFO" "$JOB_LOG_EMAIL"

    # Générer le HTML pour ce job et l'ajouter au HTML global
    GLOBAL_HTML_BLOCK+=$(prepare_mail_html "$JOB_LOG_EMAIL")$'\n'

    # Créer une version sans ANSI pour Discord et envoyer immédiatement
    TMP_JOB_LOG_DISCORD="${TMP_RCLONE}_${JOB_ID}_${LOG_TIMESTAMP}.log"
    make_plain_log "$TMP_JOB_LOG_INFO" "$TMP_JOB_LOG_DISCORD"
    send_discord_notification "$TMP_JOB_LOG_DISCORD"

    # Nettoyer le log temporaire
    rm -f "$TMP_JOB_LOG_DISCORD" "$TMP_JOB_LOG_INFO"

    # Incrément du compteur pour le prochain job
    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    ((JOB_COUNTER++))
    echo

done < "$JOBS_FILE"