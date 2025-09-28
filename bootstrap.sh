set -uo pipefail

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

# *** ↓↓ Déclarations ↓↓ ***

# Tableau associatif : varaibles locales utilisateur avec les règles
declare -A VARS_TO_VALIDATE=(
    [DRY_RUN]="bool:false"
    [MAIL_TO]="''"
    [DISCORD_WEBHOOK_URL]="''"
    [FORCE_UPDATE]="bool:false"
    [FORCE_BRANCH]="''"
    [ACTION_MODE]="auto|manu:manu"
    [DISPLAY_MODE]="soft|verbose|hard:soft"
    [TERM_WIDTH_DEFAULT]="80-120:80"
    [LOG_RETENTION_DAYS]="1-15:14"
    [LOG_LINE_MAX]="100-10000:1000"
    [EDITOR]="nano|micro:nano"
    [DEBUG_INFOS]="bool:false"
    [DEBUG_MODE]="bool:false"
)

# Tableau couple fichier exemple : fichier local
# Format : ["nom_unique"]="référence;local"
declare -A VARS_LOCAL_FILES=(
    ["conf_local"]="${DIR_EXEMPLE_CONF_LOCAL_FILE};${DIR_CONF_DEV_FILE}"
    ["conf_dev"]="${DIR_EXEMPLE_CONF_LOCAL_FILE};${DIR_CONF_LOCAL_FILE}"
    ["jobs"]="${DIR_EXEMPLE_JOBS_FILE};${DIR_JOBS_FILE}"
    ["conf_secret"]="${DIR_EXEMPLE_SECRET_FILE};${DIR_SECRET_FILE}"
    # Ajoutez d'autres fichiers ici

)

# *** ↓↓ FONCTIONS PERSISTANTES (en cas de MAJ) ↓↓ ***

###############################################################################
# Fonction : Rendre des scripts exécutables (utile après une MAJ notamment)
###############################################################################
make_scripts_executable() {

    # Se placer dans un répertoire sûr pour éviter getcwd errors
    if cd /; then
        display_msg "hard" --theme info "Changement de répertoire vers / réussi."
    else
        display_msg "soft|verbose|hard" --theme error "Impossible de changer de répertoire vers / ."
        return 1
    fi

    local scripts=(
        "$SCRIPT_DIR/main.sh"
        "$SCRIPT_DIR/update/standalone_updater.sh"
    )

    for s in "${scripts[@]}"; do
        if [[ -f "$s" ]]; then
            chmod +x "$s"
            display_msg "verbose|hard" --theme info "chmod +x correctement appliqué sur :"
            display_msg "verbose|hard" --align "right" --fg "light_blue" "$s"
        else
            display_msg "verbose|hard"  --theme "warning" "Fichier absent :"
            display_msg "verbose|hard"  --align "right" --fg "red" "$s"
            return 1
        fi
    done
}


###############################################################################
# Fonction : Mise à jour (upgrade) des fichiers exemples à destination des fichiers locaux (préférences utilisateurs)
# https://chat.mistral.ai/chat/20d4c4a2-08ff-46bb-9920-3abb12adcaa6
###############################################################################
# Fonction pour mettre à jour un fichier local
update_local_configs() {

    # Répertoire pour les sauvegardes horodatées
    BACKUP_DIR="${DIR_LOCAL}/backups"

    # Flag pour savoir si au moins un fichier a été traité
    local files_updated=false

    # Boucle pour traiter chaque fichier
    for key in "${!VARS_LOCAL_FILES[@]}"; do
        IFS=';' read -r ref_file user_file <<< "${VARS_LOCAL_FILES[$key]}"
        update_user_file "$ref_file" "$user_file"
        [[ $? -eq 2 ]] && files_updated=true
    done

    # Code retour et message final
    if [[ "$files_updated" == true ]]; then
        return 2
    else
        display_msg "soft|verbose|hard" --theme info "Aucun changement détecté sur les fichiers d'exemples."
        return 0
    fi

}


###############################################################################
# Fonction : Permet de mettre à jour les fichiers locaux en se basant sur les fichiers de références (exemples_files)
# https://chatgpt.com/share/68d671af-f828-8004-adeb-9554a00d1382
###############################################################################
update_user_file() {
    local ref_file="$1"
    local user_file="$2"
    local last_ref_backup="$BACKUP_DIR/last_$(basename "$ref_file")"

    # Vérification de l'existence des fichiers
    if [ ! -f "$ref_file" ]; then
        display_msg "soft" --theme error "Fichier de référence non présent : $ref_file"
        display_msg "verbose|hard" --theme error "Un problème sérieux → Fichier de référence non présent : $ref_file"
        return 1
    fi

    # Cas où le fichier local n'existe pas → on ignore totalement → pas de suivi
    if [ ! -f "$user_file" ]; then
        display_msg "verbose|hard" "🔎  Fichier local absent, aucun suivi nécessaire : $user_file"
        [ -f "$last_ref_backup" ] && rm -f "$last_ref_backup" \
            && display_msg "verbose|hard" --theme warning "Backup inutile supprimé : $last_ref_backup"
        return 0
    fi

    # 1. Première exécution : sauvegarde de la version de référence
    if [ ! -f "$last_ref_backup" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$ref_file" "$last_ref_backup"
        display_msg "soft|verbose|hard" --theme ok "Première exécution pour $user_file : sauvegarde de la version de référence."
    fi

    # 2. Vérification des changements
    if ! diff -q "$last_ref_backup" "$ref_file" > /dev/null; then
        display_msg "soft|verbose|hard" --theme warning --bg orange --highlight "Le fichier de référence suivant à été mis à jour :"
        display_msg "soft|verbose|hard" --bg orange --highlight align right --style italic "$ref_file"
        display_msg "soft|verbose|hard" --bg orange --highlight align right ""
        display_msg "soft|verbose|hard" --bg orange --style underline --highlight "Votre ancien fichier de référence a été sauvegardé et mis de coté."
        display_msg "soft|verbose|hard" --bg orange --highlight align right "Voici les différences :"
        if command -v colordiff &> /dev/null; then
            colordiff -u "$last_ref_backup" "$ref_file"
        else
            diff -u "$last_ref_backup" "$ref_file"
        fi

        # 3. Demande de confirmation
        display_msg "soft|verbose|hard" ""
        display_msg "soft|verbose|hard" "Souhaitez-vous appliquer ces changements à votre propre fichier :"
        display_msg "soft|verbose|hard" --align right --style italic "$user_file"
        read -p "Réponse ? (o/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Oo]$ ]]; then
            # 4. Sauvegarde horodatée du fichier local
            local backup_file="$BACKUP_DIR/$(basename "$user_file")_$(date +%Y%m%d_%H%M%S).bak"
            cp "$user_file" "$backup_file"
            echo "📦  Sauvegarde de $user_file : $backup_file"

            # 5. Application du patch
            diff -u --label "$user_file" "$last_ref_backup" "$ref_file" > "/tmp/$(basename "$user_file").patch"
            if patch -p0 -i "/tmp/$(basename "$user_file").patch" "$user_file" -o "$user_file.tmp"; then
                mv "$user_file.tmp" "$user_file"
                echo "✅  Mises à jour appliquées à $user_file."
                return 2   # signaler qu’une maj a été appliquée
            else
                echo "⚠️  Conflits détectés. Patch enregistré : /tmp/$(basename "$user_file").patch"
                mv "$backup_file" "$user_file"  # Restauration
                echo "🔄  $user_file restauré depuis la sauvegarde."
                return 1   # échec maj
            fi
            # 6. Mise à jour du backup de référence
            cp "$ref_file" "$last_ref_backup"

            # On marque que quelque chose a été traité
            files_updated=true
        else
            print_fancy --theme error "Mise à jour annulée pour $user_file."
            return 0
        fi
    else
        display_msg "verbose|hard" --theme success "$user_file est déjà à jour."
        return 0   # pas de modification
    fi
}