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
# Fonction pour parser et vérifier les jobs
###############################################################################
# Déclarer le tableau global pour stocker les jobs
declare -a JOBS_LIST    # Liste des jobs src|dst
declare -A JOB_STATUS   # idx -> OK/PROBLEM

parse_jobs() {
    local file="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Nettoyage : trim + séparateurs
        line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
        IFS='|' read -r src dst <<< "$line"

        # Trim
        src="${src#"${src%%[![:space:]]*}"}"
        src="${src%"${src##*[![:space:]]}"}"
        dst="${dst#"${dst%%[![:space:]]*}"}"
        dst="${dst%"${dst##*[![:space:]]}"}"

        # Vérif source locale
        if [[ ! -d "$src" ]]; then
            print_fancy --theme "error" "$MSG_SRC_NOT_FOUND : $src"
            echo
            ERROR_CODE=7
            exit $ERROR_CODE
        fi

        # Stocker la paire src|dst, sans statut
        JOBS_LIST+=("$src|$dst")

    done < "$file"

    # --- Initialiser tous les jobs à OK ---
    # On les suposes OK avant de changer ce status.
    for idx in "${!JOBS_LIST[@]}"; do
        JOB_STATUS[$idx]="OK"
    done
}


###############################################################################
# Fonction pour vérifier et éventuellement reconnecter un remote avec timeout
###############################################################################
declare -A REMOTE_STATUS   # remote_name -> OK / PROBLEM

check_remote_non_blocking() {
    local remote="$1"
    local timeout_duration=30s  # Temps max pour chaque test/reconnect

    local remote_type
    remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')

    REMOTE_STATUS["$remote"]="OK"
    local msg_status=""

    if [[ "$remote_type" == "onedrive" || "$remote_type" == "drive" ]]; then
        if ! timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
            print_fancy --theme "info" "Remote '$remote' inaccessible. Tentative de reconnect..."
            if timeout "$timeout_duration" rclone reconnect "${remote}:" >/dev/null 2>&1; then
                print_fancy --theme "info" "Reconnect OK, vérification..."
                if ! timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
                    REMOTE_STATUS["$remote"]="PROBLEM"
                    msg_status="inaccessible malgré reconnect"
                else
                    REMOTE_STATUS["$remote"]="OK"
                    msg_status="accessible après reconnect ✅"
                fi
            else
                REMOTE_STATUS["$remote"]="PROBLEM"
                msg_status="Reconnect échoué, remote inaccessible  ⚠️"
            fi

            # ❗ Marquer tous les jobs qui utilisent ce remote comme PROBLEM
            for i in "${!JOBS_LIST[@]}"; do
                [[ "${JOBS_LIST[$i]}" == *"$remote:"* ]] && {
                    JOB_STATUS[$i]="PROBLEM"
                    warn_remote_problem "$remote" "$remote_type" "$i"
                }
            done
        else
            msg_status="accessible ✅"
        fi
    else
        msg_status="accessible ✅"
    fi

    # Affichage stylisé
    if [[ "${REMOTE_STATUS[$remote]}" == "PROBLEM" ]]; then
        print_fancy --theme "warning" "Remote '$remote' $msg_status"
        echo
    else
        print_fancy --theme "success" "Remote '$remote' $msg_status"
    fi
}


###############################################################################
# Fonction pour parcourir tous les remotes avec exécution parallèle
###############################################################################
check_remotes() {
    for job in "${JOBS_LIST[@]}"; do
        IFS='|' read -r src dst <<< "$job"
        if [[ "$dst" == *":"* ]]; then
            local remote="${dst%%:*}"
            # Vérification unique par remote
            [[ -z "${REMOTE_STATUS[$remote]+x}" ]] && check_remote_non_blocking "$remote"
        fi
    done
}


###############################################################################
# Fonction : Avertissement remote inaccessible
###############################################################################
declare -A JOB_MSG         # idx -> message d'erreur détaillé

warn_remote_problem() {
    local remote="$1"
    local remote_type="$2"
    local job_idx="$3"     # optionnel, pour associer message JOB_MSG

    local msg
    msg="❌  \e[1;33mAttention\e[0m : le remote '\e[1m$remote\e[0m' est \e[31minaccessible\e[0m pour l'écriture.
    
    "

    case "$remote_type" in
        onedrive)
            msg+="
Ce problème est typique de \e[36mOneDrive\e[0m : le token OAuth actuel
ne permet plus l'écriture, même si la lecture fonctionne.
Il faut refaire complètement la configuration du remote :
  1. Supprimer ou éditer le remote existant : \e[1mrclone config\e[0m
  2. Reconnecter le remote et accepter toutes les permissions
     (\e[32mlecture\e[0m + \e[32mécriture\e[0m).
  3. Commande pour éditer directement le fichier de conf. de rclone :
     \e[1mnano ~/.config/rclone/rclone.conf\e[0m
"
            ;;
        drive)
            msg+="
Ce problème peut se produire sur \e[36mGoogle Drive\e[0m si le token
OAuth est expiré ou si les scopes d'accès sont insuffisants.
Pour résoudre le problème :
  1. Supprimer ou éditer le remote existant : \e[1mrclone config\e[0m
  2. Reconnecter le remote et accepter toutes les permissions nécessaires.
  3. Commande pour éditer directement le fichier de conf. de rclone :
     \e[1mnano ~/.config/rclone/rclone.conf\e[0m
"
            ;;
        *)
            msg+="
Le problème provient probablement du token ou des permissions.
Vérifiez la configuration du remote avec : \e[1mrclone config\e[0m
"
            ;;
    esac

    msg+="
Les jobs utilisant ce remote seront \e[31mignorés\e[0m jusqu'à résolution.
"

    # Affichage à l’écran
    echo -e "\n$msg"

    # Associer au JOB_MSG si job_idx fourni
    [[ -n "$job_idx" ]] && JOB_MSG["$job_idx"]="$msg"
}


###############################################################################
# Fonction de création de fichiers (log) pour chaque job traité
###############################################################################
init_job_logs() {
    local job_id="$1"

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${JOB_ID}_raw.log"       # Spécifique à la sortie de rclone
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${JOB_ID}_html.log"     # Spécifique au formatage des balises HTML
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${JOB_ID}_plain.log"   # Version simplifié de raw, débarassée des codes ANSI / HTML
}


###############################################################################
# Fonction de convertion des formats
###############################################################################
generate_logs() {
    local raw_log="$1"
    local html_log="$2"
    local plain_log="$3"

    # 1) Créer la version propre (sans ANSI)
    make_plain_log "$raw_log" "$plain_log"

    # 2) Construire le HTML à partir de la version propre
    [[ -n "$html_log" ]] && prepare_mail_html "$plain_log" > "$html_log"
}


###############################################################################
# Fonction : créer une version sans couleurs ANSI d’un log
###############################################################################
make_plain_log() {
    local src_log="$1"
    local dest_log="$2"

    # On bosse en mode binaire (pas de conversion d’encodage)
    perl -pe '
        # --- 1) Séquences ANSI réelles (ESC) ---
        s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g;        # CSI ... command (SGR, etc.)
        s/\x1B\][^\x07]*(?:\x07|\x1B\\)//g;     # OSC ... BEL ou ST
        s/\x1B[@-Z\\-_]//g;                     # Codes 2 octets (RIS, etc.)

        # --- 2) Versions "littérales" écrites dans les strings ---
        s/\\e\[[0-9;?]*[ -\/]*[@-~]//g;         # \e[ ... ]
        s/\\033\[[0-9;?]*[ -\/]*[@-~]//g;       # \033[ ... ]
        s/\\x1[bB]\[[0-9;?]*[ -\/]*[@-~]//g;    # \x1b[ ... ] ou \x1B[ ... ]

        # --- 3) Retire les \r éventuels (progrès/spinners) ---
        s/\r//g;
    ' "$src_log" > "$dest_log"
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
        ERROR_CODE=12
        exit $ERROR_CODE
    fi
}

# Déterminer le sujet brut (SUBJECT_RAW) pour un job passé.
# Valable pour un fichier concaténé ou job individuel
# Evite les erreur lorsque aucun mail n'est saisie et est nécessaire pour notification Discord
calculate_subject_raw_for_job() {
    local job_log_file="$1"

    if grep -iqE "(error|failed|unauthenticated|io error|io errors|not deleting)" "$job_log_file"; then
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
    if grep -iqE "(error|failed|unauthenticated|io error|io errors|not deleting)" "$file"; then
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
        [[ -z "$trimmed_line" ]] && continue

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
        elif [[ "$lower" =~ (error|failed|unauthenticated|io error|io errors|not deleting) ]]; then
            line_html="<span style='color:red; font-weight:bold;'>$safe_line</span><br>"
        elif [[ "$lower" =~ (copied|added|transferred|new|created|renamed|uploaded) ]]; then
            line_html="<span style='color:blue;'>$safe_line</span><br>"
        elif [[ "$lower" =~ (unchanged|already exists|skipped|skipping|there was nothing to transfer|no change) ]]; then
            line_html="<span style='color:orange;'>$safe_line</span><br>"
        else
            line_html="$safe_line<br>"
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
    local MAIL="${TMP_RCLONE}/rclone_mail_$$.tmp"  # <- fichier temporaire unique

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
        assemble_and_send_mail "$TMP_JOB_LOG_HTML" "$html_block"
    fi
}



###############################################################################
# Fonction spinner
###############################################################################

spinner() {
    local pid=$1       # PID du processus à surveiller
    local delay=0.1    # vitesse du spinner
    local spinstr='|/-\'

    # Couleurs
    local ORANGE=$'\033[38;5;208m'
    local GREEN=$(get_fg_color "green")
    local RESET=$'\033[0m'

    tput civis  # cacher le curseur

    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r[${ORANGE}%c${RESET}] Traitement du JOB en cours..." "${spinstr:i:1}"
            sleep $delay
        done
    done

    printf "\r[${GREEN}✔${RESET}] Terminé !                   \n"
    tput cnorm  # réafficher le curseur
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
#   --fg <code|var>     : Couleur du texte (ex: "red" ou "31")
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
#   print_fancy --fg red --bg white --style "bold underline" "Alerte"
#   print_fancy --fg 42 --style italic "Succès en vert"
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
            --fg)     color="$2"; shift 2 ;;
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

    if [[ -n "$highlight" ]]; then
        # Ligne complète remplie avec le fill
        local full_line
        full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
        # Insérer le texte avec style et couleur
        full_line="${full_line:0:pad_left}${color}${bg}${style_seq}${text}${RESET}${bg}${full_line:$((pad_left + visible_len))}"
        # Appliquer la couleur de fond sur toute la ligne
        printf "%b\n" "${bg}${full_line}${RESET}"
    else
        # Version classique sans highlight
        local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
        local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
        printf "%b\n" "${pad_left_str}${color}${bg}${style_seq}${text}${RESET}${pad_right_str}"
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
    print_aligned_table "Nb. de jobs traités" "${EXECUTED_JOBS} / ${#JOBS_LIST[@]}"
    print_aligned_table "Code erreur" "$ERROR_CODE"
    print_aligned_table "Dossier" "${LOG_DIR}/"
    print_aligned_table "Log script" "$FILE_SCRIPT"
    print_aligned_table "Log mail" "$FILE_MAIL"
    print_aligned_table "Log rclone" "$FILE_INFO"

    if [[ -n "$MAIL_TO" ]]; then
        print_aligned_table "Email envoyé à" "$MAIL_TO"
        print_aligned_table "Sujet email" "$SUBJECT_RAW"
    fi

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_PROCESSED"
    else
        print_aligned_table "Notifs Discord" "$MSG_DISCORD_ABORDED"
    fi

    [[ "$DRY_RUN" == true ]] && print_aligned_table "Simulation (dry-run)" "$MSG_DRYRUN"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='

    # Ligne finale avec couleur fond jaune foncé, texte noir, centrée
    print_fancy --bg "yellow" --fg "black" "$MSG_END_REPORT"
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
# Fonction : envoyer une notification Discord avec sujet + log attaché
###############################################################################
send_discord_notification() {
    local log_file="$1"

    # Si pas de webhook défini → sortir silencieusement
    [[ -z "$DISCORD_WEBHOOK_URL" ]] && return 0

    # Sujet calculé pour CE job
    local subject_raw
    subject_raw=$(calculate_subject_raw_for_job "$log_file")

    local message="🗞️  **$subject_raw** – $NOW"

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