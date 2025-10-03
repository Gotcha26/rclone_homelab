###############################################################################
# Fonctions pivot qui préparer la logique d'envoi d'email si le paramètre MAIL_TO est fourni/valide
###############################################################################
check_and_prepare_email() {
    local mail_to="$1"

    if [[ -z "$mail_to" ]]; then
        display_msg "verbose|hard" --theme info "Aucun email fourni : pas besoin de chercher à en envoyer un !"
        return 0
    fi

    display_msg "verbose|hard" "☛  Adresse email détectée, envoie d'un mail requis !"

    # 1/x : Contrôle du format
    display_msg "verbose|hard" "☞  1/x Contrôle d'intégrité adresse email"
    if ! check_mail_format "$mail_to"; then
        display_msg "soft" --theme ok "Email non validé."
        display_msg "verbose|hard" --theme error "L'adresse email saisie ne satisfait pas aux exigences et est rejetée."
        die 12 "Adresse email saisie invalide : $mail_to"
    else
        display_msg "soft|verbose|hard" --theme ok "Email validé."
    fi

    # 2a/x : Présence de msmtp
    display_msg "verbose|hard" "☞  2a/x Contrôle présence msmtp"
    if ! check_msmtp; then
        if [[ $ACTION_MODE == auto ]]; then
            display_msg "soft" --theme error "msmtp absent."
            display_msg "verbose|hard" --theme error "L'outil msmtp obligatoire mais n'est pas détecté."
            die 13 "msmtp absent..."
        else
            display_msg "soft|verbose|hard" --theme warning "msmtp absent, proposition d'installation"
            echo
            read -e -rp "Voulez-vous installer msmtp maintenant (requis) ? [O/n] : " -n 1 -r
            echo
            if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
                install_msmtp
            else
                die 15 "Annulé par l'utilisateur. msmtp est requis : non installé."
            fi
        fi
    else
        display_msg "soft|verbose|hard" --theme ok "L'outil msmtp est installé."
    fi

    # 3/x : Vérification configuration msmtp
    display_msg "verbose|hard" "☞  3/x Lecture (sans garanties) de la configuration msmtp"
    msmtp_conf=$(check_msmtp_configured)
    if [[ -z "$msmtp_conf" ]]; then
        if [[ $ACTION_MODE == auto ]]; then
            display_msg "soft" --theme error "msmtp non ou mal configuré."
            display_msg "verbose|hard" --theme error "L'outil msmtp semble mal configuré ou absent."
            die 14 "msmtp non ou mal configuré."
        else
            display_msg "soft|verbose|hard" --theme warning "msmtp absent, proposition de configuration"
            configure_msmtp
        fi
    else
        display_msg "soft|verbose|hard" --theme ok "L'outil msmtp est configuré :"
        display_msg "soft|verbose|hard" --fg blue --align right "$msmtp_conf"
    fi
}


###############################################################################
# Fonctions de vérification de l'email (forme)
###############################################################################
check_mail_format() {
    if [[ "$MAIL_TO" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}


###############################################################################
# Fonction : Détecter la présence de msmtp
###############################################################################
check_msmtp() {
    if command -v msmtp >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}


###############################################################################
# Fonction : Installer msmtp (sans confirmation)
###############################################################################
install_msmtp() {
    echo "📦  Installation de msmtp en cours..."
    if $SUDO apt update && $SUDO apt install -y msmtp msmtp-mta; then
        print_fancy -- theme ok "msmtp a été installé avec succès !"
    else
        die 14 "Une erreur est survenue lors de l'installation de msmtp."
    fi
}


###############################################################################
# Fonction : Détecter le fichier de configuration msmtp réellement utilisé
###############################################################################
check_msmtp_configured() {
    local candidates=()

    # 1. Variable d'environnement MSMTPRC si définie
    [[ -n "${MSMTPRC:-}" ]] && candidates+=("$MSMTPRC")

    # 2. Fichier utilisateur
    [[ -n "$HOME" ]] && candidates+=("$HOME/.msmtprc")

    # 3. Fichier système
    candidates+=("/etc/msmtprc")

    # Parcours des candidats
    for conf_file in "${candidates[@]}"; do
        if [[ -f "$conf_file" && -r "$conf_file" ]]; then
            if [[ -s "$conf_file" ]]; then
                # fichier existe et non vide
                echo "$conf_file"   # retourne le chemin
                return 0            # succès
            else
                echo "⚠️  Fichier msmtp trouvé mais vide : $conf_file"
                return 1
            fi
        fi
    done

    # Aucun fichier valide trouvé
    echo "❌  Aucun fichier msmtp valide trouvé."
    return 1
}


###############################################################################
# Fonctions EMAIL
###############################################################################

# Déterminer le sujet brut (SUBJECT_RAW) pour un job passé.
# Valable pour un fichier concaténé ou job individuel
# Evite les erreur lorsque aucun mail n'est saisie MAIS est nécessaire pour notification Discord

###############################################################################
# Fonction Détermine le sujet individuel issue du traitement d'un job.
# Est utilisée aussi par Discord
###############################################################################
calculate_subject_raw_for_job() {
    local job_log_file="$1"

    if grep -iqE "(error|failed|unexpected|io error|io errors|not deleting)" "$job_log_file"; then
        echo "❌  Des erreurs lors des sauvegardes vers le cloud"
    elif grep -q "There was nothing to transfer" "$job_log_file"; then
        echo "⚠️  Synchronisation réussie mais aucun fichier transféré"
    else
        echo "✅  Sauvegardes vers le cloud réussies"
    fi
}


###############################################################################
# Fonction prépare le contenu de l'email. Assemble et colorise.
###############################################################################
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


###############################################################################
# Fonction Encodage MIME UTF-8 Base64 du sujet
###############################################################################
encode_subject_for_email() {
    local log_file="$1"
    SUBJECT_RAW="$(calculate_subject_raw_for_job "$log_file")"
    SUBJECT="=?UTF-8?B?$(printf "%s" "$SUBJECT_RAW" | base64 -w0)?="
}


###############################################################################
# Fonction Assemblage des différents élements pour constituer un email complet (entête, corps...)
###############################################################################
assemble_mail_file() {
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
<p>– Fin du message automatique –</p>
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
}

send_email() {
    local html_block="$1"

    print_fancy --align "center" "📧  Préparation de l'email..."
    encode_subject_for_email "$LOG_FILE_INFO"
    assemble_mail_file "$TMP_JOB_LOG_HTML" "$html_block"

    # --- Envoi du mail ---
    msmtp --logfile "$DIR_LOG_FILE_MAIL" -t < "$MAIL" || echo "⚠ Echec envoi email via msmtp" >> "$DIR_LOG_FILE_MAIL"
    print_fancy --align "center" "... Email envoyé ✅ "

    # --- Nettoyage optionnel ---
    rm -f "$MAIL"
}
