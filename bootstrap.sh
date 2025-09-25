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

# *** ↓↓ FONCTIONS PERSISTANTES (en cas de MAJ) ↓↓ ***

###############################################################################
# Fonction : Rendre des scripts exécutables (utile après une MAJ notamment)
###############################################################################
make_scripts_executable() {

    # Se placer dans un répertoire sûr pour éviter getcwd errors
    if cd /; then
        display_msg "hard" --theme info "Changement de répertoire vers / réussi."
        return 0
    else
        display_msg "soft|verbose|hard" --theme error "Impossible de changer de répertoire vers / ."
        return 1
    fi

    local base_dir="${1:-$SCRIPT_DIR}"
    local scripts=(
        "$SCRIPT_DIR/main.sh"
        "$SCRIPT_DIR/update/standalone_updater.sh"
    )

    # Vérifier que base_dir est défini
    if [[ -z "$base_dir" ]]; then
        display_msg "soft|verbose|hard" --theme error "ERREUR: variable non défini $base_dir"
        return 1
    else
        display_msg "hard" --theme info "base_dir correctement défini ou présent."
        return 0
    fi

    # Vérifier que base_dir existe
    if [[ ! -d "$base_dir" ]]; then
        display_msg "soft|verbose|hard" --theme error "ERREUR: le répertoire n'existe pas : $base_dir"
        return 1
    else
        display_msg "hard" --theme info "Le répertoire validée : $base_dir"
        return 0
    fi

    for s in "${scripts[@]}"; do
        local f="$base_dir/$s"
        if [[ -f "$f" ]]; then
            chmod +x "$f"
            display_msg "soft|verbose|hard" --theme info "chmod +x correctement appliqué sur :"
            display_msg "soft|verbose|hard" --align "right" --fg "light_blue" "$f"
            return 0
        else
            display_msg "verbose|hard"  --theme "warning" "Fichier absent :"
            display_msg "verbose|hard"  --align "right" --fg "red" "$f"
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
    mkdir -p "$BACKUP_DIR"

    update_user_file() {
        local ref_file="$1"
        local user_file="$2"
        local last_ref_backup="$BACKUP_DIR/last_$(basename "$ref_file")"

        # Vérification de l'existence des fichiers
        if [ ! -f "$ref_file" ]; then
            echo "⚠️  Fichier de référence non présent : $ref_file"
            return 1
        fi
        if [ ! -f "$user_file" ]; then
            echo "🔎  Fichier local non présent : $user_file"
        fi

        # 1. Première exécution : sauvegarde de la version de référence
        if [ ! -f "$last_ref_backup" ]; then
            cp "$ref_file" "$last_ref_backup"
            echo "✅  Première exécution pour $user_file : sauvegarde de la version de référence."
        fi

        # 2. Vérification des changements
        if ! diff -q "$last_ref_backup" "$ref_file" > /dev/null; then
            echo "⚠️  Le fichier de référence $ref_file a été mis à jour. Voici les différences :"
            if command -v colordiff &> /dev/null; then
                colordiff -u "$last_ref_backup" "$ref_file"
            else
                diff -u "$last_ref_backup" "$ref_file"
            fi

            # 3. Demande de confirmation
            read -p "Souhaitez-vous appliquer ces changements à $user_file ? (o/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Oo]$ ]]; then
                # 4. Sauvegarde horodatée du fichier local
                local backup_file="$BACKUP_DIR/$(basename "$user_file")_$(date +%Y%m%d_%H%M%S).bak"
                cp "$user_file" "$backup_file"
                echo "📦  Sauvegarde de $user_file : $backup_file"

                # 5. Application du patch
                diff -u "$last_ref_backup" "$ref_file" > "/tmp/$(basename "$user_file").patch"
                if patch -p0 -i "/tmp/$(basename "$user_file").patch" "$user_file" -o "$user_file.tmp"; then
                    mv "$user_file.tmp" "$user_file"
                    echo "✅  Mises à jour appliquées à $user_file."
                else
                    echo "⚠️  Conflits détectés. Patch enregistré : /tmp/$(basename "$user_file").patch"
                    mv "$backup_file" "$user_file"  # Restauration
                    echo "🔄  $user_file restauré depuis la sauvegarde."
                fi
                # 6. Mise à jour du backup de référence
                cp "$ref_file" "$last_ref_backup"

                # On marque que quelque chose a été traité
                files_updated=true
            else
                echo "❌  Mise à jour annulée pour $user_file."
            fi
        else
            echo "✅  $user_file est déjà à jour."
        fi
    }

    # Flag pour savoir si au moins un fichier a été traité
    local files_updated=false

    # Liste des fichiers à traiter (référence, local)
    # Format : ["nom_unique"]="référence;local"
    declare -A files=(
        ["fichier1"]="${DIR_EXEMPLE_CONF_LOCAL_FILE};${DIR_CONF_DEV_FILE}"
        ["fichier2"]="${DIR_EXEMPLE_CONF_LOCAL_FILE};${DIR_CONF_LOCAL_FILE}"
        ["fichier3"]="${DIR_EXEMPLE_JOBS_FILE};${DIR_JOBS_FILE}"
        ["fichier4"]="${DIR_EXEMPLE_SECRET_FILE};${DIR_SECRET_FILE}"
        # Ajoutez d'autres fichiers ici
    )

    # Boucle pour traiter chaque fichier
    for key in "${!files[@]}"; do
        IFS=';' read -r ref_file user_file <<< "${files[$key]}"
        update_user_file "$ref_file" "$user_file"
    done

    # Code retour et message final
    if [[ "$files_updated" == true ]]; then
        return 0
    else
        echo "ℹ️  Aucun changement détecté sur les fichiers d'exemples."
        return 2
    fi

}
