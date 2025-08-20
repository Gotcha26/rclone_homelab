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

check_email() {
    local email="$1"
    # Regex basique : texte@texte.domaine
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "${RED}$MSG_MAIL_ERROR : $email${RESET}" >&2
        ERROR_CODE=11
        exit $ERROR_CODE
    fi
}

prepare_mail_html() {
  local file="$1"

  # Charger les dernières lignes dans un tableau
  mapfile -t __lines < <(tail -n "$LOG_LINE_MAX" "$file")
  local total=${#__lines[@]}

  for (( idx=0; idx<total; idx++ )); do
    local line="${__lines[idx]}"

    # 2 lignes vides juste AVANT la 4e ligne en partant du bas
    # if (( total >= 4 && idx == total - 4 )); then
    #   echo "<br><br>"
    # fi

    # Échapper le HTML
    local safe_line
    safe_line=$(printf '%s' "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    # Normalisation pour tests insensibles à la casse
    local lower="${line,,}"

    # Flag gras si on est dans les 4 dernières lignes
    local bold_start=""
    local bold_end=""
    if (( idx >= total - 4 )); then
      bold_start="<b>"
      bold_end="</b>"
    fi

    # Colorisation mail
    if [[ "$lower" == *"--dry-run"* ]]; then
        echo "${bold_start}<span style='color:orange; font-style:italic;'>$safe_line</span>${bold_end}<br>"
    elif [[ "$lower" == *"deleted"* ]]; then
        echo "${bold_start}<span style='color:red;'>$safe_line</span>${bold_end}<br>"
    elif [[ "$lower" == *"copied"* ]]; then
        echo "${bold_start}<span style='color:blue;'>$safe_line</span>${bold_end}<br>"
    elif [[ "$lower" == *"updated"* ]]; then
        echo "${bold_start}<span style='color:orange;'>$safe_line</span>${bold_end}<br>"
    elif [[ "$lower" == *"there was nothing to transfer"* || "$lower" == *"there was nothing to transfert"* ]]; then
        echo "${bold_start}<span style='color:orange;'>$safe_line</span>${bold_end}<br>"
    else
        echo "${bold_start}$safe_line${bold_end}<br>"
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
    local html_block="$2"   # facultatif

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
        if [[ -n "$html_block" ]]; then
            printf "%s" "$html_block"
        else
            prepare_mail_html "$log_file"
        fi
        echo "</div>"

        echo "<hr><h3>📊 Résumé global</h3>"
        local copied=$(grep -c "INFO.*Copied"   "$log_file" || true)
        local updated=$(grep -c "INFO.*Updated" "$log_file" || true)
        local deleted=$(grep -c "INFO.*Deleted" "$log_file" || true)
        # ... après avoir calculé copied/updated/deleted ...

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
    } > "$MAIL"

    # Pièces jointes (logs bruts concaténés)
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
    msmtp --logfile "$LOG_FILE_MAIL" -t < "$MAIL" || echo "$MSG_MSMTP_ERROR" >> "$LOG_FILE_MAIL"
    print_fancy --align "center" "$MSG_EMAIL_SENT"
}

send_email_if_needed() {
    local html_block="$1"
    if [[ -z "$MAIL_TO" ]]; then
        echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    elif ! command -v msmtp >/dev/null 2>&1; then
        echo "${ORANGE}$MSG_MSMTP_NOT_FOUND${RESET}" >&2
        ERROR_CODE=9
    else
        print_fancy --align "center" "$MSG_EMAIL_PREP"
        calculate_subject "$LOG_FILE_INFO"

        # Ici : soit on a un bloc HTML préformaté, soit on laisse assemble_and_send_mail parser
        assemble_and_send_mail "$LOG_FILE_INFO" "$html_block"
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
# print_fancy : Affiche du texte formaté avec couleurs, styles et alignement
#
# Options :
#   --color <code|var>     : Couleur du texte (ex: "$RED" ou "\033[31m")
#   --bg <code|var>        : Couleur de fond (ex: "$BG_BLUE" ou "\033[44m")
#   --fill <char>          : Caractère de remplissage (défaut: espace)
#   --align <center|left>  : Alignement du texte (défaut: center)
#   --style <bold|italic|underline|combinaison>
#                          : Style(s) appliqués au texte
#   --highlight            : Active un surlignage complet (ligne entière)
#   texte ...              : Le texte à afficher (peut contenir des espaces)
#
# Exemple :
#   print_fancy --color "$RED" --bg "$BG_WHITE" --style "bold underline" "Alerte"
#   print_fancy --color "\033[32m" --style italic "Succès en vert"
# ----

print_fancy() {
    local color=""
    local bg=""
    local fill=" "
    local align="center"
    local text=""
    local style=""
    local highlight=""

    # Styles ANSI de base
    local BOLD="\033[1m"
    local ITALIC="\033[3m"
    local UNDERLINE="\033[4m"
    local RESET="\033[0m"

    # Parsing options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --color)     color="$2"; shift 2 ;;
            --bg)        bg="$2"; shift 2 ;;
            --fill)      fill="$2"; shift 2 ;;
            --align)     align="$2"; shift 2 ;;
            --style)     style="$2"; shift 2 ;;   # bold / italic / underline / combinaison
            --highlight) highlight="1"; shift ;;
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

    # Construction de la séquence de style
    local style_seq=""
    [[ "$style" =~ bold ]]      && style_seq+="$BOLD"
    [[ "$style" =~ italic ]]    && style_seq+="$ITALIC"
    [[ "$style" =~ underline ]] && style_seq+="$UNDERLINE"

    # Calcul longueur et padding
    local line_len=${#text}
    if (( line_len >= TERM_WIDTH_DEFAULT )); then
        printf "%b%s%b\n" "${color}${bg}${style_seq}" "$text" "$RESET"
        return
    fi

    if [[ "$align" == "center" ]]; then
        local pad_total=$((TERM_WIDTH_DEFAULT - line_len - 2))
        local pad_side=$((pad_total / 2))
        local pad_left=$(printf '%*s' "$pad_side" '' | tr ' ' "$fill")
        local pad_right=$(printf '%*s' $((pad_total - pad_side)) '' | tr ' ' "$fill")

        if [[ -n "$highlight" ]]; then
            # Ligne complète remplie
            local full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
            local insert_pos=$((pad_side + 1))
            full_line="${full_line:0:$insert_pos}$text${full_line:$((insert_pos + line_len))}"
            printf "%b%s%b\n" "${color}${bg}${style_seq}" "$full_line" "$RESET"
        else
            printf "%s%b %s %b%s\n" "$pad_left" "${color}${bg}${style_seq}" "$text" "$RESET" "$pad_right"
        fi
    else
        # align left
        if [[ -n "$highlight" ]]; then
            local full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
            full_line="${text}$(printf '%*s' $((TERM_WIDTH_DEFAULT - line_len)) '' | tr ' ' "$fill")"
            printf "%b%s%b\n" "${color}${bg}${style_seq}" "$full_line" "$RESET"
        else
            printf "%b%s%b\n" "${color}${bg}${style_seq}" "$text" "$RESET"
        fi
    fi
}



###############################################################################
# Fonction d'affichage du tableau récapitulatif avec bordures
###############################################################################

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
    print_aligned_table "Dossier" "$LOG_DIR"
    print_aligned_table "Log script" "$FILE_SCRIPT"
    print_aligned_table "Log rclone" "$FILE_INFO"
    print_aligned_table "Log mail" "$FILE_MAIL"
    print_aligned_table "Email envoyé à" "$MAIL_TO"
    print_aligned_table "Sujet email" "$SUBJECT_RAW"
    [[ "$DRY_RUN" == true ]] && print_aligned_table "Simulation (dry-run)" "$MSG_DRYRUN"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    # Ligne finale avec couleur fond jaune foncé, texte noir, centrée
    print_fancy --bg ${YELLOW_DARK} --color ${BLACK} "$MSG_END_REPORT"
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