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
declare -A JOB_ERR_REASON
declare -A JOB_ENDPOINT
declare -A REMOTE_STATUS

check_remotes() {
    local timeout_duration="10s"
									   
    ERROR_CODE=${ERROR_CODE:-0}

    for idx in "${!JOBS_LIST[@]}"; do
        local job="${JOBS_LIST[$idx]}"
        IFS='|' read -r src dst <<< "$job"

        # Initialisation
		# On part du principe que le job est OK
        JOB_STATUS[$idx]="OK"
		JOB_ERR_REASON[$idx]="ok"				  
        JOB_REMOTE[$idx]=""

        for endpoint in "$src" "$dst"; do
            local remote_type="local"

            # --- Vérification remote distant ---
            if [[ "$endpoint" == *:* ]]; then
                local remote="${endpoint%%:*}"

                # Remote connu ?
                if ! printf '%s\n' "${RCLONE_REMOTES[@]}" | grep -qx "$remote"; then
                    JOB_STATUS[$idx]="PROBLEM"
					JOB_ERR_REASON[$idx]="missing"					   
                    JOB_REMOTE[$idx]="$remote"
                    REMOTE_STATUS["$remote"]="missing"
                    ERROR_CODE=6   # remote manquant
                    break
                fi						   

                remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')
                remote_type=$(echo "$remote_type" | tr '[:upper:]' '[:lower:]')

                # Test token pour remotes sensibles (OneDrive / Drive)
                if [[ "$remote_type" == "onedrive" || "$remote_type" == "drive" ]]; then
                    if ! timeout "$timeout_duration" rclone lsf "${remote}:" --max-depth 1 --limit 1 >/dev/null 2>&1; then
                        JOB_STATUS[$idx]="PROBLEM"
						JOB_ERR_REASON[$idx]="$remote_type"							
                        JOB_REMOTE[$idx]="$remote"
                        REMOTE_STATUS["$remote"]="PROBLEM"
                        ERROR_CODE=14
                        break
                    fi
                fi

            fi

            # --- Vérification dry-run uniquement pour la destination distante ---
            if [[ "$dst" == *:* ]] && [[ " ${RCLONE_OPTS[*]} " == *"--dry-run"* ]]; then
                if ! check_dry_run_compat "$dst"; then
                    JOB_STATUS[$idx]="PROBLEM"
					JOB_ERR_REASON[$idx]="dry_run_incompatible"
                    JOB_REMOTE[$idx]="$remote"
                    REMOTE_STATUS["$dst"]="PROBLEM"
                    JOB_ENDPOINT[$idx]="$dst"
                    ERROR_CODE=20
                    break
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
                JOB_ERR_REASON["$i"]="missing"
            }
        done
        return
    fi

    # Récupération du type
    local remote_type
    remote_type=$(rclone config dump | jq -r --arg r "$remote" '.[$r].type')
    remote_type=$(echo "$remote_type" | tr '[:upper:]' '[:lower:]')

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
declare -A JOB_MSG         # idx -> message d'erreur détaillé

warn_remote_problem() {
    local remote="$1"         # remote en cause
    local endpoint="$2"       # endpoint exact (src ou dst)
    local problem_type="$3"   # missing / onedrive / drive / dry_run_incompatible / autre
    local job_idx="$4"        # index du job
    local log_file="$5"       # fichier raw log

			 
    local msg="❌  \e[1;33mAttention\e[0m : erreur unexpected détectée !
    
"

    case "$problem_type" in
        missing)
            msg+="
Raison : le remote '\e[1;94m$remote\e[0m' n'existe pas...
... ou n'a pas été trouvé dans votre configuration de rclone.
Vous êtes invité à revoir votre configuration pour le job et/ou rclone.

Les jobs utilisant ce remote seront \e[31mignorés\e[0m jusqu'à résolution.
"
            ;;
        onedrive)
            msg+="
Le remote '\e[1;94m$remote\e[0m' est \e[31minaccessible\e[0m pour l'écriture.

Ce problème est typique de \e[36mOneDrive\e[0m : le token OAuth actuel
ne permet plus l'écriture, même si la lecture fonctionne. [unauthenticated]
Il faut refaire complètement la configuration du remote :
  1. Supprimer ou éditer le remote existant : \e[1mrclone config\e[0m
  2. Reconnecter le remote et accepter toutes les permissions
     (\e[32mlecture\e[0m + \e[32mécriture\e[0m).
  3. Commande pour éditer directement le fichier de conf. de rclone :
     \e[1mnano ~/.config/rclone/rclone.conf\e[0m

Les jobs utilisant ce remote seront \e[31mignorés\e[0m jusqu'à résolution.
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

Les jobs utilisant ce remote seront \e[31mignorés\e[0m jusqu'à résolution.
"
            ;;
        dry_run_incompatible)
            msg+="
La destination choisie n'accèpte pas l'option dry-run :

\e[1;94m$endpoint\e[0m

Ce type de service \e[3m(local / SMB / CIFS)\e[0m ne respectera pas la simulation et
exécuterait \e[4mréellement\e[0m les actions de synchronisation ne garantissant pas
de préserver votre destination de toutes modifications induites.

Le job sera \e[31mignoré\e[0m pour éviter toute suppression ou copie non désirée.
Supprimer --dry-run ou le job de la liste."
            ;;
        *)
            msg+="
Le problème provient probablement du token ou des permissions.
Vérifiez la configuration du remote avec : \e[1mrclone config\e[0m

Les jobs utilisant ce remote seront \e[31mignorés\e[0m jusqu'à résolution.
"
													 
            ;;
    esac

    msg+="

"

    # Écriture dans le log RAW
    [[ -n "$log_file" ]] && echo -e "\n$msg\n" >> "$log_file"

    # Associer au JOB_MSG si job_idx fourni (corrigé pour job_idx=0)
    [[ -n "${job_idx+x}" ]] && JOB_MSG["$job_idx"]="$msg"

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


###############################################################################
# Fonction d'appel pour une autre fonction mais avec les bons arguments sans UNBOUND VARIABLE
###############################################################################
handle_job_problem() {
    local idx="$1"
    local ENDPOINT="${JOB_ENDPOINT[$idx]-}"
    # Génération des logs RAW directement
    warn_remote_problem "${JOB_REMOTE[$idx]}" "${ENDPOINT}" "${JOB_ERR_REASON[$idx]}" "$idx" "$TMP_JOB_LOG_RAW"
}
