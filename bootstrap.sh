#!/usr/bin/env bash

# Résoudre le chemin réel du script (suivi des symlinks)
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Sourcing global
source "$SCRIPT_DIR/config/global.conf"
source "$SCRIPT_DIR/functions/debug.sh"
source "$SCRIPT_DIR/functions/dependances.sh"
source "$SCRIPT_DIR/functions/core.sh"
source "$SCRIPT_DIR/update/updater.sh"

source "$SCRIPT_DIR/export/mail.sh"
source "$SCRIPT_DIR/export/discord.sh"

# Surchage via configuration local
load_optional_configs