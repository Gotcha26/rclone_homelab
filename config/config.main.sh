#!/bin/bash

# =========================================================================== #
#         Configuration locale pour script RCLONE_HOMELABE par GOTCHA         #
# =========================================================================== #
# Ce fichier vient surcharger les paramètres par défaut.                      #
#                                                                             #
# Fichier de référence : /opt/rclone_homelab/conf.sh                          #
# =========================================================================== #


# === Variables adaptables ===

DISCORD_WEBHOOK_URL=""                     # URL du webhook salon Discord.
MAIL_TO=""                                 # ARGUMENT - Adresse mail par défaut.

LOG_LINE_MAX=1000                          # Nombre de lignes maximales (en partant du bas) à afficher dans le rapport par email.
TERM_WIDTH_DEFAULT=80                      # Largeur par défaut pour les affichages fixes.
LOG_RETENTION_DAYS=15                      # Durée de conservation des logs.

FORCE_UPDATE=""                            # ARGUMENT - Force à faire les MAJ dès le lancement. Sans argument = sécurité. Accèpte un switch sur une branche spécifique <branche>
DRY_RUN=""                                 # ARGUMENT - Permet de lancer UNIQUEMENT rclone en mode simulation seulement.

LAUNCH_MODE=manual                         # Pour l'instant ne sert pas à grand chose...
DEBUG_MODE=false                           # Action d'aides actives pour le débugage
DEBUG_INFOS=false                          # Quelques informations pour le debugage
DISPLAY_MODE=simplified                    # verbose / simplified / none


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


# =========================================================================== #
# Couleurs personnalisées pour print_fancy()                                  #
#                                                                             #
# Déclaration dans config.local.sh                                            #
# Syntaxe simple : définir une couleur pour le texte et/ou le fond            #
# =========================================================================== #
#                                                                             #
# EXEMPLES :                                                                  #
# MY_ORANGE="256:208"        # Couleur texte 256 couleurs, indice 208         #
# MY_BG_GRAY="256:236"       # Couleur fond 256 couleurs, indice 236          #
# MY_RED="ansi:31"           # Couleur texte ANSI classique (rouge)           #
# MY_BG_BLUE="rgb:255;200;0" # Couleur fond RGB 24-bit                        #
#                                               (rouge=255, vert=200, bleu=0) #
#                                                                             #
# UTILISATION DANS print_fancy :                                              #
# print_fancy --fg "$MY_ORANGE" "Texte orange"                                #
# print_fancy --bg "$MY_BG_GRAY" "Texte sur fond gris"                        #
# print_fancy --fg "$MY_ORANGE" --bg "$MY_BG_GRAY"                            #
#                                                "Texte orange sur fond gris" #
#                                                                             #
# FORMAT ATTENDU :                                                            #
# "ansi:<code>"      -> séquence ANSI classique (30-37,90-97 pour le texte ;  #
#                                                 40-47,100-107 pour le fond) #
# "256:<n>"          -> palette 256 couleurs (0-255)                          #
# "rgb:<r>;<g>;<b>"  -> palette 24-bit RGB (0-255 chacun)                     #
# =========================================================================== #