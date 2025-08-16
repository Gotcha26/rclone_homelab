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
  - Vérifie la présence du dossier temporaire : $TMP_RCLONE
  - Lance 'rclone sync' pour chaque job avec les options par défaut
  - Affiche la sortie colorisée dans le terminal
  - Génère un fichier log INFO dans : $LOG_DIR
  - Si --mailto est fourni et msmtp est configuré, envoie un rapport HTML

EOF
}

###############################################################################
# Fonction MAIL
###############################################################################
# === Fonction HTML pour logs partiels ===
log_to_html() {
  local file="$1"
  local buffer=""
  while IFS= read -r line; do
    safe_line=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    if [[ "$line" == *"Deleted"* ]]; then
      buffer+="<span style='color:red;'>$safe_line</span><br>"
    elif [[ "$line" == *"Copied"* ]]; then
      buffer+="<span style='color:blue;'>$safe_line</span><br>"
    elif [[ "$line" == *"Updated"* ]]; then
      buffer+="<span style='color:orange;'>$safe_line</span><br>"
    elif [[ "$line" == *"NOTICE"* ]]; then
      buffer+="<b>$safe_line</b><br>"
    else
      buffer+="$safe_line<br>"
    fi
  done < <(tail -n "$LOG_LINE_MAX" "$file")
  echo "$buffer"
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
# Fonction pour centrer une ligne avec des '=' de chaque côté + coloration
###############################################################################
print_centered_line() {
    local line="$1"
    local term_width=$((TERM_WIDTH_DEFAULT - 2))   # <- Force largeur fixe à 80-2

    # Calcul longueur visible (sans séquences d’échappement)
    local line_len=${#line}

    local pad_total=$((term_width - line_len))
    local pad_side=0
    local pad_left=""
    local pad_right=""

    if (( pad_total > 0 )); then
        pad_side=$((pad_total / 2))
        # Si pad_total est impair, on met un '=' en plus à droite
        pad_left=$(printf '=%.0s' $(seq 1 $pad_side))
        pad_right=$(printf '=%.0s' $(seq 1 $((pad_side + (pad_total % 2)))))
    fi

    # Coloriser uniquement la partie texte, pas les '='
    printf "%s%s %s %s%s\n" "$pad_left" "$BG_BLUE_DARK" "$line" "$RESET" "$pad_right"
}

###############################################################################
# Fonction pour centrer une ligne dans le terminal (simple, sans décor ni couleur)
###############################################################################
print_centered_text() {
    local line="$1"
    local term_width=${2:-$TERM_WIDTH_DEFAULT}  # largeur par défaut = TERM_WIDTH_DEFAULT
    local line_len=${#line}

    if (( line_len >= term_width )); then
        # Si la ligne est plus longue que la largeur, on l’affiche telle quelle
        echo "$line"
        return
    fi

    local pad_total=$((term_width - line_len))
    local pad_side=$((pad_total / 2))
    local pad_left=$(printf ' %.0s' $(seq 1 $pad_side))
    local pad_right=$(printf ' %.0s' $(seq 1 $((pad_total - pad_side))))

    echo "${pad_left}${line}${pad_right}"
}

###############################################################################
# Fonction d'affichage du tableau récapitulatif avec bordures
###############################################################################
print_aligned() {
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

    print_aligned "Date / Heure début" "$START_TIME"
    print_aligned "Date / Heure fin" "$END_TIME"
    print_aligned "Mode de lancement" "$LAUNCH_MODE"
    print_aligned "Nombre de jobs" "$JOBS_COUNT"
    print_aligned "Code erreur" "$ERROR_CODE"
    print_aligned "Log INFO" "$LOG_FILE_INFO"
	print_aligned "Email envoyé à" "$MAIL_TO"
	print_aligned "Sujet email" "$SUBJECT_RAW"
	if $DRY_RUN; then
		print_aligned "Simulation (dry-run)" "$MSG_DRYRUN"
	fi

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

	# Ligne finale avec couleur fond jaune foncé, texte noir, centrée max 80
    local text="$MSG_END_REPORT"
    local term_width="$TERM_WIDTH_DEFAULT"
    local text_len=${#text}
    local pad_total=$((term_width - text_len))
    local pad_side=0
    local pad_left=""
    local pad_right=""
    if (( pad_total > 0 )); then
        pad_side=$((pad_total / 2))
        pad_left=$(printf ' %.0s' $(seq 1 $pad_side))
        pad_right=$(printf ' %.0s' $(seq 1 $((pad_side + (pad_total % 2)))))
    fi
    printf "%b%s%s%s%s%b\n" "${BG_YELLOW_DARK}${BOLD}${BLACK}" "$pad_left" "$text" "$pad_right" "${RESET}" ""
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

# Affiche le logo uniquement si on n'est pas en mode "automatique"
if [[ "$LAUNCH_MODE" != "automatique" ]]; then
    print_logo
fi
