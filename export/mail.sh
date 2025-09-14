#!/usr/bin/env bash

###############################################################################
# Fonctions de vérification de l'email (forme)
###############################################################################

email_check() {
    local email="$1"
    # Regex basique : texte@texte.domaine
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        die 12 "$MSG_MAIL_ERROR : $email"
    fi
}


###############################################################################
# Fonctions EMAIL
###############################################################################

# Déterminer le sujet brut (SUBJECT_RAW) pour un job passé.
# Valable pour un fichier concaténé ou job individuel
# Evite les erreur lorsque aucun mail n'est saisie et est nécessaire pour notification Discord
calculate_subject_raw_for_job() {
    local job_log_file="$1"

    if grep -iqE "(error|failed|unexpected|io error|io errors|not deleting)" "$job_log_file"; then
        echo "$MSG_EMAIL_FAIL"
    elif grep -q "There was nothing to transfer" "$job_log_file"; then
        echo "$MSG_EMAIL_SUSPECT"
    else
        echo "$MSG_EMAIL_SUCCESS"
    fi
}

prepare_mail_html() {
    local file="$1"

    # Charger les dernières lignes dans un tableau
    mapfile -t __lines < <(tail -n "$LOG_LINE_MAX" "$file")
    local total=${#__lines[@]}

    # Déterminer le bloc final selon le type de job
    local final_count=4  # par défaut, job réussi
    if grep -iqE "(error|failed|unexpected|io error|io errors|not deleting)" "$file"; then
        final_count=9   # erreurs
    elif grep -q "There was nothing to transfer" "$file"; then
        final_count=1   # rien à transférer
    fi

    local normal_end=$((total - final_count))
    [[ $normal_end -lt 0 ]] && normal_end=0

    # Parcourir chaque ligne et générer le HTML
    for (( idx=0; idx<total; idx++ )); do
        local line="${__lines[idx]}"

        # Supprimer espaces en début/fin et ignorer lignes vides
        local trimmed_line
        trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$trimmed_line" ]]; then
            echo "<br>"  # préserve la ligne vide dans le HTML
            continue
        fi

        # Échapper le HTML
        local safe_line
        safe_line=$(printf '%s' "$trimmed_line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

        # Normalisation pour tests insensibles à la casse
        local lower="${trimmed_line,,}"

        # Colorisation mail (équivalent à colorize())
        local line_html
        if [[ "$lower" == *"--dry-run"* ]]; then
            line_html="<span style='color:orange; font-style:italic;'>$safe_line</span><br>"
        elif [[ "$lower" =~ \b(delete|deleted)\b ]]; then
            line_html="<span style='color:red;'>$safe_line</span><br>"
        elif [[ "$lower" =~ (error|failed|unexpected|io error|io errors|not deleting) ]]; then
            line_html="<span style='color:red; font-weight:bold;'>$safe_line</span><br>"
        elif [[ "$lower" =~ (copied|added|transferred|new|created|renamed|uploaded) ]]; then
            line_html="<span style='color:blue;'>$safe_line</span><br>"
        elif [[ "$lower" =~ (unchanged|already exists|skipped|skipping|there was nothing to transfer|no change) ]]; then
            line_html="<span style='color:orange;'>$safe_line</span><br>"
        else
            line_html="$safe_line<br>"
        fi

        # === Mettre en gras les deux premières lignes ===
        if (( idx == 0 || idx == 1 )); then
            line_html="<b>$line_html</b>"
        fi

        # Séparateur avant le bloc final
        if (( idx == normal_end )); then
            echo "<br>"
        fi

        # Afficher la ligne
        echo "$line_html"
    done
}


# Encodage MIME UTF-8 Base64 du sujet
encode_subject_for_email() {
    local log_file="$1"
    SUBJECT_RAW="$(calculate_subject_raw_for_job "$log_file")"
    SUBJECT="=?UTF-8?B?$(printf "%s" "$SUBJECT_RAW" | base64 -w0)?="
}

assemble_and_send_mail() {
    local log_file="$1"        # Fichier log utilisé pour calcul du résumé global (copied/updated/deleted)
    local html_block="$2"      # Bloc HTML global déjà préparé (tous les jobs), facultatif
    local MAIL="${DIR_TMP}/rclone_mail_$$.tmp"  # <- fichier temporaire unique

    # Récupération de l'adresse expéditeur depuis msmtp
    FROM_ADDRESS="$(grep '^from' /etc/msmtprc | awk '{print $2}')"

    {
        # --- En-têtes ---
        echo "From: \"$MAIL_DISPLAY_NAME\" <$FROM_ADDRESS>"
        echo "To: $MAIL_TO"
        echo "Date: $(date -R)"
        echo "Subject: $SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"MIXED_BOUNDARY\""
        echo
        echo "This is a multi-part message in MIME format."
        echo

        # --- Partie alternative (texte + HTML) ---
        echo "--MIXED_BOUNDARY"
        echo "Content-Type: multipart/alternative; boundary=\"ALT_BOUNDARY\""
        echo

        # Version texte brut (fallback)
        echo "--ALT_BOUNDARY"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo "Rapport de synchronisation Rclone - $NOW"
        echo "Voir la version HTML pour plus de détails."
        echo

        # Version HTML
        echo "--ALT_BOUNDARY"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        echo "<html><body style='font-family: monospace; background-color:#f9f9f9; padding:1em;'>"
        echo "<h2>📤 Rapport de synchronisation Rclone – $NOW</h2>"
        echo "<p><b>📝 Dernières lignes du log :</b></p>"
        echo "<div style='background:#eee; padding:1em; border-radius:8px; font-family: monospace;'>"
    } > "$MAIL"

    if [[ -n "$html_block" ]]; then
        echo "$html_block" >> "$MAIL"
    else
        prepare_mail_html "$log_file" >> "$MAIL"
    fi

    {
        echo "</div>"

        # --- Résumé global ---
        echo "<hr><h3>📊 Résumé global</h3>"

        local copied=$(grep -i "INFO" "$log_file" | grep -i "Copied" | grep -vi "There was nothing to transfer" | wc -l)
        local updated=$(grep -i "INFO" "$log_file" | grep -i "Updated" | grep -vi "There was nothing to transfer" | wc -l)
        local deleted=$(grep -i "INFO" "$log_file" | grep -i "Deleted" | grep -vi "There was nothing to transfer" | wc -l)

        cat <<HTML
<table style="font-family: monospace; border-collapse: collapse;">
<tr><td><b>Fichiers copiés&nbsp;</b></td>
    <td style="text-align:right;">: $copied</td></tr>
<tr><td><b>Fichiers mis à jour&nbsp;</b></td>
    <td style="text-align:right;">: $updated</td></tr>
<tr><td><b>Fichiers supprimés&nbsp;</b></td>
    <td style="text-align:right;">: $deleted</td></tr>
</table>
<p>$MSG_EMAIL_END</p>
</body></html>
HTML

        echo "--ALT_BOUNDARY--"   # Fin alternative
    } >> "$MAIL"

    # Récupérer tous les logs PLAIN (jobs)
    for file in "$TMP_JOBS_DIR"/JOB*_plain.log; do
        [[ -f "$file" ]] || continue
        {
            echo "--MIXED_BOUNDARY"
            echo "Content-Type: text/plain; name=\"$(basename "$file")\""
            echo "Content-Disposition: attachment; filename=\"$(basename "$file")\""
            echo "Content-Transfer-Encoding: base64"
            echo
            base64 "$file"
        } >> "$MAIL"
    done

    # --- Fermeture finale ---
    echo "--MIXED_BOUNDARY--" >> "$MAIL"

    # --- Envoi du mail ---
    msmtp --logfile "$DIR_LOG_FILE_MAIL" -t < "$MAIL" || echo "$MSG_MSMTP_ERROR" >> "$DIR_LOG_FILE_MAIL"
    print_fancy --align "center" "$MSG_EMAIL_SENT"

    # --- Nettoyage optionnel ---
    rm -f "$MAIL"
}

send_email_if_needed() {
    local html_block="$1"
    if [[ -z "$MAIL_TO" ]]; then
        print_fancy --theme "warning" "$MAIL_TO_ABS" >&2
    elif ! command -v msmtp >/dev/null 2>&1; then
        print_fancy --theme "warning" "$MSG_MSMTP_NOT_FOUND" >&2
        echo
        ERROR_CODE=13
    else
        print_fancy --align "center" "$MSG_EMAIL_PREP"
        encode_subject_for_email "$LOG_FILE_INFO"

        # Ici : soit on a un bloc HTML préformaté, soit on laisse assemble_and_send_mail parser
        assemble_and_send_mail "$TMP_JOB_LOG_HTML" "$html_block"
    fi
}