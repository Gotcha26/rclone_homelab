set -uo pipefail

# Sourcing global
source "$SCRIPT_DIR/config/global.conf"
source "$SCRIPT_DIR/functions/debug.sh"
source "$SCRIPT_DIR/functions/core.sh"
source "$SCRIPT_DIR/libs/lib_gotcha.sh"
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

# *** Action(s) global(s) ***

# Détection du sudo
if [[ $(id -u) -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

# SECURITE - Arbitraire - Valeurs par défaut si les variables ne sont pas définies (avant le contrôle/correction)
: "${DEBUG_INFOS:=false}"
: "${DEBUG_MODE:=false}"
: "${DISPLAY_MODE:=soft}"
: "${ACTION_MODE:=manu}"

# Association des modes si nécessaire (DEBUG)
[[ "$DEBUG_INFOS" == true || "$DEBUG_MODE" == true ]] && DISPLAY_MODE="hard"
[[ "$DEBUG_MODE" == true ]] && ACTION_MODE="manu"

# Répertoire pour les sauvegardes horodatées (MAJ fichiers locaux)
BACKUP_DIR="${DIR_LOCAL}/backups"

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

    # Flag pour savoir si au moins un fichier a été traité
    local files_updated=false

    display_msg "verbose|hard" --theme info "Mise à jour des fichiers locaux..."

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
update_user_file_old() {
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
        return 0
    fi

    # 1. Première exécution : sauvegarde de la version de référence
    if [ ! -f "$last_ref_backup" ]; then
        if mkdir -p "$BACKUP_DIR" && cp "$ref_file" "$last_ref_backup"; then
            print_fancy --theme ok \
                "Initialisation du suivi pour : $user_file"
            print_fancy \
                "   → Référence sauvegardée : $last_ref_backup"
        else
            print_fancy --theme error \
                "Échec de la sauvegarde initiale ($ref_file → $last_ref_backup)"
            return 1
        fi
    fi

    # 2. Vérification des changements
    if ! diff -q "$last_ref_backup" "$ref_file" > /dev/null; then
        echo
        print_fancy --theme warning --bg orange --highlight "Le fichier de référence suivant à été mis à jour :"
        print_fancy --bg orange --highlight --align right --style italic "$ref_file"
        print_fancy --bg orange --highlight --align right ""
        print_fancy --bg orange --style "underline|bold" --highlight "Votre ancien fichier de référence a été sauvegardé et mis de coté."
        echo
        print_fancy --bg orange --highlight --align right "Voici les différences à reporter sur votre installation :"
        if command -v colordiff &> /dev/null; then
            colordiff -u "$last_ref_backup" "$ref_file"
        else
            diff -u "$last_ref_backup" "$ref_file"
        fi

        # 3. Demande de confirmation
        echo
        print_fancy "❓  Souhaitez-vous répercuter automatiquement ces changements sur le fichier :"
        print_fancy --align right --style bold "$user_file"
        print_fancy --theme follow --style italic "☝️  Sachant qu'une sauvegarde a déjà été faite..."
        echo
        read -e -p "Réponse ? (O/n) " -n 1 -r
        echo
        if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
            # 4. Sauvegarde horodatée du fichier local
            local backup_file="$BACKUP_DIR/$(basename "$user_file")_$(date +%Y%m%d_%H%M%S).bak"
            cp "$user_file" "$backup_file"
            print_fancy "📦  Sauvegarde de : $user_file"
            print_fancy "   Vers →        : $backup_file"

            # 5. Application du patch : Merge à 3 voies avec git
            git merge-file -p "$user_file" "$last_ref_backup" "$ref_file" >"$user_file.merged"
            merge_status=$?

            case $merge_status in
                0)
                    # merge clean
                    mv "$user_file.merged" "$user_file"
                    cp "$ref_file" "$last_ref_backup"
                    print_fancy "✅  Mise à jour appliquée automatiquement à $user_file"
                    return 2
                    ;;
                1)
                    # conflits détectés
                    print_fancy "⚠️  Conflits détectés lors de la fusion :"
                    print_fancy "👉  Voir et résoudre manuellement dans : $user_file.merged"
                    print_fancy "    (votre ancien fichier reste inchangé : $user_file)"
                    return 1
                    ;;
                2)
                    # erreur fatale
                    print_fancy --theme error "❌  Erreur fatale lors de la fusion"
                    return 1
                    ;;
            esac

            #  6. On marque que quelque chose a été traité. Drapeau pour update_local_configs()
            files_updated=true
        else
            print_fancy --theme error "Mise à jour annulée par l'utilisateur pour le fichier :"
            print_fancy --fg red --style bold --align right "$user_file"
            echo
            print_fancy "La demande sera réitérée à chaque mise à jour :"
            print_fancy "garantissant une uniformtité des fichiers."
            return 0
        fi
    else
        print_fancy --theme success "$user_file est déjà à jour."
        return 0   # pas de modification
    fi
}



update_user_file() {
    local ref_file="$1"
    local user_file="$2"
    local last_ref_backup="$BACKUP_DIR/last_$(basename "$ref_file")"

    # 1. Vérification de l'existence des fichiers
    # ref_file (bloquand si absent)
    if [ ! -f "$ref_file" ]; then
        print_fancy --theme error "Un problème sérieux → Fichier de référence non présent :"
        print_fancy --fg red --style bold --align right "$ref_file"
        return 1
    fi

    # user_file - Cas où le fichier local n'existe pas → on ignore totalement → pas de suivi
    if [ ! -f "$user_file" ]; then
        display_msg "verbose|hard" "🔎  Fichier local absent, aucun suivi nécessaire pour :"
        display_msg "verbose|hard" --align right "$user_file"
        return 0
    fi

    # 2. Première exécution : sauvegarde de la version de référence
    if [ ! -f "$last_ref_backup" ]; then
        if mkdir -p "$BACKUP_DIR" && cp "$ref_file" "$last_ref_backup"; then
            print_fancy --theme ok "Initialisation du suivi pour : $user_file"
            print_fancy "   → Référence sauvegardée : $last_ref_backup"
        else
            print_fancy --theme error "Échec de la sauvegarde initiale, concerne :"
            print_fancy --fb red --style bold "Fichier : $ref_file"
            print_fancy --fb red --style bold "Pour    → $last_ref_backup"
            return 1
        fi
    fi

    # 3.Vérification changements
    if diff -q "$last_ref_backup" "$ref_file" > /dev/null; then
        display_msg "verbose|hard" --theme ok "Fichier déjà à jour et passé :"
        display_msg "verbose|hard" --align right "$user_file"
        return 0
    fi

    # 4. Affichage des différences
    echo
    print_fancy --theme warning --bg orange --highlight "Le fichier de référence suivant est à mettre à jour :"
    print_fancy --bg orange --highlight --align right --style italic "$ref_file"
    echo
    print_fancy --bg orange --highlight --align right "Voici les différences :"
    if command -v colordiff &> /dev/null; then
        colordiff -u "$last_ref_backup" "$ref_file"
    else
        diff -u "$last_ref_backup" "$ref_file"
    fi
    echo

    # 5. Confirmation utilisateur
    print_fancy "Une montée de version automatique (upgrade) est possible ci-après."
    print_fancy "Le procédé va préserver les clés ainsi que leurs valeurs associées."
    print_fancy --style "underline|bold" --align center "Tout le reste sera écrasé !"
    print_fancy --style italic --align center "(Une sauvegarde préalable sera faite avant toute intervention...)"
    echo
    print_fancy "❓  Voulez-vous procéder à ce remplacement ?"
    read -e -p "Réponse ? (O/n) " -n 1 -r
    echo
    if [[ -n "$REPLY" && ! "$REPLY" =~ ^[OoYy]$ ]]; then
        print_fancy --theme error "Mise à jour annulée par l'utilisateur pour : $user_file"
        return 0
    fi

    # 5.1. Sauvegarde horodatée du fichier utilisateur
    local backup_file="$BACKUP_DIR/$(basename "$user_file")_$(date +%Y%m%d_%H%M%S).bak"
    cp "$user_file" "$backup_file"
    print_fancy "📦  Sauvegarde de : $user_file"
    print_fancy "   Vers →        : $backup_file"

    # 5.2. Extraction des valeurs existantes pour les clés connues
    declare -A user_values
    while IFS='=' read -r key value; do
        # Nettoyage espaces en début/fin
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ -n "$key" && -n "${VARS_TO_VALIDATE[$key]+_}" ]] && user_values[$key]="$value"
    done < "$user_file"

    # 5.3. Extraction de toutes les clés étrangères pour les conserver
    declare -A foreign_values
    while IFS='=' read -r key value; do
        # Nettoyage espaces en début/fin
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ -n "$key" && -z "${VARS_TO_VALIDATE[$key]+_}" ]] && foreign_values[$key]="$value"
    done < "$user_file"

    # 5.4. Génération du nouveau fichier basé sur la référence
    local tmp_file
    tmp_file="$(mktemp)"
    while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Za-z0-9_]+)=(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            if [[ -n "${user_values[$key]+_}" ]]; then
                # Clé connue → conserver valeur utilisateur
                echo "$key=${user_values[$key]}" >> "$tmp_file"
            elif [[ -n "${foreign_values[$key]+_}" ]]; then
                # Clé étrangère → conserver valeur originale
                echo "$key=${foreign_values[$key]}" >> "$tmp_file"
            else
                # Nouvelle clé → prendre la valeur de référence
                echo "$line" >> "$tmp_file"
            fi
        else
            # Lignes non key=value → copier
            echo "$line" >> "$tmp_file"
        fi
    done < "$ref_file"

    # 5.5. Remplacement du fichier utilisateur
    mv "$tmp_file" "$user_file"
    print_fancy "✅  Mise à jour effectuée :"
    print_fancy "Valeurs clés conservées, reste remplacé par la référence, clés étrangères préservées."
    print_fancy "Fichier traité :"
    print_fancy --align right "$user_file"
    

    # 5.6. Mise à jour du backup de référence
    if cp "$ref_file" "$last_ref_backup"; then
        display_msg "verbose|hard" --theme ok "Mise à jour de la sauvegarde pour le fichier 'ref_file'"
    else
        print_fancy --theme error "Un problème en voulant mettre à jour la sauvegarde pour 'ref_file' !"
    fi

    # 5.7. On marque que quelque chose a été traité. Drapeau pour update_local_configs()
    files_updated=true
    return 2
}