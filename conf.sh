###############################################################################
# Variables de configuration
# Toutes les variables peuvent être suplantées via un fichier config/config.local.sh
###############################################################################

: "${DISCORD_WEBHOOK_URL:=}"
: "${FORCE_BRANCH:=}"
FORCE_UPDATE=${FORCE_UPDATE:-false}
UPDATE_TAG=${UPDATE_TAG:-false}
DRY_RUN=${DRY_RUN:-false}
LAUNCH_MODE=${DRY_RUN:-manual}
DEBUG_MODE=${DEBUG_MODE:-false}
DEBUG_INFOS=${DEBUG_INFOS:-false}
: "${MAIL_TO:=}"
DISPLAY_MODE=${DISPLAY_MODE:-simplified}


# === Messages (centralisés pour affichage et email) ===

MAIL_DISPLAY_NAME="RCLONE Script Backup"   # Nom affiché de l'expéditeur
MAIL_TO_ABS="Option --mail activée mais aucun destinataire fourni (--mailto).
Le rapport ne sera pas envoyé."            # Affiché si aucun destinataire email fourni
MSG_PRINT_FANCY_EMPTY="⚠️  Aucun texte fourni"
MSG_WAITING1=" SOYEZ PATIENT... "
MSG_WAITING2=" Mise à jour seulement à fin du traitement du JOB. "
MSG_WAITING3=" Pour interrompre : CTRL + C "
MSG_FILE_NOT_FOUND="Fichier jobs introuvable"
MSG_FILE_NOT_READ="Fichier jobs non lisible"
MSG_TMP_NOT_FOUND="Dossier temporaire rclone introuvable"
MSG_JOB_LINE_INVALID="Ligne invalide dans le fichier jobs"
MSG_SRC_NOT_FOUND="Dossier source introuvable ou inaccessible"
MSG_REMOTE_PROBLEM_TEMPLATE="Remote %s (%s) inaccessible, tentative de reconnexion..."
MSG_REMOTE_RECONNECTION_TEMPLATE="🔄  Remote %s : reconnexion effectuée, nouveau test..."
MSG_MSMTP_NOT_FOUND="Attention : msmtp n'est pas installé ou introuvable dans le PATH.
Le rapport par e-mail ne sera pas envoyé."
MSG_MSMTP_ERROR="⚠ Echec envoi email via msmtp"
MSG_END_REPORT="--- Fin de rapport ---"
MSG_LOG_DIR_CREATE_FAIL="Impossible de créer le dossier de logs"
MSG_TMP_RCLONE_CREATE_FAIL="Impossible de créer le dossier temporaire"
MSG_RCLONE_FAIL="Erreur : rclone n'est pas installé ou introuvable dans le PATH."
MSG_RCLONE_START="Synchronisation :"
MSG_TASK_LAUNCH="Tâche lancée le"
MSG_EMAIL_END="– Fin du message automatique –"
MSG_EMAIL_SUCCESS="✅  Sauvegardes vers le cloud réussies"
MSG_EMAIL_FAIL="❌  Des erreurs lors des sauvegardes vers le cloud"
MSG_EMAIL_SUSPECT="⚠️  Synchronisation réussie mais aucun fichier transféré"
MSG_EMAIL_PREP="📧  Préparation de l'email..."
MSG_EMAIL_SENT="... Email envoyé ✅ "
MSG_MAIL_ERROR="❌  Adresse email saisie invalide"
MSG_DRYRUN="✅  Oui : aucune modification de fichiers."
MSG_DISCORD_ABORDED="⚠️  Aucun webhook Discord de défini."
MSG_DISCORD_SENT="✅  Notification Discord envoyée."
MSG_DISCORD_PROCESSED="Traitée(s)"
MSG_MAJ_ERROR="Impossible de vérifier les mises à jour (API GitHub muette)."
MSG_MAJ_ACCESS_ERROR="Erreur : impossible d'accéder au répertoire du script"
MSG_MAJ_UPDATE_TEMPLATE="📥  Nouvelle version disponible : %s (vous utilisez la %s)"
MSG_MAJ_UPDATE2="Utiliser l'argument --update-tag la prochaine fois."
MSG_MAJ_UPDATE_RELEASE_TEMPLATE="⚡  Mise à jour vers la dernière release : %s"
MSG_MAJ_UPDATE_BRANCH_TEMPLATE="⚡  Mécanisme automatique de mise à jour forcée sur la branche %s."
MSG_MAJ_UPDATE_BRANCH_SUCCESS="Script mis à jour !"
MSG_MAJ_UPDATE_BRANCH_REJECTED="Git : Rien à mettre à jour, vous êtes déjà sur la dernière version."
MSG_MAJ_UPDATE_TAG_SUCCESS_TEMPLATE="Script mis à jour vers le tag %s !"
MSG_MAJ_UPDATE_TAG_REJECTED_TEMPLATE="Git : Rien à mettre à jour, vous êtes déjà sur le dernier tag %s."
MSG_MAJ_UPDATE_TAG_FAILED_TEMPLATE="Impossible de mettre à jour vers %s : modifications locales non sauvegardées."


###############################################################################
# Variables techniques
###############################################################################

LOG_LINE_MAX=1000                          # Nombre de lignes maximales (en partant du bas) à afficher dans le rapport par email
TERM_WIDTH_DEFAULT=80                      # Largeur par défaut pour les affichages fixes
LOG_RETENTION_DAYS=15                      # Durée de conservation des logs

# Ne pas toucher
TMP_RCLONE="$SCRIPT_DIR/tmp"           # Répertoire temporaire pour rclone
LOG_DIR="$SCRIPT_DIR/logs"          # Répertoire de logs
JOBS_FILE="$SCRIPT_DIR/jobs.txt"      # Fichier des jobs
EXEMPLE_FILE="${JOBS_FILE}.exemple"      # Fichier des jobs (exemple - vierge)

LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
NOW="$(date '+%Y/%m/%d %H:%M:%S')"

FILE_SCRIPT="main_${LOG_TIMESTAMP}.log"
LOG_FILE_SCRIPT="$LOG_DIR/${FILE_SCRIPT}"
FILE_INFO="rclone_${LOG_TIMESTAMP}.log"
LOG_FILE_INFO="$LOG_DIR/${FILE_INFO}"
FILE_MAIL="msmtp_${LOG_TIMESTAMP}.log"
LOG_FILE_MAIL="$LOG_DIR/${FILE_MAIL}"


# Couleurs ANSI : on utilise $<couleur> pour insérer le caractère ESC réel
ORANGE=$'\e[38;5;208m'              # orange (256-color). Si ton terminal ne supporte pas, ce sera équivalent à une couleur proche.

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
    --stats=0
)
