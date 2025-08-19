###############################################################################
# Variables de configuration
###############################################################################

# === Générales ===

# Adaptables
TERM_WIDTH_DEFAULT=80                      # Largeur par défaut pour les affichages fixes
LOG_RETENTION_DAYS=15                      # Durée de conservation des logs
LOG_LINE_MAX=200                           # Nombre de lignes maximales (en partant du bas) à afficher dans le rapport par email

# === Messages (centralisés pour affichage et email) ===

MAIL_DISPLAY_NAME="RCLONE Script Backup"   # Nom affiché de l'expéditeur
MAIL_TO_ABS="⚠ Option --mail activée mais aucun destinataire fourni (--mailto).
Le rapport ne sera pas envoyé."            # Affiché si aucun destinataire email fourni
MSG_WAITING1="SOYEZ PATIENT..."
MSG_WAITING2="Mise à jour seulement à fin de l'opération de synchronisation."
MSG_WAITING3="Pour interrompre : CTRL + C"
MSG_FILE_NOT_FOUND="✗ Fichier jobs introuvable"
MSG_FILE_NOT_READ="✗ Fichier jobs non lisible"
MSG_TMP_NOT_FOUND="✗ Dossier temporaire rclone introuvable"
MSG_JOB_LINE_INVALID="✗ Ligne invalide dans le fichier jobs"
MSG_SRC_NOT_FOUND="✗ Dossier source introuvable ou inaccessible"
MSG_REMOTE_UNKNOW="✗ Remote inconnu dans rclone"
MSG_MSMTP_NOT_FOUND="⚠ Attention : msmtp n'est pas installé ou introuvable dans le PATH.
Le rapport par e-mail ne sera pas envoyé."
MSG_MSMTP_ERROR="⚠ Echec envoi email via msmtp"
MSG_END_REPORT="--- Fin de rapport ---"
MSG_LOG_DIR_CREATE_FAIL="✗ Impossible de créer le dossier de logs"
MSG_TMP_RCLONE_CREATE_FAIL="✗ Impossible de créer le dossier temporaire"
MSG_RCLONE_FAIL="❌ Erreur : rclone n'est pas installé ou introuvable dans le PATH."
MSG_RCLONE_START="Synchronisation :"
MSG_TASK_LAUNCH="Tâche lancée le"
MSG_EMAIL_END="– Fin du message automatique –"
MSG_EMAIL_SUCCESS="✅  Sauvegardes vers le cloud réussies"
MSG_EMAIL_FAIL="❌  Des erreurs lors des sauvegardes vers le cloud"
MSG_EMAIL_SUSPECT="❗  Synchronisation réussie mais aucun fichier transféré"
MSG_EMAIL_PREP="📧  Préparation de l'email..."
MSG_EMAIL_SENT="... Email envoyé ✅ "
MSG_MAIL_ERROR="❌  Adresse email saisie invalide"
MSG_DRYRUN="✅  Oui : aucune modification de fichiers."

# === Variables techniques ===

# Ne pas toucher
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_RCLONE="$SCRIPT_DIR/tmp"               # Répertoire temporaire pour rclone
LOG_DIR="$SCRIPT_DIR/logs"                 # Répertoire de logs
JOBS_FILE="$SCRIPT_DIR/rclone_sync_jobs.txt"    # Fichier des jobs
LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE_INFO="$LOG_DIR/rclone_log_${LOG_TIMESTAMP}_INFO.log"
NOW="$(date '+%Y/%m/%d %H:%M:%S')"
MAIL_TO=""                     # valeur par défaut vide
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
END_TIME=""
ERROR_CODE=0
JOBS_COUNT=0
LAUNCH_MODE="manuel"

# Couleurs ANSI : on utilise $'...' pour insérer le caractère ESC réel
BLUE=$'\e[34m'                # bleu pour ajouts / copied / added / transferred
RED=$'\e[31m'                 # rouge pour deleted / error
ORANGE=$'\e[38;5;208m'        # orange (256-color). Si ton terminal ne supporte pas, ce sera équivalent à une couleur proche.
BLUE_DARK=$'\e[44m'        # fond bleu foncé
YELLOW_DARK=$'\e[43m'      # fond jaune classique (visible partout, jaune "standard")
BLACK=$'\e[30m'               # texte noir
RESET=$'\e[0m'                # Effaceur

# === Options rclone ===

# 1 par ligne
# Plus de commandes sur https://rclone.org/commands/rclone/
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
