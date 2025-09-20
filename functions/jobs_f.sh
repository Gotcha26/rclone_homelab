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
            die 7 "$MSG_SRC_NOT_FOUND : $src"
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
# Fonction : parcourir tous les remotes et vérifier leur disponibilité
# Cumule les problèmes sans écraser les précédents
###############################################################################
declare -A JOB_REMOTE   # idx -> remote problématique
declare -A JOB_MSG_LIST

check_remotes() {
    local timeout_duration="10s"
    ERROR_CODE=${ERROR_CODE:-0}

    for idx in "${!JOBS_LIST[@]}"; do
        local job="${JOBS_LIST[$idx]}"
        IFS='|' read -r src dst <<< "$job"

        # Initialisation
        JOB_STATUS[$idx]="OK"
        JOB_REMOTE[$idx]=""
        JOB_MSG_LIST[$idx]=""  # réinitialisation pour chaque job

        for endpoint in "$src" "$dst"; do
            local remote_type="local"

            # --- Vérification remote distant ---
            if [[ "$endpoint" == *:* ]]; then
                local remote="${endpoint%%:*}"

                # Remote connu ?
                if ! printf '%s\n' "${RCLONE_REMOTES[@]}" | grep -qx "$remote"; then
                    JOB_STATUS[$idx]="PROBLEM"
                    JOB_REMOTE[$idx]="$remote"
                    REMOTE_STATUS["$remote"]="PROBLEM"
                    ERROR_CODE=6
                    warn_remote_problem "$remote" "missing" "$idx" "$TMP_JOB_LOG_RAW"
                    continue 2  # passer au job suivant
                fi

                remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')

                # Test token pour remotes sensibles
                if [[ "$remote_type" == "onedrive" || "$remote_type" == "drive" ]]; then
                    if ! timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
                        JOB_STATUS[$idx]="PROBLEM"
                        JOB_REMOTE[$idx]="$remote"
                        REMOTE_STATUS["$remote"]="PROBLEM"
                        ERROR_CODE=14
                        warn_remote_problem "$remote" "$remote_type" "$idx" "$TMP_JOB_LOG_RAW"
                        continue 2
                    fi
                else
                    REMOTE_STATUS["$remote"]="OK"
                fi
            fi

            # --- Vérification dry-run uniquement pour la destination distante ---
            dst_only="$dst"
            if [[ "$dst_only" == *:* ]] && [[ " ${RCLONE_OPTS[*]} " == *"--dry-run"* ]]; then
                if ! check_dry_run_compat "$dst_only"; then
                    JOB_STATUS[$idx]="PROBLEM"
                    JOB_REMOTE[$idx]="$dst_only"
                    REMOTE_STATUS["$dst_only"]="PROBLEM"
                    ERROR_CODE=20
                    warn_remote_problem "$dst_only" "dry_run_incompatible" "$idx" "$TMP_JOB_LOG_RAW"
                    JOB_MSG_LIST[$idx]="dry_run_incompatible"
                    continue  # passe au job suivant
                fi
            fi
        done
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
                JOB_MSG_LIST["$i"]="missing"
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
        for i in "${!JOBS_LIST[@]}"; do
            [[ "${JOBS_LIST[$i]}" == *"$remote:"* ]] && {
                JOB_STATUS[$i]="PROBLEM"
                JOB_MSG_LIST["$i"]="$remote_type"
            }
        done
    else
        REMOTE_STATUS["$remote"]="OK"
    fi
}


###############################################################################
# Fonction : avertissement remote inaccessible ou problème dry-run
# Cumule tous les problèmes au lieu d'écraser
###############################################################################
warn_remote_problem() {
    local endpoint="$1"       # endpoint exact (src ou dst)
    local problem_type="$2"   # missing / onedrive / drive / dry_run_incompatible / autre
    local job_idx="$3"        # index du job
    local log_file="$4"       # fichier raw log

    local msg=""

    case "$problem_type" in
        missing)
            msg="❌  \e[1;33mAttention\e[0m : le remote '$endpoint' n'existe pas ou n'a pas été trouvé dans votre configuration rclone.
Le job associé sera \e[31mignoré\e[0m jusqu'à résolution."
            ;;
        onedrive)
            msg="❌  \e[1;33mAttention\e[0m : le remote OneDrive '$endpoint' est \e[31minaccessible\e[0m pour l'écriture.
Problème typique de token OAuth expiré ou permissions insuffisantes.
Le job sera \e[31mignoré\e[0m jusqu'à résolution."
            ;;
        drive)
            msg="❌  \e[1;33mAttention\e[0m : le remote Google Drive '$endpoint' est \e[31minaccessible\e[0m pour l'écriture.
Token OAuth expiré ou scopes insuffisants.
Le job sera \e[31mignoré\e[0m jusqu'à résolution."
            ;;
        dry_run_incompatible)
            msg="❌  \e[1;33mAttention\e[0m : dry-run activé sur un endpoint incompatible ('$endpoint').
Ce type de service (local / SMB / CIFS) ne respectera pas la simulation et exécuterait réellement les actions.
Le job sera \e[31mignoré\e[0m pour éviter toute suppression ou copie non désirée.
Supprimer --dry-run ou le job de la liste."
            ;;
        *)
            msg="❌  Attention : erreur unexpected détectée sur '$endpoint'.
Le problème provient probablement du token ou des permissions.
Vérifiez la configuration du remote avec : \e[1mrclone config\e[0m
Le job sera \e[31mignoré\e[0m jusqu'à résolution."
            ;;
    esac

    # Écriture dans le log RAW si fourni
    [[ -n "$log_file" ]] && echo -e "\n$msg\n" >> "$log_file"

    # Ajouter le message à la liste cumulée pour le job
    if [[ -n "$job_idx" ]]; then
        if [[ -z "${JOB_MSG_LIST[$job_idx]}" ]]; then
            JOB_MSG_LIST[$job_idx]="$msg"
        else
            JOB_MSG_LIST[$job_idx]+="|$msg"
        fi
    fi
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
    local ORANGE=$(get_fg_color "orange")
    local RESET=$'\033[0m'

    cat "$TMP_JOB_LOG_RAW" | sed -r 's/\x1B\[[0-9;]*[mK]//g' | awk -v BLUE="$BLUE" -v RED="$RED" -v RED_BOLD="$RED_BOLD" -v ORANGE="$ORANGE" -v RESET="$RESET" '
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
        else if (l ~ /(error|failed|unexpected|io error|io errors|not deleting)/) {
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


###############################################################################
# Vérifie si un endpoint rclone est compatible avec --dry-run
# Retourne 0 si OK, 1 si incompatible
###############################################################################
check_dry_run_compat() {
    local endpoint="$1"   # src ou dst
    local remote_type=""

    # Cas remote distant
    if [[ "$endpoint" == *:* ]]; then
        local remote="${endpoint%%:*}"
        remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')
    else
        remote_type="local"  # pas de :, donc local
    fi

    case "$remote_type" in
        local|smb|cifs)
            return 1  # incompatible dry-run
            ;;
        *)
            return 0  # compatible
            ;;
    esac
}