#!/usr/bin/env bash

###############################################################################
# Fonction : Vérifie la présence de jobs.txt et initialise à partir de jobs.txt.exemple si absent
###############################################################################
init_jobs_file() {

    # Si jobs.conf existe, rien à faire
    if [[ -f "$DIR_JOBS_FILE" ]]; then
        print_fancy --theme "info" "Fichier $JOBS_FILE déjà présent"
        return 0
    fi

    # Sinon, on tente de copier le fichier exemple
    if [[ -f "$DIR_EXEMPLE_JOBS_FILE" ]]; then
        mkdir -p "$(dirname "$DIR_JOBS_FILE")"
        cp "$DIR_EXEMPLE_JOBS_FILE" "$DIR_JOBS_FILE"
        print_fancy --theme "success" "Copie de $EXEMPLE_JOBS_FILE → $JOBS_FILE réalisée"
        return 0
    else
        print_fancy --theme "error" "Erreur dans la copie de $EXEMPLE_JOBS_FILE → $JOBS_FILE"
        return 1
    fi
}


###############################################################################
# Fonction : Initialiser config.local.conf si absent
###############################################################################
init_config_local() {
    local main_conf="$DIR_EXEMPLE_CONF_LOCAL_FILE"
    local conf_file="$DIR_CONF_LOCAL_FILE"

    echo
    echo
    print_fancy --style "underline" "⚙️  Création de $CONF_LOCAL_FILE"
    print_fancy --theme "info" "Vous êtes sur le point de créer un fichier personnalisable de configuration."
    print_fancy --fg "blue" -n "Fichier d'origine : ";
        print_fancy "$main_conf"
    print_fancy --fg "blue" -n "Fichier à créer   : ";
        print_fancy "$conf_file"
    echo
    read -rp "❓  Voulez-vous créer ce fichier ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        print_fancy --theme "info" \
            "Création ignorée pour : $conf_file"
        return 1
    fi

    mkdir -p "$(dirname "$conf_file")" || {
        print_fancy --theme "error" \
            "Impossible de créer le dossier cible $(dirname "$conf_file")";
        return 1;
    }

    cp "$main_conf" "$conf_file" || {
        print_fancy --theme "error" \
            "Impossible de copier $main_conf vers $conf_file";
        return 1;
    }

    print_fancy --theme "success" \
        "Fichier installé : $conf_file"

    # --- Proposer l'édition immédiate avec nano ---
    echo
    read -rp "✏️  Voulez-vous éditer le fichier maintenant avec $EDITOR ? [Y/n] : " EDIT_REPLY
    EDIT_REPLY=${EDIT_REPLY,,}
    if [[ -z "$EDIT_REPLY" || "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        $EDITOR "$conf_file"
    else
        print_fancy --theme "info" \
            "Édition ignorée pour : $conf_file"
    fi
}


###############################################################################
# Fonction : Recherche la présence eventuelle du fichier config.local.conf
###############################################################################
check_config_local () {
    local mode="${1:-${DEBUG_INFO:-false}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    # Vérifier existence
    if [[ ! -f "$DIR_CONF_LOCAL_FILE" ]]; then
        case "$mode" in
            false)    return 1 ;;
            true) print_fancy --theme "error" "$MSG_FILE_NOT_FOUND : $DIR_CONF_LOCAL_FILE" >&2; return 1 ;;
        esac
    fi

    # Si tout est bon
    return 0
}


###############################################################################
# Fonction : Recherche la présence eventuelle du fichier config.dev.conf
###############################################################################
check_config_dev () {
    local mode="${1:-${DEBUG_INFO:-false}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    # Vérifier existence
    if [[ ! -f "$DIR_CONF_DEV_FILE" ]]; then
        case "$mode" in
            false)    return 1 ;;
            true) print_fancy --theme "error" "$MSG_FILE_NOT_FOUND : $DIR_CONF_DEV_FILE" >&2; return 1 ;;
        esac
    fi

    # Si tout est bon
    return 0
}


###############################################################################
# Fonction : Initialiser config.local.sh si absent
###############################################################################
init_secrets_local() {
    local main_conf="$DIR_EXEMPLE_SECRET_FILE"
    local secret_file="$DIR_SECRET_FILE"

    echo
    echo
    print_fancy --style "underline" "⚙️  Création de $SECRET_FILE"
    print_fancy --theme "info" "Vous êtes sur le point de créer un fichier pour vos clés secrètes. (optionnel)"
    print_fancy --fg "blue" -n "Fichier d'origine : ";
        print_fancy "$main_conf"
    print_fancy --fg "blue" -n "Fichier à créer   : ";
        print_fancy "$secret_file"
    echo
    read -rp "❓  Voulez-vous créer ce fichier ? [y/N] : " REPLY
    REPLY=${REPLY,,}
    if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
        print_fancy --theme "info" \
            "Création ignorée pour : $secret_file"
        return 1
    fi

    mkdir -p "$(dirname "$secret_file")" || {
        print_fancy --theme "error" \
            "Impossible de créer le dossier cible $(dirname "$secret_file")";
        return 1;
    }

    cp "$main_conf" "$secret_file" || {
        print_fancy --theme "error" \
            "Impossible de copier $main_conf vers $secret_file";
        return 1;
    }

    print_fancy --theme "success" \
        "Fichier installé : $secret_file"

    # --- Proposer l'édition immédiate avec nano ---
    echo
    read -rp "✏️  Voulez-vous éditer le fichier maintenant avec $EDITOR ? [Y/n] : " EDIT_REPLY
    EDIT_REPLY=${EDIT_REPLY,,}
    if [[ -z "$EDIT_REPLY" || "$EDIT_REPLY" == "y" || "$EDIT_REPLY" == "yes" ]]; then
        $EDITOR "$secret_file"
    else
        print_fancy --theme "info" \
            "Édition ignorée pour : $secret_file"
    fi
}


###############################################################################
# Fonction : Recherche la présence eventuelle du fichier secret.env
###############################################################################
check_secrets_conf () {
    local mode="${1:-${DEBUG_INFO:-false}}" # argument : variable:<defaut> (l'argument prime sur la variable)

    # Vérifier existence
    if [[ ! -f "$DIR_SECRET_FILE" ]]; then
        case "$mode" in
            false)    return 1 ;;
            true) print_fancy --theme "error" "$MSG_FILE_NOT_FOUND : $DIR_SECRET_FILE" >&2; return 1 ;;
        esac
    fi

    # Si tout est bon
    return 0
}


###############################################################################
# Fonction : Récupérer le log précédent afin de l'afficher via le menu
###############################################################################
get_last_log() {
    # Tous les logs triés par date décroissante
    local logs=("$DIR_LOG"/*.log)

    # Aucun log ?
    [[ ${#logs[@]} -eq 0 ]] && echo "" && return

    # Exclure le log actuel
    local previous=""
    for log in "${logs[@]}"; do
        [[ "$log" == "$LOG_FILE_INFO" ]] && continue
        previous="$log"
        break
    done

    echo "$previous"
}