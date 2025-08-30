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
        print_fancy --theme "error" "$MSG_REMOTE_UNKNOW : $remote" >&2
        echo
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
        print_fancy --theme "error" "$MSG_MAIL_ERROR : $email" >&2
        echo
        ERROR_CODE=11
        exit $ERROR_CODE
    fi
}

# Déterminer le sujet brut (SUBJECT_RAW) toujours
# Evite les erreur lorsque aucun mail n'est saisie et est nécessaire pour notification Discord
calculate_subject_raw() {
    local log_file="$1"
    if grep -iqE "(error|failed|failed to)" "$log_file"; then
        SUBJECT_RAW="$MSG_EMAIL_FAIL"
    elif grep -q "There was nothing to transfer" "$log_file"; then
        SUBJECT_RAW="$MSG_EMAIL_SUSPECT"
    else
        SUBJECT_RAW="$MSG_EMAIL_SUCCESS"
    fi
}

prepare_mail_html() {
  local file="$1"

  # Charger les dernières lignes dans un tableau
  mapfile -t __lines < <(tail -n "$LOG_LINE_MAX" "$file")
  local total=${#__lines[@]}

  for (( idx=0; idx<total; idx++ )); do
    local line="${__lines[idx]}"

    # Supprimer espaces en début/fin et ignorer lignes vides
    local trimmed_line
    trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$trimmed_line" ]] && continue

    # Échapper le HTML
    local safe_line
    safe_line=$(printf '%s' "$trimmed_line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    # Normalisation pour tests insensibles à la casse
    local lower="${trimmed_line,,}"

    # Colorisation mail (équivalent à colorize())
    if [[ "$lower" == *"--dry-run"* ]]; then
        echo "<span style='color:orange; font-style:italic;'>$safe_line</span><br>"
    elif [[ "$lower" =~ \b(delete|deleted)\b ]]; then
        # Rouge simple
        echo "<span style='color:red;'>$safe_line</span><br>"
    elif [[ "$lower" =~ (error|failed|unauthenticated|io error|io errors|not deleting) ]]; then
        # Rouge gras
        echo "<span style='color:red; font-weight:bold;'>$safe_line</span><br>"
    elif [[ "$lower" =~ (copied|added|transferred|new|created|renamed|uploaded) ]]; then
        echo "<span style='color:blue;'>$safe_line</span><br>"
    elif [[ "$lower" =~ (unchanged|already exists|skipped|skipping|there was nothing to transfer|no change) ]]; then
        echo "<span style='color:orange;'>$safe_line</span><br>"
    else
        echo "$safe_line<br>"
    fi
  done
}


# Encodage MIME UTF-8 Base64 du sujet
encode_subject_for_email() {
    local log_file="$1"
    calculate_subject_raw "$log_file"
    SUBJECT="=?UTF-8?B?$(printf "%s" "$SUBJECT_RAW" | base64 -w0)?="
}

assemble_and_send_mail() {
    local log_file="$1"        # Fichier log utilisé pour calcul du résumé global (copied/updated/deleted)
    local html_block="$2"      # Bloc HTML global déjà préparé (tous les jobs), facultatif
    local MAIL="${TMP_RCLONE}/rclone_mail_$$.tmp"  # <- fichier temporaire unique

    # Récupération de l'adresse expéditeur depuis msmtp
    FROM_ADDRESS="$(grep '^from' /etc/msmtprc | awk '{print $2}')"

    {
        # --- Entêtes de l'email ---
        echo "From: \"$MAIL_DISPLAY_NAME\" <$FROM_ADDRESS>"     # Laisser msmtp gérer l'expéditeur configuré
        echo "To: $MAIL_TO"
        echo "Date: $(date -R)"
        echo "Subject: $SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"BOUNDARY123\""
        echo

        # --- Partie HTML principale ---
        echo "--BOUNDARY123"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        echo "<html><body style='font-family: monospace; background-color: #f9f9f9; padding: 1em;'>"
        echo "<h2>📤 Rapport de synchronisation Rclone – $NOW</h2>"

        echo "<p><b>📝 Dernières lignes du log :</b></p>"
        echo "<div style='background:#eee; padding:1em; border-radius:8px; font-family: monospace;'>"

        if [[ -n "$html_block" ]]; then
            # Si plusieurs jobs sont présents, insérer des séparateurs <hr> entre eux
            # Suppression de doublons de <hr> pour sécurité
            printf "%s" "$html_block" | awk '
            BEGIN { first=1 }
            /<hr>/ { if(!first) print "<br><hr><br>"; next }
            { first=0; print }
            '
        else
            # Cas fallback : un seul fichier log
            prepare_mail_html "$log_file"
        fi

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
    } > "$MAIL"

    # --- Pièces jointes (logs bruts concaténés) ---
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

    # --- Envoi du mail ---
    msmtp --logfile "$LOG_FILE_MAIL" -t < "$MAIL" || echo "$MSG_MSMTP_ERROR" >> "$LOG_FILE_MAIL"
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
        ERROR_CODE=9
    else
        print_fancy --align "center" "$MSG_EMAIL_PREP"
        encode_subject_for_email "$LOG_FILE_INFO"

        # Ici : soit on a un bloc HTML préformaté, soit on laisse assemble_and_send_mail parser
        assemble_and_send_mail "$JOB_LOG_EMAIL" "$html_block"
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
            printf "\r[%c] Traitement du JOB en cours..." "${spinstr:i:1}"
            sleep $delay
        done
    done

    printf "\r[✔] Terminé !                   \n"
    tput cnorm         # réafficher le curseur
}


###############################################################################
# Fonctions additionnels pour print_fancy()
###############################################################################

# --- Déclarations globales pour print_fancy ---
# + ajoute 'reset' (et 'default' si tu veux) aux maps
declare -A FG_COLORS=(
  [reset]=0 [default]=39
  [black]=30 [red]=31 [green]=32 [yellow]=33 [blue]=34 [magenta]=35 [cyan]=36 [white]=37
  [gray]=90 [light_red]=91 [light_green]=92 [light_yellow]=93 [light_blue]=94 [light_magenta]=95 [light_cyan]=96 [bright_white]=97
)
declare -A BG_COLORS=(
  [reset]=49 [default]=49
  [black]=40 [red]=41 [green]=42 [yellow]=43 [blue]=44 [magenta]=45 [cyan]=46 [white]=47
  [gray]=100 [light_red]=101 [light_green]=102 [light_yellow]=103 [light_blue]=104 [light_magenta]=105 [light_cyan]=106 [bright_white]=107
)

get_fg_color() {
  local c="$1"
  [[ -z "$c" ]] && return 0
  if [[ -n "${FG_COLORS[$c]+_}" ]]; then
    # reset=0 -> \033[0m ; default=39 -> \033[39m ; etc.
    printf "\033[%sm" "${FG_COLORS[$c]}"
  else
    # codes bruts (ex: $'\e[38;5;208m')
    printf "%s" "$c"
  fi
}

get_bg_color() {
  local c="$1"
  [[ -z "$c" || "$c" == "none" || "$c" == "transparent" ]] && return 0
  if [[ -n "${BG_COLORS[$c]+_}" ]]; then
    printf "\033[%sm" "${BG_COLORS[$c]}"
  else
    printf "%s" "$c"
  fi
}


###############################################################################
# Fonction alignement - décoration sur 1 ligne
###############################################################################
# ----
# print_fancy : Affiche du texte formaté avec couleurs, styles et alignement
#
# Options :
#   --theme <success|error|warning|info>
#                          : Thème appliqué avec mise en page + emoji
#   --color <code|var>     : Couleur du texte (ex: "red" ou "31")
#   --bg <code|var>        : Couleur de fond (ex: "blue" ou "44")
#   --fill <char>          : Caractère de remplissage (défaut: espace)
#   --align <center|left|right>  : Alignement du texte (défaut: center)
#   --style <bold|italic|underline|combinaison>
#                          : Style(s) appliqués au texte
#   --highlight            : Active un surlignage complet (ligne entière)
#   --icon                 : Ajoute une icone (emoji) en debut de texte.
#   texte ... [OBLIGATOIRE]: Le texte à afficher (peut contenir des espaces)
#
# Exemple :
#   print_fancy --color red --bg white --style "bold underline" "Alerte"
#   print_fancy --color 42 --style italic "Succès en vert"
#   print_fancy --theme success "Backup terminé avec succès"
#   print_fancy --theme error --align right "Erreur critique détectée"
#   print_fancy --theme warning --highlight "Attention : espace disque faible"
#   print_fancy --theme info "Démarrage du service..."
#   print_fancy --theme info --icon "🚀" "Lancement en cours..."
# ----

print_fancy() {
    local color=""
    local bg=""
    local fill=" "
    local align="center"
    local text=""
    local style=""
    local highlight=""
    local theme=""
    local icon=""

    local BOLD="\033[1m"
    local ITALIC="\033[3m"
    local UNDERLINE="\033[4m"
    local RESET="\033[0m"

    # Lecture des arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --color)     color="$2"; shift 2 ;;
            --bg)        bg="$2"; shift 2 ;;
            --fill)      fill="$2"; shift 2 ;;
            --align)     align="$2"; shift 2 ;;
            --style)     style="$2"; shift 2 ;;
            --highlight) highlight="1"; shift ;;
            --theme)     theme="$2"; shift 2 ;;
            --icon)      icon="$2 "; shift 2 ;;
            *) text="$1"; shift; break ;;
        esac
    done

    while [[ $# -gt 0 ]]; do text+=" $1"; shift; done
    [[ -z "$text" ]] && { echo "$MSG_PRINT_FANCY_EMPTY" >&2; return 1; }

    # Application du thème (valeurs par défaut)
    case "$theme" in
        success) [[ -z "$icon" ]] && icon="✅  " ; [[ -z "$color" ]] && color="green"; [[ -z "$style" ]] && style="bold" ;;
        error)   [[ -z "$icon" ]] && icon="❌  " ; [[ -z "$color" ]] && color="red"; [[ -z "$style" ]] && style="bold" ;;
        warning) [[ -z "$icon" ]] && icon="⚠️  " ; [[ -z "$color" ]] && color="yellow"; [[ -z "$style" ]] && style="bold" ;;
        info)    [[ -z "$icon" ]] && icon="ℹ️  " ; [[ -z "$color" ]] && color="light_blue"; [[ -z "$style" ]] && style="italic" ;;
    esac

    # Ajout de l’icône si définie
    text="$icon$text"

    # --- Traduction des couleurs sûres même si valeurs inconnues ou vides ---

    # Couleur du texte
    if [[ "$color" =~ ^\\e ]]; then
        :  # laisse la séquence telle quelle
    else
        color=$(get_fg_color "${color:-white}")
    fi
    # Couleur du fond
    if [[ "$bg" =~ ^\\e ]]; then
        :  # rien à faire, la séquence est déjà complète
    else
        bg=$(get_bg_color "$bg")
    fi

    local style_seq=""
    [[ "$style" =~ bold ]] && style_seq+="$BOLD"
    [[ "$style" =~ italic ]] && style_seq+="$ITALIC"
    [[ "$style" =~ underline ]] && style_seq+="$UNDERLINE"

    local visible_len=${#text}
    local pad_left=0
    local pad_right=0

    case "$align" in
        center)
            local total_pad=$((TERM_WIDTH_DEFAULT - visible_len))
            pad_left=$(( (total_pad+1)/2 ))
            pad_right=$(( total_pad - pad_left ))
            ;;
        right)
            pad_left=$((TERM_WIDTH_DEFAULT - visible_len - 1))
            (( pad_left < 0 )) && pad_left=0
            ;;
        left)
            pad_right=$((TERM_WIDTH_DEFAULT - visible_len))
            ;;
    esac

    local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
    local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
    local suffix=""

    [[ "$align" == "right" ]] && suffix=" $RESET" || suffix="$RESET"

    local line="${pad_left_str}${color}${bg}${style_seq}${text}${suffix}${pad_right_str}"

    if [[ -n "$highlight" ]]; then
        local full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
        local insert_pos=$pad_left
        full_line="${full_line:0:$insert_pos}${color}${bg}${style_seq}${text}${suffix}${full_line:$((insert_pos+visible_len))}"
        printf "%s\n" "$full_line"
    else
        printf "%b\n" "$line"
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
    print_aligned_table "Dossier" "${LOG_DIR}/"
    print_aligned_table "Log script" "$FILE_SCRIPT"
    print_aligned_table "Log rclone" "$FILE_INFO"
    print_aligned_table "Log mail" "$FILE_MAIL"
    print_aligned_table "Email envoyé à" "$MAIL_TO"
    print_aligned_table "Sujet email" "$SUBJECT_RAW"

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_PROCESSED"
    else
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_ABORDED"
    fi

    [[ "$DRY_RUN" == true ]] && print_aligned_table "Simulation (dry-run)" "$MSG_DRYRUN"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    # Ligne finale avec couleur fond jaune foncé, texte noir, centrée
    print_fancy --bg "yellow" --color "black" "$MSG_END_REPORT"
    echo
}


###############################################################################
# Colorisation de la sortie rclone (fonction)
# Utilise awk pour des correspondances robustes et insensibles à la casse.
###############################################################################

colorize() {
    local BLUE=$(get_fg_color "blue")
    local RED=$(get_fg_color "red")
    local RED_BOLD=$'\033[1;31m'   # rouge gras
    local ORANGE=$(get_fg_color "yellow")
    local RESET=$'\033[0m'

    awk -v BLUE="$BLUE" -v RED="$RED" -v RED_BOLD="$RED_BOLD" -v ORANGE="$ORANGE" -v RESET="$RESET" '
    {
        line = $0
        l = tolower(line)
        # Ajouts / transferts / nouveaux fichiers -> bleu
        if (l ~ /(copied|added|transferred|new|created|renamed|uploaded)/) {
            printf "%s%s%s\n", BLUE, line, RESET
        }
        # Suppressions -> rouge simple
        else if (l ~ /\b(delete|deleted)\b/) {
            printf "%s%s%s\n", RED, line, RESET
        }
        # Erreurs et échecs -> rouge gras
        else if (l ~ /(error|failed|unauthenticated|io error|io errors|not deleting)/) {
            printf "%s%s%s\n", RED_BOLD, line, RESET
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
# Fonction : créer une version sans couleurs ANSI d’un log
###############################################################################
make_plain_log() {
    local src_log="$1"
    local dest_log="$2"

    sed 's/\x1b\[[0-9;]*m//g' "$src_log" > "$dest_log"
}


###############################################################################
# Fonction : envoyer une notification Discord avec sujet + log attaché
###############################################################################
send_discord_notification() {
    local log_file="$1"

    # Si pas de webhook défini → sortir silencieusement
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && return 0

    calculate_subject_raw "$LOG_FILE_INFO"

    # Message principal = même sujet que l'email
    local message="📢 **$SUBJECT_RAW** – $NOW"

    # Envoi du message + du log en pièce jointe
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
        -F "payload_json={\"content\": \"$message\"}" \
        -F "file=@$log_file" \
        > /dev/null

    # On considère qu’à partir du moment où la fonction est appelée, on annonce un succès
    print_fancy --align "center" "$MSG_DISCORD_SENT"
}


###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################

print_logo() {
    echo
    echo
    local RED="$(get_fg_color red)"
    local RESET="$(get_fg_color reset)"

    # Règle "tout sauf #"
    sed -E "s/([^#])/${RED}\1${RESET}/g" <<'EOF'
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
    print_fancy --align "right" "$VERSION"
    echo
    echo
}


###############################################################################
# Fonction : Vérifie s'il existe une nouvelle release ou branche
# NE MODIFIE PAS le dépôt
###############################################################################
check_update() {
    # Récupère le tag du dernier release publié sur GitHub
    latest=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
             | grep -oP '"tag_name": "\K(.*)(?=")')

    if [ -n "$latest" ]; then
        if [ "$latest" != "$VERSION" ]; then
            MSG_MAJ_UPDATE1=$(printf "$MSG_MAJ_UPDATE_TEMPLATE" "$latest" "$VERSION")
            echo
            print_fancy --align "left" --color "green" --style "italic" "$MSG_MAJ_UPDATE1"
            print_fancy --align "center" --color "green" --style "italic" "$MSG_MAJ_UPDATE2"
        fi
    else
        print_fancy --color "red" --bg "white" --style "bold underline" "$MSG_MAJ_ERROR"
    fi
}

###############################################################################
# Fonction : Met à jour le script vers la dernière branche (forcée)
# Appel explicite uniquement
###############################################################################
force_update_branch() {
    local branch="${FORCE_BRANCH:-main}"
    MSG_MAJ_UPDATE_BRANCH=$(printf "$MSG_MAJ_UPDATE_BRANCH_TEMPLATE" "$branch")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_BRANCH"

    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    # Récupération des dernières infos du remote
    git fetch --all --tags

    # Assure que l'on est bien sur la branche souhaitée
    git checkout -f "$branch" || { echo "Erreur lors du checkout de $branch" >&2; exit 1; }

    # Écrase toutes les modifications locales, y compris fichiers non suivis
    git reset --hard "origin/$branch"
    git clean -fd

    # Rendre le script principal exécutable
    chmod +x "$SCRIPT_DIR/rclone_sync_main.sh"

    print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_BRANCH_SUCCESS"

    # Quitter immédiatement pour que le script relancé prenne en compte la mise à jour
    exit 0
}


###############################################################################
# Fonction : Met à jour le script vers la dernière release (dernier tag)
# Appel explicite uniquement.
###############################################################################
update_to_latest_tag() {
    cd "$SCRIPT_DIR" || { echo "$MSG_MAJ_ACCESS_ERROR" >&2; exit 1; }

    git fetch --tags

    # Dernier tag distant
    local latest_tag
    latest_tag=$(git tag -l | sort -V | tail -n1)

    # Hash du tag distant et hash local
    local remote_hash
    remote_hash=$(git rev-parse "$latest_tag")
    local local_hash
    local_hash=$(git rev-parse HEAD)

    MSG_MAJ_UPDATE_RELEASE=$(printf "$MSG_MAJ_UPDATE_RELEASE_TEMPLATE" "$latest_tag")
    echo
    print_fancy --align "center" --bg "green" --style "italic" "$MSG_MAJ_UPDATE_RELEASE"

    if [[ "$remote_hash" != "$local_hash" ]]; then
        # Essayer le checkout sécurisé sans message detached HEAD
        if git -c advice.detachedHead=false checkout "$latest_tag"; then
            chmod +x "$SCRIPT_DIR/rclone_sync_main.sh"
            MSG_MAJ_UPDATE_TAG_SUCCESS=$(printf "$MSG_MAJ_UPDATE_TAG_SUCCESS_TEMPLATE" "$latest_tag")
            print_fancy --align "center" --theme "success" "$MSG_MAJ_UPDATE_TAG_SUCCESS"
            exit 0  # Quitter après succès
        else
            # Si échec (modifications locales)
            MSG_MAJ_UPDATE_TAG_FAILED=$(printf "$MSG_MAJ_UPDATE_TAG_FAILED_TEMPLATE" "$latest_tag")
            print_fancy --align "center" --theme "error" "$MSG_MAJ_UPDATE_TAG_FAILED"
            exit 1  # Quitter après échec
        fi
    else
        MSG_MAJ_UPDATE_TAG_REJECTED=$(printf "$MSG_MAJ_UPDATE_TAG_REJECTED_TEMPLATE" "$latest_tag")
        print_fancy --align "center" --theme "info" "$MSG_MAJ_UPDATE_TAG_REJECTED"
        exit 0  # Quitter même si rien à faire
    fi
}