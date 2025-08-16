#!/usr/bin/env bash
###############################################################################
# Script : rclone_sync_job.sh
# Version : 1.46 - 2025-08-16
# Auteur  : Julien & ChatGPT
#
# Description :
#   Lit la liste des jobs dans rclone_jobs.txt et exécute rclone pour chacun.
#   Format du fichier rclone_jobs.txt :
#       source|destination
#
#   Les lignes commençant par # ou vides sont ignorées.
#   L'option --auto permet d'indiquer un lancement automatique.
#   L'option --mailto=<mon_adresse@mail.com permet d'envoyer un rapport par e-mail.
#
#   En fin d'exécution, un tableau récapitulatif avec bordures est affiché.
###############################################################################

set -uo pipefail  # -u pour var non définie, -o pipefail pour récupérer le code d'erreur d'un composant du pipeline, on retire -e pour éviter l'arrêt brutal, on gère les erreurs manuellement

###############################################################################
# Variables
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_FILE="$SCRIPT_DIR/rclone_jobs.txt"   # Modifier ici si besoin
TMP_RCLONE="/mnt/tmp_rclone"
TERM_WIDTH_DEFAULT=80   # Largeur par défaut pour les affichages fixes
LOG_DIR="/var/log/rclone"					# Emplacement des logs
LOG_RETENTION_DAYS=15						# Durée de conservation des logs
LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE_INFO="$LOG_DIR/rclone_log_${LOG_TIMESTAMP}_INFO.log"
DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
NOW="$(date '+%Y/%m/%d %H:%M:%S')"
MAIL="${TMP_RCLONE}/rclone_report.mail"
MAIL_DISPLAY_NAME="RCLONE Script Backup"
MAIL_TO=""   # valeur par défaut vide
MAIL_TO_ABS="⚠ Option --mail activée mais aucun destinataire fourni (--mailto).
Le rapport ne sera pas envoyé."
LOG_LINE_MAX="200"

# Couleurs : on utilise $'...' pour insérer le caractère ESC réel
BLUE=$'\e[34m'                # bleu pour ajouts / copied / added / transferred
RED=$'\e[31m'                 # rouge pour deleted / error
ORANGE=$'\e[38;5;208m'        # orange (256-color). Si ton terminal ne supporte pas, ce sera équivalent à une couleur proche.
BG_BLUE_DARK=$'\e[44m'        # fond bleu foncé
BG_YELLOW_DARK=$'\e[43m'      # fond jaune classique (visible partout, jaune "standard")
BLACK=$'\e[30m'               # texte noir
BOLD=$'\e[1m'                 # texte gras
RESET=$'\e[0m'                # Effaceur

# Options rclone (1 par ligne)
RCLONE_OPTS=(
    --temp-dir "$TMP_RCLONE"
    --exclude '*<*'
    --exclude '*>*'
    --exclude '*:*'
    --exclude '*"*'
    --exclude '*\\*'
    --exclude '*\|*'
    --exclude '*\?*'
    --exclude '.*'
    --exclude 'Thumbs.db'
    --log-level INFO
    --stats-log-level NOTICE
)

START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
END_TIME=""
ERROR_CODE=0
JOBS_COUNT=0
LAUNCH_MODE="manuel"
SEND_MAIL=false   # <- par défaut, pas d'envoi d'email

###############################################################################
# Messages (centralisés pour affichage et email)
###############################################################################
MSG_WAITING1="SOYEZ PATIENT..."
MSG_WAITING2="Mise à jour seulement à fin de l'opération de synchronisation."
MSG_WAITING3="Pour interrompre : CTRL + C"
MSG_FILE_NOT_FOUND="✗ Fichier jobs introuvable"
MSG_FILE_NOT_READ="✗ Fichier jobs non lisible"
MSG_TMP_NOT_FOUND="✗ Dossier temporaire rclone introuvable"
MSG_JOB_LINE_INVALID="✗ Ligne invalide dans le fichier jobs"
MSG_SRC_NOT_FOUND="✗ Dossier source introuvable ou inaccessible"
MSG_REMOTE_UNKNOWN="✗ Remote inconnu dans rclone"
MSG_MSMTP_NOT_FOUND="⚠ Attention : msmtp n'est pas installé ou introuvable dans le PATH.
Le rapport par e-mail ne sera pas envoyé."
MSG_MSMTP_ERROR="⚠ Echec envoi email via msmtp"
MSG_END_REPORT="--- Fin de rapport ---"
MSG_LOG_DIR_CREATE_FAIL="✗ Impossible de créer le dossier de logs"
MSG_RCLONE_START="Synchronisation :"
MSG_TASK_LAUNCH="Tâche lancée le"
MSG_EMAIL_END="– Fin du message automatique –"
MSG_EMAIL_SUCCESS="✅  Sauvegardes vers le cloud réussies"
MSG_EMAIL_FAIL="❌  Des erreurs lors des sauvegardes vers le cloud"
MSG_MAIL_SUSPECT="❗  Synchronisation réussie mais aucun fichier transféré"
MSG_PREP="📧  Préparation de l'email..."
MSG_SENT="... Email envoyé ✅ "
MSG_DRYRUN="✅  Oui : aucune modification de fichiers."

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

# === Initialisation des données pour le mail ===
MAIL_SUBJECT_OK=true
MAIL_CONTENT="<html><body style='font-family: monospace; background-color: #f9f9f9; padding: 1em;'>"
MAIL_CONTENT+="<h2>📤 Rapport de synchronisation Rclone – $NOW</h2>"

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
# Fonction LOG pour les journaux
###############################################################################
# Création conditionnelle du répertoire LOG_DIR
if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        echo "${RED}$MSG_LOG_DIR_CREATE_FAIL : $LOG_DIR${RESET}" >&2
        ERROR_CODE=8
        exit $ERROR_CODE
    fi
fi

###############################################################################
# Fonction spinner
###############################################################################
spinner() {
    local pid=$1       # PID du processus à surveiller
    local delay=0.1    # vitesse du spinner
    local spinstr='|/-\'
    tput civis         # cacher le curseur

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
# Lecture des options du script
###############################################################################
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            LAUNCH_MODE="automatique"
            shift
            ;;
        --mailto=*)
            MAIL_TO="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Activation dry-run si demandé
if $DRY_RUN; then
    RCLONE_OPTS+=(--dry-run)
fi

# Vérification si --mailto est fourni
if [[ -z "$MAIL_TO" ]]; then
    echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    SEND_MAIL=false
else
    SEND_MAIL=true
fi

# === Vérification non bloquante si --mail activé sans --mailto ===
if $SEND_MAIL && [[ -z "$MAIL_TO" ]]; then
    echo "${ORANGE}${MAIL_TO_ABS}${RESET}" >&2
    SEND_MAIL=false
fi

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

###############################################################################
# Affichage récapitulatif à la sortie
###############################################################################
trap 'print_summary_table' EXIT

###############################################################################
# Vérifications initiales
###############################################################################
if [[ ! -f "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_FOUND : $JOBS_FILE" >&2
    ERROR_CODE=1
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    echo "$MSG_FILE_NOT_READ : $JOBS_FILE" >&2
    ERROR_CODE=2
    exit $ERROR_CODE
fi
# **Vérification ajoutée pour TMP_RCLONE**
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "$MSG_TMP_NOT_FOUND : $TMP_RCLONE" >&2
    ERROR_CODE=7
    exit $ERROR_CODE
fi

# Charger la liste des remotes configurés dans rclone
mapfile -t RCLONE_REMOTES < <(rclone listremotes 2>/dev/null | sed 's/:$//')

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

###############################################################################
# Purge inconditionnel des logs anciens (tous fichiers du dossier)
###############################################################################
find "$LOG_DIR" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

exit $ERROR_CODE
