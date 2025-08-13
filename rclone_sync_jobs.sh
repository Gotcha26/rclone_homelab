#!/usr/bin/env bash
###############################################################################
# Script : rclone_sync_job.sh
# Version : 1.10 - 2025-08-09
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
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    IFS='|' read -r src dst <<< "$line"
    src="${src#"${src%%[![:space:]]*}"}"
    src="${src%"${src##*[![:space:]]}"}"
    dst="${dst#"${dst%%[![:space:]]*}"}"
    dst="${dst%"${dst##*[![:space:]]}"}"

    print_centered_line "=== Synchronisation : $src → $dst ==="
    print_centered_line "=== Tâche lancée le $(date '+%Y-%m-%d à %H:%M:%S') (mode : $LAUNCH_MODE) ==="
    echo

    # Exécution avec colorisation (awk) — set -o pipefail permet de récupérer correctement le code retour de rclone
	# Première exécution : affichage + log INFO
	if ! rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" \
		--log-level INFO \
		2>&1 | tee -a "$LOG_FILE_INFO" | colorize; then
		ERROR_CODE=6
	fi

	# Deuxième exécution DEBUG (silencieuse, complète dans log DEBUG)
	if ! rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" \
		--log-level DEBUG --log-file "$LOG_FILE_DEBUG" >/dev/null 2>&1; then
		ERROR_CODE=6
	fi

    ((JOBS_COUNT++))
    echo
done < "$JOBS_FILE"

# Purge des logs si rclone a réussi
if [[ $ERROR_CODE -eq 0 ]]; then
    find "$LOG_DIR" -type f -name "rclone_log_*" -mtime +$LOG_RETENTION_DAYS -delete
fi

exit $ERROR_CODE
