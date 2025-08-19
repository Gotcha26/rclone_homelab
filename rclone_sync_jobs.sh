SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        ERROR_CODE=6
        exit $ERROR_CODE
    fi

    # Vérif source locale
    if [[ ! -d "$src" ]]; then
        echo "$MSG_SRC_NOT_FOUND : $src" >&2
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

#  Initialisation du flag global avant la boucle des jobs
NO_CHANGES_ALL=true

# Compteur de jobs pour le label [JOBxx]
JOB_COUNTER=1

JOBS_COUNT=0

while IFS= read -r line; do
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

    # Affichage header job
    print_fancy --bg $BLUE_DARK --fill "=" --align "center" "$MSG_WAITING1"
    print_fancy --bg $BLUE_DARK --fill "=" --align "center" "$MSG_WAITING2"
    print_fancy --bg $BLUE_DARK --fill "=" --align "center" "$MSG_WAITING3"
    echo

    print_fancy --align "center" "[$JOB_ID] $src → $dst" | tee -a "$LOG_FILE_INFO"
    print_fancy --align "center" "$MSG_TASK_LAUNCH $(date '+%Y-%m-%d à %H:%M:%S')" | tee -a "$LOG_FILE_INFO"
    echo "" | tee -a "$LOG_FILE_INFO"

    # Log temporaire pour ce job
    JOB_LOG_INFO="$(mktemp)"

    # === Exécution rclone ===

    rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" > "$JOB_LOG_INFO" 2>&1 &
    RCLONE_PID=$!

	# Afficher le spinner tant que rclone tourne
    spinner $RCLONE_PID

    # Attendre fin rclone et récupérer code retour
    wait $RCLONE_PID
    job_rc=$?
    (( job_rc != 0 )) && ERROR_CODE=8

    # Affichage colorisé après exécution
    sed "s/^/[$JOB_ID] /" "$JOB_LOG_INFO" | colorize

    # Concatenation du log temporaire dans le log global
    cat "$JOB_LOG_INFO" >> "$LOG_FILE_INFO"
    rm -f "$JOB_LOG_INFO"

    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    echo

    # Incrément du compteur pour le prochain job
    ((JOB_COUNTER++))
done < "$JOBS_FILE"
