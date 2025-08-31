#!/bin/bash
# Variables spécifiques à l'environnement de DEV

VERSION="v2.3.0"
REPO="Gotcha26/rclone_homelab"
BRANCH="dev"
latest=""
CHECK_UPDATES=false
FORCE_UPDATE=false
FORCE_BRANCH=""     # Dois reserter vide pour prendre en compte "main" par défaut.
UPDATE_TAG=""


# --- Commande pour remettre la branch dev vers main (origin)
# git push -u origin dev
