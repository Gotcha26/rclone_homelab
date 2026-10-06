###############################################################################
# Constante : Tag d'identification des entrées cron créées par rclone_homelab
###############################################################################
CRON_TAG="# rclone_homelab"


###############################################################################
# Fonction : Échappe les % en \% pour la compatibilité crontab
# Usage    : _cron_escape_percent "string"
# Retour   : chaîne échappée sur stdout
###############################################################################
_cron_escape_percent() {
    printf '%s' "${1//%/\\%}"
}


###############################################################################
# Fonction : Indique si une ligne crontab est une tâche gérée par rclone_homelab
# (tag en fin de ligne, ligne non commentée)
# Usage    : _cron_is_managed_line "ligne"
###############################################################################
_cron_is_managed_line() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*# ]] && return 1
    [[ "$line" == *" $CRON_TAG" ]]
}


###############################################################################
# Fonction : Remplace (ou supprime) UNE ligne du crontab, par égalité exacte
# Usage    : _cron_replace_line "ancienne ligne" ["nouvelle ligne"]
# Retour   : 0 si succès, 1 si ligne introuvable ou échec crontab
###############################################################################
_cron_replace_line() {
    local old="$1" new="${2:-}"
    local line replaced=false
    local -a out=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$replaced" == false && "$line" == "$old" ]]; then
            replaced=true
            [[ -n "$new" ]] && out+=("$new")
            continue
        fi
        out+=("$line")
    done < <(crontab -l 2>/dev/null)

    [[ "$replaced" == true ]] || return 1
    printf '%s\n' "${out[@]}" | crontab - 2>/dev/null
}


###############################################################################
# Fonction : Valide un entier dans un intervalle (base 10 : "08" accepté)
# Usage    : _cron_valid_int "valeur" min max
# Retour   : valeur normalisée sur stdout, code 1 si invalide
###############################################################################
_cron_valid_int() {
    local value="$1" min="$2" max="$3"
    [[ "$value" =~ ^[0-9]{1,3}$ ]] || return 1
    value=$(( 10#$value ))
    (( value >= min && value <= max )) || return 1
    echo "$value"
}


###############################################################################
# Fonction : Demande le jour de la semaine
# Retour   : valeur cron (0-7 ou *) sur stdout, code 1 si abandon
###############################################################################
_cron_ask_day_of_week() {
    local choice

    echo >/dev/tty
    print_fancy --theme info "Étape 1/7 — Jour de la semaine" >/dev/tty
    echo >/dev/tty
    echo "  1) Tous les jours" >/dev/tty
    echo "  2) Lundi       3) Mardi       4) Mercredi" >/dev/tty
    echo "  5) Jeudi       6) Vendredi    7) Samedi" >/dev/tty
    echo "  8) Dimanche" >/dev/tty
    echo >/dev/tty

    read -e -rp "  Choix [1-8, défaut: 1] : " choice </dev/tty || return 1
    choice="${choice:-1}"

    case "$choice" in
        1) echo "*" ;;
        2) echo "1" ;;
        3) echo "2" ;;
        4) echo "3" ;;
        5) echo "4" ;;
        6) echo "5" ;;
        7) echo "6" ;;
        8) echo "0" ;;
        *)
            print_fancy --theme error "Choix invalide." >/dev/tty
            return 1
            ;;
    esac
    return 0
}


###############################################################################
# Fonction : Demande l'heure (0-23)
# Retour   : valeur sur stdout, code 1 si invalide
###############################################################################
_cron_ask_hour() {
    local hour

    echo >/dev/tty
    print_fancy --theme info "Étape 2/7 — Heure d'exécution" >/dev/tty
    echo >/dev/tty

    read -e -rp "  Heure (0-23) [défaut: 3] : " hour </dev/tty || return 1
    hour="${hour:-3}"

    if _cron_valid_int "$hour" 0 23; then
        return 0
    else
        print_fancy --theme error "Heure invalide (attendu : 0-23)." >/dev/tty
        return 1
    fi
}


###############################################################################
# Fonction : Demande la minute (0-59)
# Retour   : valeur sur stdout, code 1 si invalide
###############################################################################
_cron_ask_minute() {
    local minute

    echo >/dev/tty
    print_fancy --theme info "Étape 3/7 — Minute d'exécution" >/dev/tty
    echo >/dev/tty

    read -e -rp "  Minute (0-59) [défaut: 0] : " minute </dev/tty || return 1
    minute="${minute:-0}"

    if _cron_valid_int "$minute" 0 59; then
        return 0
    else
        print_fancy --theme error "Minute invalide (attendu : 0-59)." >/dev/tty
        return 1
    fi
}


###############################################################################
# Fonction : Demande si --dry-run doit être activé
# Retour   : code 0 = oui (activer), code 1 = non
###############################################################################
_cron_ask_dry_run() {
    local reply
    local default="n"
    [[ "${DRY_RUN:-false}" == "true" ]] && default="O"

    echo >/dev/tty
    print_fancy --theme info "Étape 4/7 — Mode simulation (--dry-run)" >/dev/tty
    echo >/dev/tty

    read -e -rp "  Activer --dry-run ? (O/n) [défaut: $default] : " reply </dev/tty
    reply="${reply:-$default}"

    [[ "$reply" =~ ^[OoYy]$ ]]
}


###############################################################################
# Fonction : Demande l'adresse email pour --mailto
# Retour   : adresse sur stdout (peut être vide), code 0 toujours
###############################################################################
_cron_ask_mailto() {
    local email default_email

    default_email="${MAIL_TO:-}"

    echo >/dev/tty
    print_fancy --theme info "Étape 5/7 — Rapport par email (--mailto)" >/dev/tty
    echo >/dev/tty

    if [[ -n "$default_email" ]]; then
        read -e -rp "  Adresse email [défaut: $default_email] : " email </dev/tty
        email="${email:-$default_email}"
    else
        read -e -rp "  Adresse email [laisser vide si aucun] : " email </dev/tty
    fi

    # Validation si non vide
    if [[ -n "$email" ]]; then
        if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo "$email"
        else
            print_fancy --theme error "Format d'email invalide." >/dev/tty
            print_fancy --theme follow "Réessayez ou laissez vide pour ignorer." >/dev/tty
            read -e -rp "  Adresse email : " email </dev/tty
            if [[ -n "$email" && "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                echo "$email"
            elif [[ -n "$email" ]]; then
                print_fancy --theme warning "Email ignoré (format invalide)." >/dev/tty
            fi
        fi
    fi
    return 0
}


###############################################################################
# Fonction : Demande l'URL Discord webhook pour --discord-url
# Retour   : URL sur stdout (peut être vide), code 0 toujours
###############################################################################
_cron_ask_discord_url() {
    local url default_url

    default_url="${DISCORD_WEBHOOK_URL:-}"

    echo >/dev/tty
    print_fancy --theme info "Étape 6/7 — Notification Discord (--discord-url)" >/dev/tty
    echo >/dev/tty

    if [[ -n "$default_url" ]]; then
        read -e -rp "  URL Discord webhook [défaut: configurée] : " url </dev/tty
        url="${url:-$default_url}"
    else
        read -e -rp "  URL Discord webhook [laisser vide si aucun] : " url </dev/tty
    fi

    # Validation si non vide
    if [[ -n "$url" ]]; then
        if [[ "$url" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/ ]]; then
            echo "$url"
        else
            print_fancy --theme error "URL Discord invalide." >/dev/tty
            print_fancy --theme follow "Format attendu : https://discord.com/api/webhooks/..." >/dev/tty
            read -e -rp "  URL Discord webhook : " url </dev/tty
            if [[ -n "$url" && "$url" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/ ]]; then
                echo "$url"
            elif [[ -n "$url" ]]; then
                print_fancy --theme warning "URL Discord ignorée (format invalide)." >/dev/tty
            fi
        fi
    fi
    return 0
}


###############################################################################
# Fonction : Demande les options rclone supplémentaires
# Retour   : texte libre sur stdout (peut être vide)
###############################################################################
_cron_ask_extra_opts() {
    local opts

    echo >/dev/tty
    print_fancy --theme info "Étape 7/7 — Options rclone supplémentaires" >/dev/tty
    echo >/dev/tty

    read -e -rp "  Options rclone (ex: --transfers 4 --fast-list) [vide si aucune] : " opts </dev/tty
    echo "$opts"
    return 0
}


###############################################################################
# Fonction : Convertit le code DOW cron en libellé français
# Usage    : _cron_dow_label "*"  →  "Tous les jours"
###############################################################################
_cron_dow_label() {
    case "$1" in
        '*') echo "Tous les jours" ;;
        1)   echo "Lundi" ;;
        2)   echo "Mardi" ;;
        3)   echo "Mercredi" ;;
        4)   echo "Jeudi" ;;
        5)   echo "Vendredi" ;;
        6)   echo "Samedi" ;;
        0)   echo "Dimanche" ;;
        *)   echo "$1" ;;
    esac
}


###############################################################################
# Fonction : Affiche le résumé de la tâche cron avant confirmation
# Arguments : cron_line dow hour minute dry_run mailto discord extra
###############################################################################
_cron_show_summary() {
    local cron_line="$1"
    local dow="$2" hour="$3" minute="$4"
    local dry_run="$5" mailto="$6" discord="$7" extra="$8"

    local dow_label
    dow_label=$(_cron_dow_label "$dow")

    echo >/dev/tty
    print_fancy --align center "═══════════════════════════════════════" >/dev/tty
    print_fancy --align center "📋  RÉSUMÉ DE LA TÂCHE CRON" >/dev/tty
    print_fancy --align center "═══════════════════════════════════════" >/dev/tty
    echo >/dev/tty

    # Heure lisible si numérique, sinon champs cron bruts (ex. */2)
    local when="${hour}:${minute}"
    [[ "$hour" =~ ^[0-9]+$ && "$minute" =~ ^[0-9]+$ ]] && when=$(printf '%02d:%02d' "$((10#$hour))" "$((10#$minute))")

    printf "  %-16s : %s (%s)\n" "Planification" "$dow_label" "$when" >/dev/tty
    printf "  %-16s : %s\n" "--dry-run" "${dry_run:-Non}" >/dev/tty
    printf "  %-16s : %s\n" "--mailto" "${mailto:-(aucun)}" >/dev/tty
    printf "  %-16s : %s\n" "--discord-url" "${discord:-(aucun)}" >/dev/tty
    printf "  %-16s : %s\n" "Options extra" "${extra:-(aucune)}" >/dev/tty

    echo >/dev/tty
    print_fancy --theme follow "Ligne cron :" >/dev/tty
    print_fancy --fg blue "$cron_line" >/dev/tty
}


###############################################################################
# Fonction : Installe une ligne dans le crontab de l'utilisateur courant
# Usage    : _cron_install "ligne cron complète"
###############################################################################
_cron_install() {
    local new_line="$1"

    # Récupérer le crontab existant (peut être vide)
    local existing
    existing=$(crontab -l 2>/dev/null || true)

    # Ajouter la nouvelle ligne et réinstaller
    if printf '%s\n%s\n' "$existing" "$new_line" | crontab - 2>/dev/null; then
        print_fancy --theme success "Tâche Cron installée avec succès !"
    else
        print_fancy --theme error "Échec de l'installation de la tâche Cron."
        return 1
    fi
}


###############################################################################
# Fonction : Assistant pas-à-pas pour créer une tâche cron
###############################################################################
cron_add_wizard() {
    echo
    print_fancy --theme info "Assistant de création d'une tâche Cron"
    print_fancy --theme follow "Répondez aux questions suivantes (ou tapez 'q' pour abandonner) :"

    # Étape 1 : Jour de la semaine
    local dow
    dow=$(_cron_ask_day_of_week) || return 1

    # Étape 2 : Heure
    local hour
    hour=$(_cron_ask_hour) || return 1

    # Étape 3 : Minute
    local minute
    minute=$(_cron_ask_minute) || return 1

    # Étape 4 : Dry-run
    local dry_run_flag="" dry_run_label="Non"
    if _cron_ask_dry_run; then
        dry_run_flag="--dry-run"
        dry_run_label="Oui"
    fi

    # Étape 5 : Email
    local mailto_flag="" mailto_addr
    mailto_addr=$(_cron_ask_mailto)
    [[ -n "$mailto_addr" ]] && mailto_flag="--mailto=$(_cron_escape_percent "$mailto_addr")"

    # Étape 6 : Discord
    local discord_flag="" discord_url
    discord_url=$(_cron_ask_discord_url)
    [[ -n "$discord_url" ]] && discord_flag="--discord-url=$(_cron_escape_percent "$discord_url")"

    # Étape 7 : Options supplémentaires
    local extra_opts
    extra_opts=$(_cron_ask_extra_opts)

    # Construction de la commande
    local cron_cmd="$SCRIPT_PATH --auto"
    [[ -n "$dry_run_flag" ]]  && cron_cmd+=" $dry_run_flag"
    [[ -n "$mailto_flag" ]]   && cron_cmd+=" $mailto_flag"
    [[ -n "$discord_flag" ]]  && cron_cmd+=" $discord_flag"
    [[ -n "$extra_opts" ]]    && cron_cmd+=" $(_cron_escape_percent "$extra_opts")"

    # PATH inline pour l'environnement cron
    local cron_path="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    # Ligne cron complète
    local cron_line="${minute} ${hour} * * ${dow} ${cron_path} ${cron_cmd} ${CRON_TAG}"

    # Résumé
    _cron_show_summary "$cron_line" "$dow" "$hour" "$minute" \
        "$dry_run_label" "$mailto_addr" "$discord_url" "$extra_opts"

    # Confirmation
    echo
    local confirm
    read -e -rp "  Installer cette tâche Cron ? (O/n) : " confirm </dev/tty || confirm="n"
    if [[ -z "$confirm" || "$confirm" =~ ^[OoYy]$ ]]; then
        _cron_install "$cron_line"
    else
        print_fancy --theme warning "Installation annulée."
    fi
}


###############################################################################
# Fonction : Liste les tâches cron rclone_homelab de l'utilisateur courant
###############################################################################
cron_list() {
    echo
    print_fancy --theme info "Tâches Cron pour rclone_homelab :"
    echo

    local existing
    existing=$(crontab -l 2>/dev/null || true)

    if [[ -z "$existing" ]]; then
        print_fancy --theme warning "Aucune tâche cron définie."
        return 0
    fi

    local found=false
    local idx=1
    local line
    while IFS= read -r line; do
        if _cron_is_managed_line "$line"; then
            printf "  [%d] %s\n" "$idx" "$line"
            found=true
            ((idx++))
        fi
    done <<< "$existing"

    if [[ "$found" == false ]]; then
        print_fancy --theme warning "Aucune tâche rclone_homelab trouvée dans le crontab."
    fi
}


###############################################################################
# Fonction : Supprime une tâche cron rclone_homelab choisie par l'utilisateur
###############################################################################
cron_remove() {
    echo

    local existing
    existing=$(crontab -l 2>/dev/null || true)

    if [[ -z "$existing" ]]; then
        print_fancy --theme warning "Aucune tâche cron définie."
        return 0
    fi

    # Collecter les lignes correspondantes
    local -a cron_lines=()
    local line
    while IFS= read -r line; do
        _cron_is_managed_line "$line" && cron_lines+=("$line")
    done <<< "$existing"

    if [[ ${#cron_lines[@]} -eq 0 ]]; then
        print_fancy --theme warning "Aucune tâche rclone_homelab trouvée."
        return 0
    fi

    # Afficher les entrées numérotées
    print_fancy --theme info "Tâches Cron rclone_homelab :"
    echo
    local i
    for i in "${!cron_lines[@]}"; do
        printf "  [%d] %s\n" "$((i+1))" "${cron_lines[$i]}"
    done
    echo

    local choice
    read -e -rp "  Numéro de la tâche à supprimer [1-${#cron_lines[@]}] ou q : " choice </dev/tty || return 0

    if [[ "$choice" == "q" ]]; then
        return 0
    fi

    if choice=$(_cron_valid_int "$choice" 1 "${#cron_lines[@]}"); then
        local to_remove="${cron_lines[$((choice-1))]}"

        # Supprimer uniquement cette ligne (égalité exacte, pas de sous-chaîne)
        if _cron_replace_line "$to_remove"; then
            print_fancy --theme success "Tâche Cron supprimée avec succès."
        else
            print_fancy --theme error "Échec de la suppression."
        fi
    else
        print_fancy --theme error "Choix invalide."
    fi
}


###############################################################################
# Fonction : Parse une ligne cron rclone_homelab et extrait ses composants
# Usage    : _cron_parse_line "ligne cron"
# Exporte  : CRON_PARSE_MINUTE, CRON_PARSE_HOUR, CRON_PARSE_DOM,
#            CRON_PARSE_MONTH, CRON_PARSE_DOW,
#            CRON_PARSE_DRY_RUN, CRON_PARSE_MAILTO, CRON_PARSE_DISCORD,
#            CRON_PARSE_EXTRA
###############################################################################
_cron_parse_line() {
    local line="$1"

    # Découpage en mots (sans le tag final) — read -a ne fait pas de glob
    local -a fields=()
    read -r -a fields <<< "${line% "$CRON_TAG"}"

    # Champs cron : minute heure jour_mois mois jour_semaine ...
    CRON_PARSE_MINUTE="${fields[0]:-0}"
    CRON_PARSE_HOUR="${fields[1]:-0}"
    CRON_PARSE_DOM="${fields[2]:-*}"
    CRON_PARSE_MONTH="${fields[3]:-*}"
    CRON_PARSE_DOW="${fields[4]:-*}"

    CRON_PARSE_DRY_RUN="Non"
    CRON_PARSE_MAILTO=""
    CRON_PARSE_DISCORD=""

    # Commande : flags connus extraits par mot exact, le reste = options extra
    local -a extra=()
    local i tok
    for (( i=5; i<${#fields[@]}; i++ )); do
        tok="${fields[$i]}"
        case "$tok" in
            PATH=*|*/main.sh|--auto) ;;
            --dry-run)       CRON_PARSE_DRY_RUN="Oui" ;;
            --mailto=*)      CRON_PARSE_MAILTO="${tok#--mailto=}"; CRON_PARSE_MAILTO="${CRON_PARSE_MAILTO//\\%/%}" ;;
            --discord-url=*) CRON_PARSE_DISCORD="${tok#--discord-url=}"; CRON_PARSE_DISCORD="${CRON_PARSE_DISCORD//\\%/%}" ;;
            *)               extra+=("${tok//\\%/%}") ;;   # \% rétabli : il sera ré-échappé à l'écriture
        esac
    done
    CRON_PARSE_EXTRA="${extra[*]}"
}


###############################################################################
# Fonction : Modifie une tâche cron rclone_homelab (supprime + recrée)
###############################################################################
cron_edit() {
    echo

    local existing
    existing=$(crontab -l 2>/dev/null || true)

    if [[ -z "$existing" ]]; then
        print_fancy --theme warning "Aucune tâche cron définie."
        return 0
    fi

    # Collecter les lignes rclone_homelab
    local -a cron_lines=()
    local line
    while IFS= read -r line; do
        _cron_is_managed_line "$line" && cron_lines+=("$line")
    done <<< "$existing"

    if [[ ${#cron_lines[@]} -eq 0 ]]; then
        print_fancy --theme warning "Aucune tâche rclone_homelab trouvée dans le crontab."
        return 0
    fi

    # Afficher les entrées numérotées
    print_fancy --theme info "Tâches Cron rclone_homelab :"
    echo
    local i
    for i in "${!cron_lines[@]}"; do
        printf "  [%d] %s\n" "$((i+1))" "${cron_lines[$i]}"
    done
    echo

    local choice
    read -e -rp "  Numéro de la tâche à modifier [1-${#cron_lines[@]}] ou q : " choice </dev/tty || return 0

    if [[ "$choice" == "q" ]]; then
        return 0
    fi

    if ! choice=$(_cron_valid_int "$choice" 1 "${#cron_lines[@]}"); then
        print_fancy --theme error "Choix invalide."
        return 1
    fi

    local old_line="${cron_lines[$((choice-1))]}"

    # Parser la ligne existante pour pré-remplir les défauts
    _cron_parse_line "$old_line"

    echo
    print_fancy --theme follow "Modification de la tâche sélectionnée."
    print_fancy --theme follow "Appuyez sur Entrée pour conserver la valeur actuelle, '-' pour supprimer une option."

    # Étape 1 : Jour de la semaine (avec défaut issu du parsing)
    local dow
    echo >/dev/tty
    print_fancy --theme info "Étape 1/7 — Jour de la semaine (actuel : $(_cron_dow_label "$CRON_PARSE_DOW"))" >/dev/tty
    echo >/dev/tty
    echo "  1) Tous les jours" >/dev/tty
    echo "  2) Lundi       3) Mardi       4) Mercredi" >/dev/tty
    echo "  5) Jeudi       6) Vendredi    7) Samedi" >/dev/tty
    echo "  8) Dimanche" >/dev/tty
    echo >/dev/tty

    # Entrée vide = valeur actuelle conservée telle quelle, même non standard (ex. 1-5)
    local dow_choice
    read -e -rp "  Choix [1-8, Entrée = conserver] : " dow_choice </dev/tty || return 1
    case "$dow_choice" in
        '') dow="$CRON_PARSE_DOW" ;;
        1) dow="*" ;; 2) dow="1" ;; 3) dow="2" ;; 4) dow="3" ;;
        5) dow="4" ;; 6) dow="5" ;; 7) dow="6" ;; 8) dow="0" ;;
        *)
            print_fancy --theme error "Choix invalide." >/dev/tty
            return 1
            ;;
    esac

    # Étape 2 : Heure (Entrée = champ actuel conservé tel quel, ex. */2)
    local hour
    echo >/dev/tty
    print_fancy --theme info "Étape 2/7 — Heure d'exécution (actuelle : $CRON_PARSE_HOUR)" >/dev/tty
    echo >/dev/tty
    read -e -rp "  Heure (0-23) [défaut: $CRON_PARSE_HOUR] : " hour </dev/tty || return 1
    if [[ -z "$hour" ]]; then
        hour="$CRON_PARSE_HOUR"
    elif ! hour=$(_cron_valid_int "$hour" 0 23); then
        print_fancy --theme error "Heure invalide." >/dev/tty
        return 1
    fi

    # Étape 3 : Minute
    local minute
    echo >/dev/tty
    print_fancy --theme info "Étape 3/7 — Minute d'exécution (actuelle : $CRON_PARSE_MINUTE)" >/dev/tty
    echo >/dev/tty
    read -e -rp "  Minute (0-59) [défaut: $CRON_PARSE_MINUTE] : " minute </dev/tty || return 1
    if [[ -z "$minute" ]]; then
        minute="$CRON_PARSE_MINUTE"
    elif ! minute=$(_cron_valid_int "$minute" 0 59); then
        print_fancy --theme error "Minute invalide." >/dev/tty
        return 1
    fi

    # Étape 4 : Dry-run
    local dry_run_flag="" dry_run_label="Non"
    local default_dr="n"
    [[ "$CRON_PARSE_DRY_RUN" == "Oui" ]] && default_dr="O"
    echo >/dev/tty
    print_fancy --theme info "Étape 4/7 — Mode simulation (actuel : $CRON_PARSE_DRY_RUN)" >/dev/tty
    echo >/dev/tty
    local reply_dr
    read -e -rp "  Activer --dry-run ? (O/n) [défaut: $default_dr] : " reply_dr </dev/tty || return 1
    reply_dr="${reply_dr:-$default_dr}"
    if [[ "$reply_dr" =~ ^[OoYy]$ ]]; then
        dry_run_flag="--dry-run"
        dry_run_label="Oui"
    fi

    # Étape 5 : Email
    local mailto_flag="" mailto_addr
    # Défaut = valeur de la tâche uniquement (pas MAIL_TO global : il s'ajouterait sans qu'on le demande)
    local default_mail="$CRON_PARSE_MAILTO"
    echo >/dev/tty
    print_fancy --theme info "Étape 5/7 — Rapport par email (actuel : ${default_mail:-(aucun)})" >/dev/tty
    echo >/dev/tty
    read -e -rp "  Adresse email [Entrée = conserver, - = supprimer] : " mailto_addr </dev/tty || return 1
    if [[ "$mailto_addr" == "-" ]]; then
        mailto_addr=""
    elif [[ -z "$mailto_addr" ]]; then
        mailto_addr="$default_mail"
    fi
    if [[ -n "$mailto_addr" ]]; then
        if [[ "$mailto_addr" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            mailto_flag="--mailto=$(_cron_escape_percent "$mailto_addr")"
        else
            print_fancy --theme warning "Format email invalide — ignoré." >/dev/tty
            mailto_addr=""
        fi
    fi

    # Étape 6 : Discord
    local discord_flag="" discord_url
    local default_discord="$CRON_PARSE_DISCORD"
    echo >/dev/tty
    print_fancy --theme info "Étape 6/7 — Notification Discord (actuelle : ${default_discord:-(aucune)})" >/dev/tty
    echo >/dev/tty
    read -e -rp "  URL Discord webhook [Entrée = conserver, - = supprimer] : " discord_url </dev/tty || return 1
    if [[ "$discord_url" == "-" ]]; then
        discord_url=""
    elif [[ -z "$discord_url" ]]; then
        discord_url="$default_discord"
    fi
    if [[ -n "$discord_url" ]]; then
        if [[ "$discord_url" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/ ]]; then
            discord_flag="--discord-url=$(_cron_escape_percent "$discord_url")"
        else
            print_fancy --theme warning "URL Discord invalide — ignorée." >/dev/tty
            discord_url=""
        fi
    fi

    # Étape 7 : Options extra
    local extra_opts
    echo >/dev/tty
    print_fancy --theme info "Étape 7/7 — Options rclone supplémentaires (actuelles : ${CRON_PARSE_EXTRA:-(aucune)})" >/dev/tty
    echo >/dev/tty
    read -e -rp "  Options rclone [Entrée = conserver, - = supprimer] : " extra_opts </dev/tty || return 1
    if [[ "$extra_opts" == "-" ]]; then
        extra_opts=""
    elif [[ -z "$extra_opts" ]]; then
        extra_opts="$CRON_PARSE_EXTRA"
    fi

    # Construction de la nouvelle ligne
    local cron_cmd="$SCRIPT_PATH --auto"
    [[ -n "$dry_run_flag" ]]  && cron_cmd+=" $dry_run_flag"
    [[ -n "$mailto_flag" ]]   && cron_cmd+=" $mailto_flag"
    [[ -n "$discord_flag" ]]  && cron_cmd+=" $discord_flag"
    [[ -n "$extra_opts" ]]    && cron_cmd+=" $(_cron_escape_percent "$extra_opts")"

    local cron_path="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    # Jour du mois et mois : conservés tels quels (non gérés par l'assistant)
    local new_line="${minute} ${hour} ${CRON_PARSE_DOM} ${CRON_PARSE_MONTH} ${dow} ${cron_path} ${cron_cmd} ${CRON_TAG}"

    # Résumé
    _cron_show_summary "$new_line" "$dow" "$hour" "$minute" \
        "$dry_run_label" "$mailto_addr" "$discord_url" "$extra_opts"

    # Confirmation
    echo
    local confirm
    read -e -rp "  Appliquer les modifications ? (O/n) : " confirm </dev/tty || confirm="n"
    if [[ -z "$confirm" || "$confirm" =~ ^[OoYy]$ ]]; then
        # Remplacer l'ancienne ligne à sa place (égalité exacte, pas de sous-chaîne)
        if _cron_replace_line "$old_line" "$new_line"; then
            print_fancy --theme success "Tâche Cron mise à jour avec succès !"
        else
            print_fancy --theme error "Échec de la mise à jour."
            return 1
        fi
    else
        print_fancy --theme warning "Modification annulée."
    fi
}


###############################################################################
# Fonction : Sous-menu de gestion des tâches cron
###############################################################################
cron_submenu() {
    local choice

    while true; do
        echo
        print_fancy --align center "═══════════════════════════════════════"
        print_fancy --align center "📅  GESTION DES TÂCHES CRON"
        print_fancy --align center "═══════════════════════════════════════"
        echo
        echo "  1) Ajouter une tâche Cron"
        echo "  2) Modifier une tâche Cron"
        echo "  3) Lister les tâches existantes"
        echo "  4) Supprimer une tâche Cron"
        echo "  q) Retour au menu principal"
        echo

        # Pas de terminal → retour au lieu de boucler sans fin
        read -e -rp "  Votre choix [1-4 ou q] : " choice </dev/tty || return 0

        case "$choice" in
            1) cron_add_wizard ;;
            2) cron_edit ;;
            3) cron_list ;;
            4) cron_remove ;;
            q) return 0 ;;
            *) print_fancy --theme error "Choix invalide." ;;
        esac
    done
}
