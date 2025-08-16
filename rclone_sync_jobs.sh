SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/rclone_sync_conf.sh"
source "$SCRIPT_DIR/rclone_sync_functions.sh"

###############################################################################
# Affiche le logo uniquement si on n'est pas en mode "automatique"
###############################################################################
if [[ "$LAUNCH_MODE" != "automatique" ]]; then
    print_logo
fi

###############################################################################
# Pré-vérification de tous les jobs
###############################################################################
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

	# Nettoyage de la ligne : trim + uniformisation séparateurs
    line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
    IFS='|' read -r src dst <<< "$line"
    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"
    if [[ -z "$src" || -z "$dst" ]]; then
        echo "$MSG_JOB_LINE_INVALID : $line" >&2
        ERROR_CODE=3
        exit $ERROR_CODE
    fi
    if [[ ! -d "$src" ]]; then
        echo "$MSG_SRC_NOT_FOUND : $src" >&2
        ERROR_CODE=4
        exit $ERROR_CODE
    fi
    if [[ "$dst" == *":"* ]]; then
        remote_name="${dst%%:*}"  # récupère la partie avant le ":"
        # Remplissage de la liste des remotes connus (avec config correcte)
        RCLONE_REMOTES=$(rclone listremotes "${RCLONE_OPTS[@]}")
        # Vérification du remote
        if ! echo "$RCLONE_REMOTES" | grep -qx "${remote_name}:"; then
            echo "$MSG_REMOTE_UNKNOWN : $remote_name" >&2
            ERROR_CODE=5
            exit $ERROR_CODE
        fi
    fi
done < "$JOBS_FILE"

###############################################################################
# Exécution des jobs
###############################################################################

# === Initialisation du flag global avant la boucle des jobs ===
NO_CHANGES_ALL=true

# Initialisation des pièces jointes (évite erreur avec set -u)
declare -a ATTACHMENTS=()

# Compteur de jobs pour le label [JOBxx]
JOB_COUNTER=1

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Nettoyage de la ligne : trim + uniformisation séparateurs
    line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
    IFS='|' read -r src dst <<< "$line"
    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"

    # Générer un identifiant compact du job : [JOB01], [JOB02], ...
    JOB_ID=$(printf "JOB%02d" "$JOB_COUNTER")

    # Affichage header job dans terminal et log global
    print_centered_line "$MSG_WAITING1"
    print_centered_line "$MSG_WAITING2"
    print_centered_line "$MSG_WAITING3"
    echo

	print_centered_text "[$JOB_ID] $src → $dst" | tee -a "$LOG_FILE_INFO"
	print_centered_text "Tâche lancée le $(date '+%Y-%m-%d à %H:%M:%S')" | tee -a "$LOG_FILE_INFO"
    echo "" | tee -a "$LOG_FILE_INFO"

    # === Créer un log temporaire pour ce job ===
    JOB_LOG_INFO="$(mktemp)"

    # Exécution rclone, préfixe le job sur chaque ligne, capture dans INFO.log + affichage terminal colorisé
	# Lancer rclone en arrière-plan
	rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" --log-level INFO >"$JOB_LOG_INFO" 2>&1 &
	RCLONE_PID=$!

	# Afficher le spinner tant que rclone tourne
	spinner $RCLONE_PID

	# Récupérer le code retour de rclone
	wait $RCLONE_PID
	job_rc=$?
	(( job_rc != 0 )) && ERROR_CODE=6

	# Affichage colorisé après exécution
	sed "s/^/[$JOB_ID] /" "$JOB_LOG_INFO" | colorize


    # Mise à jour du mail
    if $SEND_MAIL; then
        MAIL_CONTENT+="<p><b>📝 Dernières lignes du log :</b></p><pre style='background:#eee; padding:1em; border-radius:8px;'>"
        MAIL_CONTENT+="$(log_to_html "$JOB_LOG_INFO")"
        MAIL_CONTENT+="</pre>"
    fi

    # Concatenation du log temporaire dans le log global
    cat "$JOB_LOG_INFO" >> "$LOG_FILE_INFO"
    rm -f "$JOB_LOG_INFO"

    ((JOBS_COUNT++))
    (( job_rc != 0 )) && MAIL_SUBJECT_OK=false
    echo

    # Incrément du compteur pour le prochain job
    ((JOB_COUNTER++))
done < "$JOBS_FILE"
