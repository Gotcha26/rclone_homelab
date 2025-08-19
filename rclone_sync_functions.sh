###############################################################################
# Fonction help (aide)
###############################################################################

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options :
  --auto             Lance le script en mode automatique (pas d'affichage du logo)
  --mailto=ADRESSE   Envoie un rapport par e-mail à l'adresse fournie
  --dry-run          Simule la synchronisation sans transférer ni supprimer de fichiers
  -h, --help         Affiche cette aide et quitte

Description :
  Ce script lit la liste des jobs à exécuter depuis le fichier :
      $JOBS_FILE
  Chaque ligne doit contenir :
      chemin_source|remote:chemin_destination
  Les lignes vides ou commençant par '#' sont ignorées.

  Exemple de ligne :
      /home/user/Documents|OneDrive:Backups/Documents

Fonctionnement :
  - Vérifie et teste les pré-requis au bon déroulement des opérations.
  - Lance 'rclone sync' pour chaque job avec les options par défaut
  - Affiche la sortie colorisée dans le terminal
  - Génère un fichier log INFO dans : $LOG_DIR
  - Si --mailto est fourni et msmtp est configuré, envoie un rapport HTML
EOF
}


###############################################################################
# Fonction pour vérifier si un remote existe
###############################################################################

check_remote() {
    local remote="$1"
    if [[ ! " ${RCLONE_REMOTES[*]} " =~ " ${remote} " ]]; then
        echo "${RED}${MSG_REMOTE_UNKNOW} : ${remote}${RESET}" >&2
        ERROR_CODE=9
        exit $ERROR_CODE
    fi
}


###############################################################################
# Fonctions EMAIL
###############################################################################

prepare_mail_html() {
  local file="$1"
  tail -n "$LOG_LINE_MAX" "$file" | while IFS= read -r line; do
    local safe_line
    safe_line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    if [[ "$line" == *"Deleted"* ]]; then
      echo "<span style='color:red;'>$safe_line</span><br>"
    elif [[ "$line" == *"Copied"* ]]; then
      echo "<span style='color:blue;'>$safe_line</span><br>"
    elif [[ "$line" == *"Updated"* ]]; then
      echo "<span style='color:orange;'>$safe_line</span><br>"
    elif [[ "$line" == *"NOTICE"* ]]; then
      echo "<b>$safe_line</b><br>"
    else
      echo "$safe_line<br>"
    fi
  done
}

calculate_subject() {
    local log_file="$1"
    if grep -iqE "(error|failed|failed to)" "$log_file"; then
        SUBJECT_RAW="$MSG_EMAIL_FAIL"
    elif grep -q "There was nothing to transfer" "$log_file"; then
        SUBJECT_RAW="$MSG_EMAIL_SUSPECT"
    else
        SUBJECT_RAW="$MSG_EMAIL_SUCCESS"
    fi
    # Encodage MIME UTF-8 Base64 du sujet
    SUBJECT="=?UTF-8?B?$(printf "%s" "$SUBJECT_RAW" | base64 -w0)?="
}

assemble_and_send_mail() {
    local log_file="$1"

    FROM_ADDRESS="$(grep '^from' ~/.msmtprc | awk '{print $2}')"
    {
        echo "From: \"$MAIL_DISPLAY_NAME\" <$FROM_ADDRESS>"     # Laisser msmtp gérer l'expéditeur configuré
        echo "To: $MAIL_TO"
        echo "Date: $(date -R)"
        echo "Subject: $SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"BOUNDARY123\""
        echo
        echo "--BOUNDARY123"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        echo "<html><body style='font-family: monospace; background-color: #f9f9f9; padding: 1em;'>"
        echo "<h2>📤 Rapport de synchronisation Rclone – $NOW</h2>"
        echo "<p><b>📝 Dernières lignes du log :</b></p>"
        echo "<div style='background:#eee; padding:1em; border-radius:8px; font-family: monospace;'>"
        prepare_mail_html "$log_file"
        echo "</div><hr><h3>📊 Résumé global</h3>"
        local copied=$(grep "INFO" "$log_file" | grep -c "Copied" || true)
        local updated=$(grep "INFO" "$log_file" | grep -c "Updated" || true)
        local deleted=$(grep "INFO" "$log_file" | grep -c "Deleted" || true)
        echo "<pre><b>Fichiers copiés :</b> $copied<br><b>Fichiers mis à jour :</b> $updated<br><b>Fichiers supprimés :</b> $deleted</pre>"
        echo "<p>$MSG_EMAIL_END</p></body></html>"
    } > "$MAIL"

    # Pièces jointes
    ATTACHMENTS=("$log_file")
    for file in "${ATTACHMENTS[@]}"; do
        {
            echo "--BOUNDARY123"
            echo "Content-Type: text/plain; name=\"$(basename "$file")\""
            echo "Content-Disposition: attachment; filename=\"$(basename "$file")\""
            echo "Content-Transfer-Encoding: base64"
            echo
            base64 "$file"
        } >> "$MAIL"
    done
    echo "--BOUNDARY123--" >> "$MAIL"

    # Envoi
    msmtp -t < "$MAIL" || echo "$MSG_MSMTP_ERROR" >&2
    print_fancy --align "center" "$MSG_EMAIL_SENT"
}

send_email_if_needed() {
    if [[ -z "$MAIL_TO" ]]; then
        echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    elif ! command -v msmtp >/dev/null 2>&1; then
        echo "${ORANGE}$MSG_MSMTP_NOT_FOUND${RESET}" >&2
        ERROR_CODE=9
    else
        print_fancy --align "center" "$MSG_EMAIL_PREP"
        calculate_subject "$LOG_FILE_INFO"
        assemble_and_send_mail "$LOG_FILE_INFO"
    fi
}


###############################################################################
# Fonction spinner
###############################################################################

spinner() {
    local pid=$1       # PID du processus à surveiller
    local delay=0.1    # vitesse du spinner
    local spinstr='|/-\'
    tput civis         # cacher l'curseur Hack

    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r[%c] Traitement en cours..." "${spinstr:i:1}"
            sleep $delay
        done
    done

    printf "\r[✔] Terminé !                   \n"
    tput cnorm         # réafficher le curseur
}


###############################################################################
# Fonction alignement - décoration sur 1 ligne
###############################################################################
# ----
# print_fancy - Affichage flexible dans le terminal
#
# Usage :
#   print_fancy [--color couleur] [--bg fond] [--fill caractere] [--align center|left] "Texte à afficher"
#
# Arguments :
#   --color  : variable ANSI pour la couleur du texte (ex: $RED)
#   --bg     : variable ANSI pour la couleur de fond (ex: $BG_BLUE_DARK)
#   --fill   : caractère à répéter avant/après le texte (ex: "=" ou " ")
#   --align  : "center" (par défaut) ou "left"
#   "Texte à afficher" : texte obligatoire, toujours en dernier
#
# Exemples :
#   print_fancy --color "$RED" --fill "=" --align center "Titre décoré centré"
#   print_fancy --bg "$BG_BLUE_DARK" "Hello World"
#   print_fancy "Texte simple à gauche"
# ----
# @description Cette fonction fait ceci et cela.
# @param $1 Description du premier paramètre.
# @param $2 Description du deuxième paramètre.
# @return Description de ce que retourne la fonction (le cas échéant).

print_fancy() {
    local color=""
    local bg=""
    local fill=" "
    local align="center"
    local text=""

    # --- Parsing options ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --color) color="$2"; shift 2 ;;
            --bg)    bg="$2"; shift 2 ;;
            --fill)  fill="$2"; shift 2 ;;
            --align) align="$2"; shift 2 ;;
            *) 
                text="$1"
                shift
                break
                ;;
        esac
    done

    # Récupérer le reste des arguments si texte contient des espaces
    while [[ $# -gt 0 ]]; do
        text+=" $1"
        shift
    done

    [[ -z "$text" ]] && { echo "⚠️ Aucun texte fourni à print_fancy" >&2; return 1; }

    # Calcul longueur et padding
    # Calcul longueur et padding
    local line_len=${#text}
    if (( line_len >= TERM_WIDTH_DEFAULT )); then
        printf "%b%s%b\n" "$color$bg" "$text" "$RESET"
        return
    fi

    if [[ "$align" == "center" ]]; then
        local pad_total=$((TERM_WIDTH_DEFAULT - line_len - 2))
        local pad_side=$((pad_total / 2))
        local pad_left=$(printf '%*s' "$pad_side" '' | tr ' ' "$fill")
        local pad_right=$(printf '%*s' $((pad_total - pad_side)) '' | tr ' ' "$fill")
        printf "%s%b %s %b%s\n" "$pad_left" "$color$bg" "$text" "$RESET" "$pad_right"
    else
        # align left
        printf "%b%s%b\n" "$color$bg" "$text" "$RESET"
    fi
}



###############################################################################
# Fonction d'affichage du tableau récapitulatif avec bordures
###############################################################################

print_aligned_table() {
print_aligned_table() {
    local label="$1"
    local value="$2"
    local label_width=20

    # Calcul de la longueur du label
    local label_len=${#label}
    local spaces=$((label_width - label_len))

    # Génère les espaces à ajouter après le label
    local padding=""
    if (( spaces > 0 )); then
        padding=$(printf '%*s' "$spaces" '')
    fi

    # Affiche la ligne avec label + padding + " : " + value
    printf "%s%s : %s\n" "$label" "$padding" "$value"
}

print_summary_table() {
    END_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "INFOS"
    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    print_aligned_table "Date / Heure début" "$START_TIME"
    print_aligned_table "Date / Heure fin" "$END_TIME"
    print_aligned_table "Mode de lancement" "$LAUNCH_MODE"
    print_aligned_table "Nombre de jobs" "$JOBS_COUNT"
    print_aligned_table "Code erreur" "$ERROR_CODE"
    print_aligned_table "Log INFO" "$LOG_FILE_INFO"
    print_aligned_table "Email envoyé à" "$MAIL_TO"
    print_aligned_table "Sujet email" "$SUBJECT_RAW"
    [[ "$DRY_RUN" == true ]] && print_aligned_table "Simulation (dry-run)" "$MSG_DRYRUN"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    # Ligne finale avec couleur fond jaune foncé, texte noir, centrée
    print_fancy --bg ${BG_YELLOW_DARK} --color ${BLACK} "$MSG_END_REPORT"
    echo
}


###############################################################################
# Colorisation de la sortie rclone (fonction)
# Utilise awk pour des correspondances robustes et insensibles à la casse.
###############################################################################

colorize() {
    awk -v BLUE="$BLUE" -v RED="$RED" -v ORANGE="$ORANGE" -v RESET="$RESET" '
    {
        line = $0
        l = tolower(line)
        # Ajouts / transferts / nouveaux fichiers -> bleu
        if (l ~ /(copied|added|transferred|new|created|renamed|uploaded)/) {
            printf "%s%s%s\n", BLUE, line, RESET
        }
        # Suppressions / erreurs -> rouge
        else if (l ~ /(deleted|delete|error|failed|failed to)/) {
            printf "%s%s%s\n", RED, line, RESET
        }
        # Déjà synchronisé / inchangé / skipped -> orange
        else if (l ~ /(unchanged|already exists|skipped|skipping|there was nothing to transfer|no change)/) {
            printf "%s%s%s\n", ORANGE, line, RESET
        }
        else {
            print line
        }
    }'
}


###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################

print_logo() {
    echo
    echo
    # On colore la bannière avec sed : '#' restent normaux, le reste en rouge
    # Pour simplifier, on colore caractère par caractère via sed
    cat <<'EOF' | sed -E "s/([^#])/${RED}\1${RESET}/g"
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::'######:::::'#######:::'########:::'######:::'##::::'##:::::'###:::::::::
:::::'##... ##:::'##.... ##::... ##..:::'##... ##:: ##:::: ##::::'## ##::::::::
::::: ##:::..:::: ##:::: ##::::: ##::::: ##:::..::: ##:::: ##:::'##:. ##:::::::
::::: ##::'####:: ##:::: ##::::: ##::::: ##:::::::: #########::'##:::. ##::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##:::::::: ##.... ##:: #########::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##::: ##:: ##:::: ##:: ##.... ##::::::
:::::. ######::::. #######:::::: ##:::::. ######::: ##:::: ##:: ##:::: ##::::::
::::::......::::::.......:::::::..:::::::......::::..:::::..:::..:::::..:::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
    echo
    echo
}