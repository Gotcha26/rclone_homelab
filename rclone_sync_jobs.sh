source "$SCRIPT_DIR/rclone_sync_conf.sh"
source "$SCRIPT_DIR/rclone_sync_functions.sh"

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
        remote_name="${dst%%:*}"
        if [[ ! " ${RCLONE_REMOTES[*]} " =~ " ${remote_name} " ]]; then
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

###############################################################################
# Partie email conditionnelle
###############################################################################

# Pièces jointes : log INFO (toujours), DEBUG (en cas d’erreur globale)
if $SEND_MAIL; then

	echo
    print_centered_text "$MSG_PREP"

    ATTACHMENTS+=("$LOG_FILE_INFO")

    # Vérification présence msmtp (ne stoppe pas le script)
    if ! command -v msmtp >/dev/null 2>&1; then
        echo "${ORANGE}$MSG_MSMTP_NOT_FOUND${RESET}" >&2
        ERROR_CODE=9
    else
		# === Compter les occurrences sur l'ensemble des jobs, uniquement lignes contenant INFO ===
		TOTAL_COPIED=$(grep "INFO" "$LOG_FILE_INFO" | grep -c "Copied" || true)
		TOTAL_UPDATED=$(grep "INFO" "$LOG_FILE_INFO" | grep -c "Updated" || true)
		TOTAL_DELETED=$(grep "INFO" "$LOG_FILE_INFO" | grep -c "Deleted" || true)

		# Ajouter un résumé général dans le mail
		MAIL_CONTENT+="<hr><h3>📊 Résumé global</h3>"
		MAIL_CONTENT+="<pre><b>Fichiers copiés :</b> $TOTAL_COPIED"
		MAIL_CONTENT+="<br><b>Fichiers mis à jour :</b> $TOTAL_UPDATED"
		MAIL_CONTENT+="<br><b>Fichiers supprimés :</b> $TOTAL_DELETED</pre>"

        MAIL_CONTENT+="<p>$MSG_EMAIL_END</p></body></html>"

		# === Détermination du sujet du mail selon le résultat global ===
        # === Analyse du log global pour déterminer l'état final ===
        HAS_ERROR=false
        HAS_NO_TRANSFER=false

        # Erreur détectée
        if grep -iqE "(error|failed|failed to)" "$LOG_FILE_INFO"; then
            HAS_ERROR=true
        fi

        # Aucun transfert détecté (cas précis)
        if grep -q "There was nothing to transfer" "$LOG_FILE_INFO"; then
            HAS_NO_TRANSFER=true
        fi

        # === Choix du sujet du mail ===
        if $HAS_ERROR; then
            SUBJECT_RAW="$MSG_EMAIL_FAIL"
        elif $HAS_NO_TRANSFER; then
            SUBJECT_RAW="$MSG_MAIL_SUSPECT"
        else
            SUBJECT_RAW="$MSG_EMAIL_SUCCESS"
        fi

		# Encodage MIME UTF-8 Base64 du sujet
		encode_subject() {
			local raw="$1"
			printf "%s" "$raw" | base64 | tr -d '\n'
		}
		SUBJECT="=?UTF-8?B?$(encode_subject "$SUBJECT_RAW")?="

		# === Construction du mail ===
		{
			FROM_ADDRESS="$(grep '^from' ~/.msmtprc | awk '{print $2}')"
			echo "From: \"$MAIL_DISPLAY_NAME\" <$FROM_ADDRESS>"	# Laisser msmtp gérer l'expéditeur configuré
			echo "To: $MAIL_TO"
			echo "Date: $(date -R)"
			echo "Subject: $SUBJECT"
			echo "MIME-Version: 1.0"
			echo "Content-Type: multipart/mixed; boundary=\"BOUNDARY123\""
			echo
			echo "--BOUNDARY123"
			echo "Content-Type: text/html; charset=UTF-8"
			echo
			echo "$MAIL_CONTENT"
		} > "$MAIL"

		# === Ajout des pièces jointes ===
		for file in "${ATTACHMENTS[@]}"; do
			{
				echo
				echo "--BOUNDARY123"
				echo "Content-Type: text/plain; name=\"$(basename "$file")\""
				echo "Content-Disposition: attachment; filename=\"$(basename "$file")\""
				echo "Content-Transfer-Encoding: base64"
				echo
				base64 "$file"
			} >> "$MAIL"
		done

		echo "--BOUNDARY123--" >> "$MAIL"

		# === Envoi du mail ===
		msmtp -t < "$MAIL" || echo "$MSG_MSMTP_ERROR" >&2

    print_centered_text "$MSG_SENT"
    echo

    fi
fi
