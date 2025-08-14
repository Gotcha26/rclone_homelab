#!/usr/bin/env bash
###############################################################################
# Script : rclone_sync_job.sh
# Version : 1.30 - 2025-08-14
# Auteur  : Julien & ChatGPT
#
# Description :
#   Lit la liste des jobs dans rclone_jobs.txt et exécute rclone pour chacun.
#   Format du fichier rclone_jobs.txt :
#       source|destination
#
#   Les lignes commençant par # ou vides sont ignorées.
#   L'option --auto permet d'indiquer un lancement automatique.
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
END_REPORT_TEXT="--- Fin de rapport ---"
TERM_WIDTH_DEFAULT=80   # Largeur par défaut pour les affichages fixes
LOG_DIR="/var/log/rclone"					# Emplacement des logs
LOG_RETENTION_DAYS=15						#Durée de conservation des logs
LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE_INFO="$LOG_DIR/rclone_log_${LOG_TIMESTAMP}_INFO.log"
LOG_FILE_DEBUG="$LOG_DIR/rclone_log_${LOG_TIMESTAMP}_DEBUG.log"
DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
NOW="$(date '+%Y/%m/%d %H:%M:%S')"
MAIL="${TMP_RCLONE}/rclone_report.mail"

# Couleurs : on utilise $'...' pour insérer le caractère ESC réel
BLUE=$'\e[34m'                # bleu pour ajouts / copied / added / transferred
RED=$'\e[31m'                 # rouge pour deleted / error
ORANGE=$'\e[38;5;208m'        # orange (256-color). Si ton terminal ne supporte pas, ce sera équivalent à une couleur proche.
BG_BLUE_DARK=$'\e[44m'        # fond bleu foncé
BG_YELLOW_DARK=$'\e[43m'      # fond jaune classique (visible partout, jaune "standard")
BLACK=$'\e[30m'               # texte noir
BOLD=$'\e[1m'                 # texte gras
RESET=$'\e[0m'

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
  tail -n 500 "$file" | while IFS= read -r line; do
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

###############################################################################
# Fonction LOG pour les journaux
###############################################################################
# Création conditionnelle du répertoire LOG_DIR
if [[ ! -d "$LOG_DIR" ]]; then
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        echo "${RED}✗ Impossible de créer le dossier de logs : $LOG_DIR${RESET}" >&2
        ERROR_CODE=8
        exit $ERROR_CODE
    fi
fi

###############################################################################
# Fonction pour centrer une ligne avec des '=' de chaque côté + coloration
###############################################################################
print_centered_line() {
    local line="$1"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo "$TERM_WIDTH_DEFAULT")  # Défaut 80 si échec

    # Calcul longueur visible (sans séquences d’échappement)
    # Ici la ligne n’a pas de couleur, donc simple :
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
    printf "%s%s%s%s%s\n" "$pad_left" "$BG_BLUE_DARK" "$line" "$RESET" "$pad_right"
}

###############################################################################
# Lecture des options du script
###############################################################################
for arg in "$@"; do
    case "$arg" in
        --auto)
            LAUNCH_MODE="automatique"
            shift
            ;;
        *)
            ;;
    esac
done

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
    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='   # ligne = de 80 caractères

    print_aligned "Date / Heure début" "$START_TIME"
    print_aligned "Date / Heure fin" "$END_TIME"
    print_aligned "Mode de lancement" "$LAUNCH_MODE"
    print_aligned "Nombre de jobs" "$JOBS_COUNT"
    print_aligned "Code erreur" "$ERROR_CODE"
    print_aligned "Log INFO" "$LOG_FILE_INFO"

    printf '%*s\n' "$TERM_WIDTH_DEFAULT" '' | tr ' ' '='   # ligne = de 80 caractères


  
# Ligne finale avec couleur fond jaune foncé, texte noir, centrée max 80
    local text="$END_REPORT_TEXT"
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
    echo "✗ Fichier jobs introuvable : $JOBS_FILE" >&2
    ERROR_CODE=1
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    echo "✗ Fichier jobs non lisible : $JOBS_FILE" >&2
    ERROR_CODE=2
    exit $ERROR_CODE
fi

# **Vérification ajoutée pour TMP_RCLONE**
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "✗ Dossier temporaire rclone introuvable : $TMP_RCLONE" >&2
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
        echo "✗ Ligne invalide dans $JOBS_FILE : $line" >&2
        ERROR_CODE=3
        exit $ERROR_CODE
    fi

    if [[ ! -d "$src" ]]; then
        echo "✗ Dossier source introuvable ou inaccessible : $src" >&2
        ERROR_CODE=4
        exit $ERROR_CODE
    fi

    if [[ "$dst" == *":"* ]]; then
        remote_name="${dst%%:*}"
        if [[ ! " ${RCLONE_REMOTES[*]} " =~ " ${remote_name} " ]]; then
            echo "✗ Remote inconnu dans rclone : $remote_name" >&2
            ERROR_CODE=5
            exit $ERROR_CODE
        fi
    fi
done < "$JOBS_FILE"

###############################################################################
# Exécution des jobs
###############################################################################
# Initialisation des pièces jointes (évite erreur avec set -u)
declare -a ATTACHMENTS=()

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

	# Nettoyage de la ligne : trim + uniformisation séparateurs
	line=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/\|/g')
	IFS='|' read -r src dst <<< "$line"

    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"

    print_centered_line "Synchronisation : $src → $dst"
    print_centered_line "Tâche lancée le $(date '+%Y-%m-%d à %H:%M:%S') (mode : $LAUNCH_MODE)"
    echo

    # Exécution avec colorisation (awk) — récupération immédiate du code retour rclone
	if ! rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" \
		--log-level INFO \
		2>&1 | tee -a "$LOG_FILE_INFO" | colorize; then
		:
	fi
	job_rc=${PIPESTATUS[0]}   # Code de rclone dans le pipeline INFO
	(( job_rc != 0 )) && ERROR_CODE=6

	# Deuxième exécution DEBUG (silencieuse, complète dans log DEBUG)
	if ! rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" \
		--log-level DEBUG --log-file "$LOG_FILE_DEBUG" >/dev/null 2>&1; then
		:
	fi
	debug_rc=$?
	(( debug_rc != 0 )) && ERROR_CODE=6

    ((JOBS_COUNT++))
    echo
	
    EXIT_CODE=$job_rc
    (( EXIT_CODE != 0 )) && MAIL_SUBJECT_OK=false

    # Nettoyage log INFO (garde une seule ligne NOTICE)
    tmp_log="$(mktemp)"
    grep -v "NOTICE" "$LOG_FILE_INFO" > "$tmp_log" || true
    last_notice=$(grep "NOTICE" "$LOG_FILE_INFO" | tail -n 1)
    [ -n "$last_notice" ] && echo "$last_notice" >> "$tmp_log"
    mv "$tmp_log" "$LOG_FILE_INFO"

    # Compteurs avec grep -E pour expressions régulières
    COPIED_COUNT=$(grep -E -c "Copied (new|replaced)" "$LOG_FILE_INFO" || true)
    UPDATED_COUNT=$(grep -c "Updated" "$LOG_FILE_INFO" || true)

    # Ajout au contenu du mail (utilisation de $src / $dst)
    MAIL_CONTENT+="<hr><h3>📁 $src ➜ $dst</h3>"
    MAIL_CONTENT+="<pre><b>📅 Démarrée :</b> $NOW"
    MAIL_CONTENT+="<br><b>Code retour :</b> $EXIT_CODE"
    MAIL_CONTENT+="<br><b>Fichiers copiés :</b> $COPIED_COUNT"
    MAIL_CONTENT+="<br><b>Fichiers mis à jour :</b> $UPDATED_COUNT</pre>"
    MAIL_CONTENT+="<p><b>📝 Dernières lignes du log :</b></p><pre style='background:#eee; padding:1em; border-radius:8px;'>"
    MAIL_CONTENT+="$(log_to_html "$LOG_FILE_INFO")"
    MAIL_CONTENT+="</pre>"
done < "$JOBS_FILE"

### Partie emails

# Pièces jointes : log INFO (toujours), DEBUG (en cas d’erreur globale)
ATTACHMENTS+=("$LOG_FILE_INFO")
if ! $MAIL_SUBJECT_OK; then
	ATTACHMENTS+=("$LOG_FILE_DEBUG")
fi

# Vérification présence msmtp (ne stoppe pas le script)
if ! command -v msmtp >/dev/null 2>&1; then
    echo "${ORANGE}⚠ Attention : msmtp n'est pas installé ou introuvable dans le PATH.${RESET}" >&2
    echo "Le rapport par e-mail ne sera pas envoyé." >&2
    ERROR_CODE=9
fi

MAIL_CONTENT+="<p>– Fin du message automatique –</p></body></html>"

# === Sujet du mail global ===
if $MAIL_SUBJECT_OK; then
  SUBJECT="✅ Sauvegardes vers OneDrive réussies"
else
  SUBJECT="❌ Des erreurs lors des sauvegardes vers OneDrive"
fi

# === Création du mail ===
{
  echo "From: Sauvegarde Rclone <spambiengentil@gmail.com>"
  echo "To: quelleheureestilsvp@gmail.com"
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
if command -v msmtp >/dev/null 2>&1; then
    msmtp -t < "$MAIL"
fi

# === Nettoyage ===
rm -f "$MAIL"

### /Partie emails

# Purge des logs si rclone a réussi
if [[ $ERROR_CODE -eq 0 ]]; then
    find "$LOG_DIR" -type f -name "rclone_log_*" -mtime +$LOG_RETENTION_DAYS -delete
fi

exit $ERROR_CODE
