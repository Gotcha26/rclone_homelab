#!/usr/bin/env bash
###############################################################################
# Script : rclone_sync_job.sh
# Version : 1.9 - 2025-08-09
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

# Couleurs : on utilise $'...' pour insérer le caractère ESC réel
BLUE=$'\e[34m'                # bleu pour ajouts / copied / added / transferred
RED=$'\e[31m'                 # rouge pour deleted / error
ORANGE=$'\e[38;5;208m'        # orange (256-color). Si ton terminal ne supporte pas, ce sera équivalent à une couleur proche.
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
        printf '%*s\n' 80 '' | tr ' ' '='   # ligne = de 60 caractères

    print_aligned "Date / Heure début" "$START_TIME"
    print_aligned "Date / Heure fin" "$END_TIME"
    print_aligned "Mode de lancement" "$LAUNCH_MODE"
    print_aligned "Nombre de jobs" "$JOBS_COUNT"
    print_aligned "Code erreur" "$ERROR_CODE"

        printf '%*s\n' 80 '' | tr ' ' '='   # ligne = de 60 caractères

        echo
        echo "--- Fin de rapport ---"
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
        fflush()   # <-- cette ligne force awk à afficher immédiatement chaque ligne
    }'
}

###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################
print_logo() {
        echo
        echo
    cat <<'EOF'
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
    echo "❌ Fichier jobs introuvable : $JOBS_FILE" >&2
    ERROR_CODE=1
    exit $ERROR_CODE
fi
if [[ ! -r "$JOBS_FILE" ]]; then
    echo "❌ Fichier jobs non lisible : $JOBS_FILE" >&2
    ERROR_CODE=2
    exit $ERROR_CODE
fi

# **Vérification ajoutée pour TMP_RCLONE**
if [[ ! -d "$TMP_RCLONE" ]]; then
    echo "❌ Dossier temporaire rclone introuvable : $TMP_RCLONE" >&2
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
        echo "❌ Ligne invalide dans $JOBS_FILE : $line" >&2
        ERROR_CODE=3
        exit $ERROR_CODE
    fi

    if [[ ! -d "$src" ]]; then
        echo "❌ Dossier source introuvable ou inaccessible : $src" >&2
        ERROR_CODE=4
        exit $ERROR_CODE
    fi

    if [[ "$dst" == *":"* ]]; then
        remote_name="${dst%%:*}"
        if [[ ! " ${RCLONE_REMOTES[*]} " =~ " ${remote_name} " ]]; then
            echo "❌ Remote inconnu dans rclone : $remote_name" >&2
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

    echo "=== Synchronisation : $src → $dst ==="
    echo "=== Tâche lancée le $(date '+%Y-%m-%d à %H:%M:%S') (mode : $LAUNCH_MODE) ==="
        echo

    # Exécution avec colorisation (awk) — set -o pipefail permet de récupérer correctement le code retour de rclone
    if ! rclone sync "$src" "$dst" "${RCLONE_OPTS[@]}" 2>&1 | colorize; then
        ERROR_CODE=6
    fi

    ((JOBS_COUNT++))
    echo
done < "$JOBS_FILE"

exit $ERROR_CODE
