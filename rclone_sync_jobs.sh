#!/usr/bin/env bash
# rclone_sync_jobs.sh
# Synchronisation locale -> cloud via rclone, multi jobs, logs, coloration, arrêt sur erreur critique.
# Affichage dates début/fin alignées, ligne vide au départ.
# Mode manuel / automatique détecté via argument (voir "Utilisation").

set -uo pipefail

## ======= Configuration =======
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_FILE="$SCRIPT_DIR/rclone_jobs.txt"  # fichier jobs OBLIGATOIRE, dans même dossier que script
LOG_DIR="/var/log/rclone"
KEEP_DAYS=30
RCLONE_OPTS=(
  "--transfers" "4"
  "--checkers" "8"
  "--contimeout" "60s"
  "--timeout" "300s"
  "--retries" "3"
  "--low-level-retries" "10"
  "--stats" "1s"
)
## =============================

COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_RESET="\033[0m"

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--auto] [-h|--help]

Ce script doit être lancé depuis son dossier contenant le fichier rclone_jobs.txt

Options:
  --dry-run     : simulateur (ne fait pas d'action)
  --auto        : mode automatique (ex: tâche cron) -> activera futur envoi email
  -h, --help    : affiche cette aide

Exemples:
  $0                       # exécution manuelle (par défaut)
  $0 --dry-run             # exécution manuelle en simulation
  $0 --auto                # exécution automatique (prévu pour envoi d'email)
  $0 --auto --dry-run      # auto + simulation
EOF
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

print_rclone_cmd() {
  local src="$1" dst="$2" dry="$3"
  echo "Commande rclone qui sera exécutée :"
  echo "rclone sync \\"
  echo "  '$src' \\"
  echo "  '$dst' \\"
  # Calcul largeur max de clé d’option pour alignement
  local max_len=0
  for ((i=0; i<${#RCLONE_OPTS[@]}; i+=2)); do
    local key="${RCLONE_OPTS[i]}"
    (( ${#key} > max_len )) && max_len=${#key}
  done
  for ((i=0; i<${#RCLONE_OPTS[@]}; i+=2)); do
    local key="${RCLONE_OPTS[i]}"
    local val="${RCLONE_OPTS[i+1]}"
    local padded_key
    padded_key=$(printf "%-${max_len}s" "$key")
    echo "  ${padded_key} = ${val} \\"
  done
  if [[ -n "$dry" ]]; then
    echo "  $dry \\"
  fi
  echo "  --log-level DEBUG"
}

## Parse args
DRY_RUN_ARG=""
AUTO_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN_ARG="--dry-run"; shift ;;
    --auto)    AUTO_MODE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue : $1"; usage; exit 1 ;;
  esac
done

## Pré-vérifications
if ! command -v rclone >/dev/null 2>&1; then
  echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} 'rclone' introuvable. Installez-le avant d'exécuter ce script."
  exit 2
fi

if [[ ! -f "$JOBS_FILE" ]]; then
  echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} fichier obligatoire '$JOBS_FILE' absent."
  echo "Annulation de la tâche."
  exit 3
fi

if [[ ! -d "$LOG_DIR" ]]; then
  echo "Création dossier logs : $LOG_DIR"
  mkdir -p "$LOG_DIR" || { echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} impossible de créer $LOG_DIR"; exit 4; }
  chmod 750 "$LOG_DIR"
fi

# Ligne vide tout début affichage
echo

# Affichage date début
START_TS=$(date '+%Y-%m-%d à %H:%M:%S')
printf "%-20s : %s\n" "Tâche initiée le" "$START_TS"
echo

job_count=0
success_count=0
fail_count=0
INFO_LOG=""
DEBUG_LOG=""

while IFS='' read -r rawline || [[ -n "$rawline" ]]; do
  line="${rawline%%#*}"
  line="$(trim "$line")"
  [[ -z "$line" ]] && continue

  if [[ "$line" == *'|'* ]]; then
    local_path="${line%%|*}"
    remote_path="${line#*|}"
  else
    local_path="$(awk '{print $1; exit}' <<<"$line")"
    remote_path="$(awk '{$1=""; sub(/^ /,""); print; exit}' <<<"$line")"
  fi
  local_path="$(trim "$local_path")"
  remote_path="$(trim "$remote_path")"

  ((job_count++))
  echo "---------------------------------------------"
  echo "Job #$job_count :"
  echo "  local : '$local_path'"
  echo "  remote: '$remote_path'"

  if [[ ! -e "$local_path" ]]; then
    echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} chemin local inexistant : $local_path"
    echo "Annulation de la procédure."
    exit 5
  fi
  if [[ ! -r "$local_path" ]]; then
    echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} pas de lecture sur : $local_path"
    echo "Annulation de la procédure."
    exit 6
  fi

  TS="$(date '+%Y-%m-%d_%H-%M-%S')"
  DEBUG_LOG="$LOG_DIR/rclone_DEBUG_${TS}.log"
  INFO_LOG="$LOG_DIR/rclone_INFO_${TS}.log"

  : > "$DEBUG_LOG" || { echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} impossible de créer $DEBUG_LOG"; exit 7; }
  : > "$INFO_LOG"  || { echo -e "${COLOR_RED}ERREUR:${COLOR_RESET} impossible de créer $INFO_LOG"; exit 7; }

  print_rclone_cmd "$local_path" "$remote_path" "$DRY_RUN_ARG"
  echo

  extra_opts=()
  if [[ -n "$DRY_RUN_ARG" ]]; then
    extra_opts+=("$DRY_RUN_ARG")
  fi

  rclone sync "$local_path" "$remote_path" \
    --log-level DEBUG \
    --log-file "$DEBUG_LOG" \
    "${RCLONE_OPTS[@]}" \
    "${extra_opts[@]}" 2>&1 \
    | awk -v green="$COLOR_GREEN" -v red="$COLOR_RED" -v reset="$COLOR_RESET" '
        /\[(INFO|NOTICE|WARNING|ERROR)\]/ {
          ts=strftime("%Y-%m-%d %H:%M:%S")
          line=$0
          if (line ~ /Copied \(|Updated /) {
            print ts, green line reset
          } else if (line ~ /Deleted/) {
            print ts, red line reset
          } else {
            print ts, line
          }
          fflush()
        }' \
    | tee -a "$INFO_LOG"

  rc=${PIPESTATUS[0]:-0}
  if [[ $rc -eq 0 ]]; then
    echo -e "Job #$job_count terminé avec ${COLOR_GREEN}succès${COLOR_RESET} (code $rc)."
    ((success_count++))
  else
    echo -e "Job #$job_count terminé avec ${COLOR_RED}échec${COLOR_RESET} (code $rc). Voir $DEBUG_LOG."
    echo "Annulation de la procédure."
    exit 8
  fi
  echo
done < "$JOBS_FILE"

# Affichage date fin
END_TS=$(date '+%Y-%m-%d à %H:%M:%S')
printf "%-20s : %s\n" "Tâche terminée le" "$END_TS"
echo

# ==== FUTUR CODE EMAIL ====
if $AUTO_MODE; then
  # Espace réservé pour futur envoi d'email
  # Exemple d'utilisation future :
  # send_email "$INFO_LOG" "$DEBUG_LOG" "$job_count" "$success_count" "$fail_count" "$START_TS" "$END_TS"
  :
fi
# ===========================

echo "Nettoyage des logs plus anciens que $KEEP_DAYS jours dans $LOG_DIR..."
find "$LOG_DIR" -type f -name 'rclone_*_*.log' -mtime +"$KEEP_DAYS" -print -delete || true

echo "============================================="
printf "%-12s %d\n" "Total jobs:" "$job_count"
printf "%-12s ${COLOR_GREEN}%d${COLOR_RESET}\n" "Succès:" "$success_count"
printf "%-12s ${COLOR_RED}%d${COLOR_RESET}\n" "Échecs:" "$fail_count"
echo
printf "%-12s %s\n" "Log INFO:"  "$INFO_LOG"
printf "%-12s %s\n" "Log DEBUG:" "$DEBUG_LOG"
echo "============================================="

exit 0
