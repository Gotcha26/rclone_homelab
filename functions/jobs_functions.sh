#!/usr/bin/env bash

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
# Fonction : Générer un JOB_ID unique basé sur l'index du job
###############################################################################
generate_job_id() {
    local job_idx="$1"
    printf "JOB%02d" "$((job_idx + 1))"
}


###############################################################################
# Vérifie si un remote existe dans la config rclone
# S'il est invalide (n'existe pas ou mal configuré) il n'y pas de message bloquant
# L'exécution se poursuit mais un drapeau PROBLEM sera marqué pour avoir un
# retour dans les logs (mail, discord...).
###############################################################################
remote_exists() {
    local remote="$1"
    if rclone listremotes | grep -q "^${remote}:$"; then
        return 0  # existe
    else
        return 1  # n'existe pas
    fi
}


###############################################################################
# Fonction pour parcourir tous les remotes avec exécution parallèle
###############################################################################
check_remotes() {
    for idx in "${!JOBS_LIST[@]}"; do
        job="${JOBS_LIST[$idx]}"
        IFS='|' read -r src dst <<< "$job"

        for endpoint in "$src" "$dst"; do
            if [[ "$endpoint" == *:* ]]; then
                remote="${endpoint%%:*}"

                if printf '%s\n' "${RCLONE_REMOTES[@]}" | grep -qx "$remote"; then
                    REMOTE_STATUS["$remote"]="OK"
                else
                    REMOTE_STATUS["$remote"]="missing"
                    JOB_STATUS[$idx]="PROBLEM"
                    JOB_MSG[$idx]="missing"
                fi
            fi
        done

        # Si aucun problème détecté, on marque explicitement OK
        if [[ -z "${JOB_STATUS[$idx]}" ]]; then
            JOB_STATUS[$idx]="OK"
            JOB_MSG[$idx]="ok"
        fi
    done
}


###############################################################################
# Fonction pour vérifier et éventuellement reconnecter un remote
# Tient compte aussi d'un remote mal renseigné dans la liste des jobs
###############################################################################
check_remote_non_blocking() {
    local remote="$1"
    local timeout_duration=30s
    local msg=""

    # Vérification existence du remote
    if ! remote_exists "$remote"; then
        REMOTE_STATUS["$remote"]="PROBLEM"

        for i in "${!JOBS_LIST[@]}"; do
            [[ "${JOBS_LIST[$i]}" == *"$remote:"* ]] && {
                JOB_STATUS[$i]="PROBLEM"
                JOB_MSG["$i"]="missing"
            }
        done
        return
    fi

    # Récupération du type
    local remote_type
    remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')

    # Vérification disponibilité du remote
    if ! timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
        # Tentative de reconnexion pour certains types
        if [[ "$remote_type" == "onedrive" || "$remote_type" == "drive" ]]; then
            rclone config reconnect "$remote:" -auto >/dev/null 2>&1
            if timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
                REMOTE_STATUS["$remote"]="OK"
                return
            fi
        fi

        REMOTE_STATUS["$remote"]="PROBLEM"
        code=1

        for i in "${!JOBS_LIST[@]}"; do
            [[ "${JOBS_LIST[$i]}" == *"$remote:"* ]] && {
                JOB_STATUS[$i]="PROBLEM"
                JOB_MSG["$i"]="$remote_type"   # on stocke juste le type ici
            }
        done
    else
        REMOTE_STATUS["$remote"]="OK"
    fi
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
    msg="❌  \e[1;33mAttention\e[0m : un problème empèche l'exécution du job pour le remote '\e[1m$remote\e[0m'
    
    "

    case "$remote_type" in
        missing)
            msg="Raison : le remote '$remote' n'existe pas...
... ou n'a pas été trouvé dans votre configuration de rclone.
Vous êtes invité à revoir votre configuration pour le job et/ou rclone."
            ;;
        onedrive)
            msg+="
Le remote '\e[1m$remote\e[0m' est \e[31minaccessible\e[0m pour l'écriture.

Ce problème est typique de \e[36mOneDrive\e[0m : le token OAuth actuel
ne permet plus l'écriture, même si la lecture fonctionne. [unauthenticated]
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
OAuth est expiré ou si les scopes d'accès sont insuffisants. [unauthenticated]
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

    TMP_JOB_LOG_RAW="$TMP_JOBS_DIR/${job_id}_raw.log"       # Spécifique à la sortie de rclone
    TMP_JOB_LOG_HTML="$TMP_JOBS_DIR/${job_id}_html.log"     # Spécifique au formatage des balises HTML
    TMP_JOB_LOG_PLAIN="$TMP_JOBS_DIR/${job_id}_plain.log"   # Version simplifié de raw, débarassée des codes ANSI / HTML
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
        else if (l ~ /(delete|deleted)/) {
            printf "%s%s%s\n", RED, line, RESET
        }
        # Erreurs et échecs -> rouge gras
        else if (l ~ /(error|failed|unauthenticated|unexpected|io error|io errors|not deleting)/) {
            printf "%s%s%s\n", RED_BOLD, line, RESET
        }
        # Déjà synchronisé / inchangé / skipped -> orange
        else if (l ~ /(unchanged|already exists|skipped|skipping|there was nothing to transfer|no change)/) {
            printf "%s%s%s\n", ORANGE, line, RESET
        }
        else {
            print line
        }
    }
    END {
        fflush()
    }'
}