# === Déclarations globales pour print_fancy() === 
# Couleurs texte (FG) et fond (BG) intégrées et personnalisables
# Compatible AUSSI avec echo -e (ne pas oublier le -e et le ${RESET} à la fin)
# Exemple :
# echo -e "${YELLOW}⚠️  ${bin}${RESET} n'est pas installé."

# --- Couleurs texte par défaut ---
declare -A FG_COLORS=(
  [reset]=0 [default]=39
  [black]=30 [red]=31 [green]=32 [yellow]=33 [blue]=34 [magenta]=35 [cyan]=36
  [white]=37 [gray]=90 [light_red]=91 [light_green]=92 [light_yellow]=93
  [light_blue]=94 [light_magenta]=95 [light_cyan]=96 [bright_white]=97
  [black_pure]="256:0" [orange]="256:208"
)

# --- Couleurs fond par défaut ---
declare -A BG_COLORS=(
  [reset]=49 [default]=49
  [black]=40 [red]=41 [green]=42 [yellow]=43 [blue]=44 [magenta]=45 [cyan]=46
  [white]=47 [gray]=100 [light_red]=101 [light_green]=102 [light_yellow]=103
  [light_blue]=104 [light_magenta]=105 [light_cyan]=106 [bright_white]=107
  [black_pure]="256:0" [orange]="256:208"
)

for name in "${!FG_COLORS[@]}"; do
    code="${FG_COLORS[$name]}"
    if [[ "$code" == 256:* ]]; then
        # Couleur en mode 256 (ex: 256:208 → 208)
        idx="${code#256:}"
        printf -v "${name^^}" '\e[38;5;%sm' "$idx"
    else
        # Couleur standard (ex: 31, 32, 97…)
        printf -v "${name^^}" '\e[%sm' "$code"
    fi
done

for name in "${!BG_COLORS[@]}"; do
    code="${BG_COLORS[$name]}"
    if [[ "$code" == 256:* ]]; then
        idx="${code#256:}"
        printf -v "BG_${name^^}" '\e[48;5;%sm' "$idx"
    else
        printf -v "BG_${name^^}" '\e[%sm' "$code"
    fi
done

RESET='\e[0m'

# ===


###############################################################################
# Fonctions pour interpréter les couleurs (support ANSI / 256 / RGB)
###############################################################################
get_fg_color() {
    local c="$1"
    [[ -z "$c" ]] && return 0

    # Résolution via dictionnaire
    local code="${FG_COLORS[$c]:-$c}"

    if [[ "$code" =~ ^256: ]]; then
        printf "\033[38;5;%sm" "${code#256:}"
    elif [[ "$code" =~ ^rgb: ]]; then
        IFS=';' read -r r g b <<< "${code#rgb:}"
        printf "\033[38;2;%s;%s;%sm" "$r" "$g" "$b"
    elif [[ "$code" =~ ^[0-9]+$ ]]; then
        printf "\033[%sm" "$code"
    else
        # fallback
        printf "\033[39m"
    fi
}

get_bg_color() {
    local c="$1"
    [[ -z "$c" || "$c" == "none" || "$c" == "transparent" ]] && return 0

    local code="${BG_COLORS[$c]:-$c}"

    if [[ "$code" =~ ^256: ]]; then
        printf "\033[48;5;%sm" "${code#256:}"
    elif [[ "$code" =~ ^rgb: ]]; then
        IFS=';' read -r r g b <<< "${code#rgb:}"
        printf "\033[48;2;%s;%s;%sm" "$r" "$g" "$b"
    elif [[ "$code" =~ ^[0-9]+$ ]]; then
        printf "\033[%sm" "$code"
    else
        # fallback
        printf "\033[49m"
    fi
}


###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################

print_banner() {
    echo
    echo
    local RED="$(get_fg_color red)"
    local RESET="$(get_fg_color reset)"

    # Règle "tout sauf #"
    sed -E "s/([^#])/${RED}\1${RESET}/g" <<'EOF'
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::::::'######:::::'#######:::'########:::'######:::'##::::'##:::::'###:::::::::
::::::'##... ##:::'##.... ##::... ##..:::'##... ##:: ##:::: ##::::'## ##::::::::
:::::: ##:::..:::: ##:::: ##::::: ##::::: ##:::..::: ##:::: ##:::'##:. ##:::::::
:::::: ##::'####:: ##:::: ##::::: ##::::: ##:::::::: #########::'##:::. ##::::::
:::::: ##::: ##::: ##:::: ##::::: ##::::: ##:::::::: ##.... ##:: #########::::::
:::::: ##::: ##::: ##:::: ##::::: ##::::: ##::: ##:: ##:::: ##:: ##.... ##::::::
::::::. ######::::. #######:::::: ##:::::. ######::: ##:::: ##:: ##:::: ##::::::
:::::::......::::::.......:::::::..:::::::......::::..:::::..:::..:::::..:::::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
EOF
}


###############################################################################
# Fonction spinner
###############################################################################

spinner() {
    local pid=$1       # PID du processus à surveiller
    local delay=0.1    # vitesse du spinner
    local spinstr='|/-\'

    # Couleurs
    local ORANGE=$'\033[38;5;208m'
    local GREEN=$(get_fg_color "green")
    local RESET=$'\033[0m'

    tput civis  # cacher le curseur

    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r\033[2K[${ORANGE}%c${RESET}] Traitement du JOB en cours..." "${spinstr:i:1}"
            sleep $delay
        done
    done

    # Effacer entièrement la ligne avant d’afficher le message final
    printf "\r\033[2K[${GREEN}✔${RESET}] Terminé !\n"

    tput cnorm  # réafficher le curseur
}


###############################################################################
# Fonction Sortie avec code erreur
###############################################################################
die() {
    local code=$1
    shift
    echo
    print_fancy --align center --bg red --fg black_pure --style bold --highlight "Le script a rencontré une erreur fatale !"
    print_fancy --theme error "$*" >&2
    print_fancy --align center --bg red --fg black_pure --style bold --highlight "--- Veuillez corriger et/ou utiliser le menu interractif ---"
    echo
    exit "$code"
}


###############################################################################
# Fonction : fait défiler l'écran vers le bas (scroll down)
###############################################################################
scroll_down() {
    local lines
    # Nombre de lignes visibles du terminal
    lines=$(tput lines 2>/dev/null || echo 40)
    # On imprime juste ce nombre de retours à la ligne
    for ((i=0; i<lines; i++)); do
        echo
    done
}


###############################################################################
# Retire toutes les séquences ANSI CSI/OSC/SGR etc. (lecture depuis argument ou stdin)
###############################################################################
strip_ansi() {
    if [[ $# -gt 0 ]]; then
        printf '%s' "$1" \
            | sed -r "s/$(printf '\033')\\[[0-9;?]*[ -\\/]*[@-~]//g"
    else
        sed -r "s/$(printf '\033')\\[[0-9;?]*[ -\\/]*[@-~]//g"
    fi
}


###############################################################################
# Fonction : calcul de la largeur "visible" d'une chaîne (sans séquences ANSI)
###############################################################################
strwidth() {
    local str="${1:-}"
    # Supprimer toutes les séquences ANSI standards (CSI + SGR)
    str=$(printf '%s' "$str" | sed -r "s/$(printf '\033')\\[[0-9;?]*[ -\\/]*[@-~]//g")

    local width=0 char
    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        if [[ "$char" =~ [^[:ascii:]] ]]; then
            ((width+=2))
        else
            ((width+=1))
        fi
    done
    echo "$width"
}


###############################################################################
# Fonction alignement - décoration sur 1 ligne
###############################################################################
# ----
# print_fancy : Génère ou affiche du texte formaté avec couleurs, styles et
#               alignement. Sert autant pour de l’affichage direct que pour
#               construire des chaînes réutilisables (ex: menu, logs).
#
# Modes de fonctionnement :
#   - Par défaut : affiche directement le texte formaté avec un retour à la ligne
#   - Avec --raw : retourne uniquement la chaîne formatée (sans saut de ligne),
#                  utile pour injecter dans d’autres fonctions/variables
#
# Options :
#   --theme <success|error|warning|info|flash|follow>
#                          : Thème appliqué avec couleurs + emoji par défaut
#   --fg <code|var>        : Couleur du texte (ex: "red", "31", ou séquence ANSI)
#   --bg <code|var>        : Couleur de fond (ex: "blue", "44", ou séquence ANSI)
#   --fill <char>          : Caractère de remplissage (défaut: espace)
#   --align <center|left|right>
#                          : Alignement du texte (défaut: center si highlight)
#   --style <bold|italic|underline|combinaison>
#                          : Styles combinables appliqués au texte
#   --highlight            : Remplissage de la ligne entière avec `fill` + couleurs
#   --icon <votre_emoji>   : Ajoute une icône personnalisée en début de texte
#   -n                     : Supprime le retour à la ligne
#   --raw                  : Retourne la chaîne sans affichage (utile pour menus)
#   texte ... [OBLIGATOIRE]: Le texte à afficher (peut contenir des espaces)
#
# Exemples :
#   print_fancy --fg red --bg white --style "bold underline" "Alerte"
#   print_fancy --fg 42 --style italic "Succès en vert"
#   print_fancy --theme success "Backup terminé avec succès"
#   print_fancy --theme error --align right "Erreur critique détectée"
#   print_fancy --theme warning --highlight "Attention : espace disque faible"
#   print_fancy --theme info "Démarrage du service..."
#   print_fancy --theme info --icon "🚀" "Lancement en cours..."
#   msg=$(print_fancy --theme success --raw "Option colorisée")
#      print_fancy --fg cyan --style bold -n "Fichier d'origine :"
#      print_fancy --fg yellow "$main_conf"
#
# Exemple texte multi couleurs/styles
#   text=""
#   text+="${BOLD}Important:${RESET} "
#   text+="Voici un message ${UNDERLINE}souligné${RESET} et un emoji ⚡"
#   print_fancy --theme info "$text"

# ----

print_fancy() {
    local color="" bg="" fill=" " align="" text="" style="" highlight="" newline=true raw_mode=""
    local theme="" offset=0
    local icon="" prefix=""

    # Séquences ANSI
    local BOLD="\033[1m"
    local ITALIC="\033[3m"
    local UNDERLINE="\033[4m"
    local RESET="\033[0m"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fg) color="$2"; shift 2 ;;
            --bg) bg="$2"; shift 2 ;;
            --fill) fill="$2"; shift 2 ;;
            --align) align="$2"; shift 2 ;;
            --style) style="$2"; shift 2 ;;
            --highlight) highlight=1; shift ;;
            --offset) offset="$2"; shift 2 ;;
            --theme) theme="$2"; shift 2 ;;
            --icon) icon="$2 "; shift 2 ;;
            --pad) pad="$2"; shift 2 ;;
            -n) newline=false; shift ;;
            --raw) raw_mode=1; shift ;;
            *) text+="$1 "; shift ;;
        esac
    done
    text="${text%" "}"  # supprime espace final

    # Application du thème
    case "$theme" in
        success)    [[ -z "$icon" ]] && icon="✅  "; [[ -z "$color" ]] && color="green"; [[ -z "$style" ]] && style="bold" ;;
        error)      [[ -z "$icon" ]] && icon="❌  "; [[ -z "$color" ]] && color="red"; [[ -z "$style" ]] && style="bold" ;;
        warning)    [[ -z "$icon" ]] && icon="⚠️  "; [[ -z "$color" ]] && color="yellow"; [[ -z "$style" ]] && style="bold"; offset=-1 ;;
        debug_info) [[ -z "$icon" ]] && icon="ℹ️  "; [[ -z "$color" ]] && color="light_blue" ; [[ -z "$prefix" ]] && prefix="[DEBUG_INFO] " ;;

        info)       [[ -z "$icon" ]] && icon="ℹ️  " ;;
        ok)         [[ -z "$icon" ]] && icon="✅  " ;;
        flash)      [[ -z "$icon" ]] && icon="⚡  " ;;
        follow)     [[ -z "$icon" ]] && icon="👉  " ;;
    esac
    text="$icon$prefix$text"

    # Traduction des couleurs
    [[ "$color" =~ ^\\e ]] || color=$(get_fg_color "${color:-bright_white}")
    [[ "$bg" =~ ^\\e ]] || bg=$(get_bg_color "$bg")

    # Style
    local style_seq=""
    [[ "$style" =~ bold ]] && style_seq+="$BOLD"
    [[ "$style" =~ italic ]] && style_seq+="$ITALIC"
    [[ "$style" =~ underline ]] && style_seq+="$UNDERLINE"

    # Padding calculé sur largeur réelle
    local visible_len pad_left=0 pad_right=0
    visible_len=$(strwidth "$text")
    visible_len=$((visible_len + offset))

    case "$align" in
        center)
            local total_pad=$((TERM_WIDTH_DEFAULT - visible_len))
            pad_left=$(( (total_pad+1)/2 ))
            pad_right=$(( total_pad - pad_left ))
            ((pad_left<0)) && pad_left=0
            ((pad_right<0)) && pad_right=0
            ;;
        right)
            pad_left=$((TERM_WIDTH_DEFAULT - visible_len))
            ((pad_left<0)) && pad_left=0
            ;;
        left)
            pad_right=$((TERM_WIDTH_DEFAULT - visible_len))
            ((pad_right<0)) && pad_right=0
            ;;
    esac

    local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
    local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
    local output="${pad_left_str}${color}${bg}${style_seq}${text}${RESET}${pad_right_str}"

    # Highlight
    if [[ -n "$highlight" ]]; then
        local full_line
        # Ligne remplie entièrement avec le caractère de fond
        full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")

        # Application du bg sur toute la ligne
        full_line="${bg}${full_line}${RESET}"

        # Réinjection du texte coloré par-dessus au bon endroit
        full_line="${full_line:0:$((pad_left+len_escape "$bg"))}${color}${bg}${style_seq}${text}${RESET}${bg}${full_line:$((pad_left+visible_len+len_escape "$bg"))}"

        # Sortie finale
        output="$full_line${RESET}"
    fi

    if [[ -n "$raw_mode" ]]; then
        printf "%b" "$output"
    else
        $newline && printf "%b\n" "$output" || printf "%b" "$output"
    fi
}


###############################################################################
# Fonction : Valide et corrige des variables selon des valeurs autorisées
# Entrée : nom du tableau associatif à traiter
###############################################################################
self_validation_local_variables() {
    local -n var_array="$1"
    local key allowed default value valid

    for key in "${!var_array[@]}"; do
        # Split "allowed:default"
        IFS=":" read -r allowed default <<< "${var_array[$key]}"

        # Valeur actuelle
        value="${!key:-$default}"

        # Gestion spéciale booléen
        if [[ "$allowed" == "bool" ]]; then
            case "${value,,}" in
                1|true|yes|on) value=1 ;;
                0|false|no|off) value=0 ;;
                '') value="${default:-0}" ;;  # si vide
                *)
                    print_fancy --fg red --style bold \
                        "Donnée invalide pour $key : '$value'.\n" \
                        "- Valeurs attendues : true/false, 1/0, yes/no, on/off.\n" \
                        "-> Valeur par défaut appliquée : '$default'" \
                        "\n" \
                    value="${default:-0}"
                    ;;
            esac
            export "$key"="$value"
            continue
        fi

        # Liste de valeurs ou intervalle (allowed)
        IFS="|" read -ra allowed_arr <<<"$allowed"
        valid=false

        for v in "${allowed_arr[@]}"; do
            if [[ "$v" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # Cas intervalle numérique : 1-5
                min=${BASH_REMATCH[1]}
                max=${BASH_REMATCH[2]}
                if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
                    valid=true
                    break
                fi
            elif [[ "$v" =~ ^[0-9]+$ ]]; then
                # Cas valeur exacte numérique
                if [[ "$value" == "$v" ]]; then
                    valid=true
                    break
                fi
            else
                # Cas valeur littérale (y compris vide '')
                [[ "$v" == "''" ]] && v=""
                if [[ "$value" == "$v" ]]; then
                    valid=true
                    break
                fi
            fi
        done

        if [[ "$valid" == false ]]; then
            print_fancy --fg red --style bold \
                "Donnée invalide pour $key : '$value'.\n" \
                "- Valeurs attendues : ${allowed//|/, }.\n" \
                "-> Valeur par défaut appliquée : '$default'" \
                "\n"
            export "$key"="$default"
        else
            export "$key"="$value"
        fi
    done
}


###############################################################################
# Fonction : Contrôle et validation des variables avec menu
# Entrée : nom du tableau associatif
###############################################################################
menu_validation_local_variables() {
    local -n var_array="$1"

    if ! print_table_vars_invalid "$1"; then
        # Problème
        echo
        print_fancy --theme "error" "Configuration invalide. Vérifiez les variables (locales) ❌"
        echo
        echo
        print_fancy --fg green "-------------------------------------------"
        print_fancy --fg green --style bold "  Aide au débogage : Configuration locale"
        print_fancy --fg green "-------------------------------------------"
        echo
        echo -e "${UNDERLINE}Voulez-vous :${RESET}"
        echo
        echo -e "[1] Appliquer la valeur ${BOLD}Défaut${RESET} automatiquement."
        echo -e "${ITALIC}    => N'est valable que pour cette session.${RESET}"
        echo -e "[2] Editer la configuration locale pour ${UNDERLINE}corriger${RESET}."
        echo -e "[3] Quitter."
        echo

        read -e -rp "Votre choix [1-3] : " choice
        echo

        case "$choice" in
            1)
                echo
                echo "👉  Application de la correction automatique."
                echo
                self_validation_local_variables "$1"
                ;;
            2)
                echo
                if ! mini_edit_local_config; then
                    print_fancy --bg yellow --fg red --highlight "⚠️  Le mystère s’épaissit... où se trouve le soucis ?!"
                    print_fancy --bg yellow --fg red --highlight "Aucun fichier disponible, retour au menu principal."
                fi
                menu_validation_local_variables  "$1" # retour au menu principal après édition pour validation
                ;;
            3)
                echo
                die 99 "Interruption par l’utilisateur"
                echo
                ;;
            *)
                echo "❌  Choix invalide."
                sleep 1
                menu_validation_local_variables "$1"
                ;;
        esac
        return 1
    fi
    return 0
    # Pas de problèmes
}


###############################################################################
# Fonction : Affiche un contenu (avec ANSI) correctement aligné dans une colonne
# Arguments :
#   $1 = contenu (ANSI autorisé)
#   $2 = largeur visible de la colonne
###############################################################################
print_cell() {
    local content="$1" col_width="$2"
    local vis_len padding clean

    # Calcul largeur visible
    clean=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
    vis_len=$(strwidth "$clean")
    padding=$((col_width - vis_len))
    (( padding<0 )) && padding=0

    # Ajouter padding avant RESET final
    if [[ "$content" =~ $'\033\[0m$' ]]; then
        local body="${content%$'\033'[0m}" reset=$'\033[0m'
        printf "%s%*s%s" "$body" "$padding" "" "$reset"
    else
        printf "%s%*s" "$content" "$padding" ""
    fi
}


###############################################################################
# Fonction : Bordures tableau
###############################################################################
draw_border() {
    printf "┌%s┐\n" \
        "$(printf '─%.0s' $(seq 1 $((w1+2))))┬$(printf '─%.0s' $(seq 1 $((w2+2))))┬$(printf '─%.0s' $(seq 1 $((w3+2))))┬$(printf '─%.0s' $(seq 1 $((w4+2))))"
}
draw_separator() {
    printf "├%s┤\n" \
        "$(printf '─%.0s' $(seq 1 $((w1+2))))┼$(printf '─%.0s' $(seq 1 $((w2+2))))┼$(printf '─%.0s' $(seq 1 $((w3+2))))┼$(printf '─%.0s' $(seq 1 $((w4+2))))"
}
draw_bottom() {
    printf "└%s┘\n" \
        "$(printf '─%.0s' $(seq 1 $((w1+2))))┴$(printf '─%.0s' $(seq 1 $((w2+2))))┴$(printf '─%.0s' $(seq 1 $((w3+2))))┴$(printf '─%.0s' $(seq 1 $((w4+2))))"
}


###############################################################################
# Fonction : Affichage d'un tableau formaté à partir d'une liste de lignes
# Chaque ligne doit être un tableau de colonnes : c1¤c2¤c3¤c4¤valid_flag
# valid_flag est optionnel et sert à colorer la valeur
###############################################################################
print_table() {
    local -n lines=$1
    local max_length="${2:-80}"

    local headers=("Variable" "Autorisé" "Défaut" "Valeur")
    local w1=0 w2=0 w3=0 w4=0

    # Calcul des largeurs
    for header in "${headers[@]}"; do
        local len=$(strwidth "$header")
        case "$header" in
            Variable) (( len > w1 )) && w1=$len ;;
            Autorisé) (( len > w2 )) && w2=$len ;;
            Défaut)   (( len > w3 )) && w3=$len ;;
            Valeur)   (( len > w4 )) && w4=$len ;;
        esac
    done

    for row in "${lines[@]}"; do
        IFS="¤" read -r c1 c2 c3 c4 valid_flag <<<"$row"
        (( $(strwidth "$c1") > w1 )) && w1=$(strwidth "$c1")
        (( $(strwidth "$c2") > w2 )) && w2=$(strwidth "$c2")
        (( $(strwidth "$c3") > w3 )) && w3=$(strwidth "$c3")
        (( $(strwidth "$c4") > w4 )) && w4=$(strwidth "$c4")
    done

    # Ajuster si dépasse max_length
    local total_width=$(( w1 + w2 + w3 + w4 + 13 ))
    if (( total_width > max_length )); then
        local excess=$(( total_width - max_length ))
        local cut=$(( (excess + 3) / 4 ))
        w1=$(( w1 - cut > 5 ? w1 - cut : 5 ))
        w2=$(( w2 - cut > 5 ? w2 - cut : 5 ))
        w3=$(( w3 - cut > 5 ? w3 - cut : 5 ))
        w4=$(( w4 - cut > 5 ? w4 - cut : 5 ))
    fi

    # Bordure supérieure
    draw_border

    # En-tête
    printf "│ "
    print_cell "$(print_fancy --style bold --raw "${headers[0]}")" $w1
    printf " │ "
    print_cell "$(print_fancy --style bold --raw "${headers[1]}")" $w2
    printf " │ "
    print_cell "$(print_fancy --style bold --raw "${headers[2]}")" $w3
    printf " │ "
    print_cell "$(print_fancy --style bold --raw "${headers[3]}")" $w4
    printf " │\n"

    draw_separator

    # Corps
    for row in "${lines[@]}"; do
        IFS="¤" read -r c1 c2 c3 c4 valid_flag <<<"$row"
        var_cell=$(print_fancy --style bold --raw "$c1")
        auth_cell=$(print_fancy --style italic --raw "$c2")
        def_cell="$c3"
        if [[ "$valid_flag" == "false" ]]; then
            val_cell=$(print_fancy --fg red --raw "$c4")
        else
            val_cell=$(print_fancy --fg green --raw "$c4")
        fi
        printf "│ "
        print_cell "$var_cell" $w1
        printf " │ "
        print_cell "$auth_cell" $w2
        printf " │ "
        print_cell "$def_cell" $w3
        printf " │ "
        print_cell "$val_cell" $w4
        printf " │\n"
    done

    draw_bottom
}


###############################################################################
# Fonction : calculer la valeur affichée "Autorisé" et si la valeur est valide
# Entrée  : var_name, allowed, default
# Sortie  : display_allowed, value, valid
# Sortie  : COMPUTE_DISPLAY_ALLOWED, COMPUTE_VALUE, COMPUTE_VALID
###############################################################################
compute_var_status() {
    local var_name=$1
    local allowed=$2
    local default=$3

    local value="${!var_name:-$default}"
    local valid=true
    local display_allowed=""

    if [[ "$allowed" == "bool" ]]; then
        display_allowed="false|true"
        [[ "$value" =~ ^(0|1|true|false|yes|no|on|off)$ ]] || valid=false
    elif [[ "$allowed" =~ ^[0-9]+-[0-9]+$ ]]; then
        display_allowed="$allowed"
        IFS="-" read -r min max <<< "$allowed"
        (( value < min || value > max )) && valid=false
    elif [[ -z "$allowed" || "$allowed" == "any" || "$allowed" == "''" ]]; then
        display_allowed="*"
        valid=true
    else
        IFS="|" read -ra allowed_arr <<<"$allowed"
        valid=false
        display_allowed=""
        for v in "${allowed_arr[@]}"; do
            [[ "$v" == "''" ]] && v=""
            [[ -z "$display_allowed" ]] && display_allowed="$v" || display_allowed+="|$v"
            [[ "$value" == "$v" ]] && valid=true
        done
        [[ -z "$value" && (-z "$allowed" || "$allowed" == "any" || "$allowed" == "''") ]] && valid=true
    fi

    COMPUTE_VALUE="$value"
    COMPUTE_DISPLAY_ALLOWED="$display_allowed"
    COMPUTE_VALID="$valid"
}



###############################################################################
# Fonction : Affiche un tableau des variables invalides seulement
# Entrée : nom du tableau associatif
###############################################################################
print_table_vars_invalid() {
    local -n var_array="$1"
    local invalid_rows=()
    local key allowed default
    local has_invalid=false

    for key in "${!var_array[@]}"; do
        IFS=":" read -r allowed default <<< "${var_array[$key]}"
        compute_var_status "$key" "$allowed" "$default"

        if [[ "$COMPUTE_VALID" == "false" ]]; then
            invalid_rows+=("$key¤$COMPUTE_DISPLAY_ALLOWED¤$default¤$COMPUTE_VALUE¤false")
            has_invalid=true
        fi
    done

    if [[ "$has_invalid" == "true" ]]; then
        echo
        print_fancy --theme "warning" "Variables invalides :"
        print_table invalid_rows
        return 1
    fi

    return 0
}


###############################################################################
# Fonction : Affiche un tableau de valeurs passé en arguments
# Entrée : nom du tableau associatif
###############################################################################
print_table_vars() {
    local -n var_array="$1"   # référence au tableau associatif
    local rows=()
    local key allowed default

    for key in "${!var_array[@]}"; do
        # Split "allowed:default"
        IFS=":" read -r allowed default <<< "${var_array[$key]}"

        compute_var_status "$key" "$allowed" "$default"

        rows+=("$key¤$COMPUTE_DISPLAY_ALLOWED¤$default¤$COMPUTE_VALUE¤$COMPUTE_VALID")
    done

    print_table rows
}

# L'ARGUMENT dans le code d'appel de la fonciton PRIME sur la variable global
#
# Exemple :
#
# fonction_fictive soft
#
#
# fonction_fictive () {
# local LAUNCH_MODE="$1:${LAUNCH_MODE:-hard}" # <== argument : variable:<defaut>
#    if ! [condition_blablabla] then
#        case "$LAUNCH_MODE" in
#            soft)
#                return 1
#                ;;
#            verbose)
#                fonction_doublement_fictive
#                ;;
#            hard)
#                die 999 "❌  J'arrête le script et je meurs avec fonction die"
#                ;;
#            *)
#                echo "❌  Mode inconnu '$LAUNCH_MODE' dans fonction_fictive"
#                return 2
#                ;;
#        esac
#    fi
#    return 0
# }
# Explications code de sortie :
# return 0   -> Quand la condition "vrai"
# Case       -> Quand la condition retourne "faux" selon les cas précisés...
# Attention au signe "!" devant la condition qui inverse le sens "vrai/faux" 


###############################################################################
# Fonction : display_msg
#
# Description :
#   Centralise l'affichage des messages selon le DISPLAY_MODE courant.
#   Compatible avec print_fancy (n'importe quel nombre d'arguments).
#
#   Le premier argument indique le(s) mode(s) d'affichage où le message
#   doit apparaître. Plusieurs modes peuvent être combinés avec "|".
#
# Modes supportés :
#   - "soft"    → affiché uniquement si DISPLAY_MODE=soft
#   - "verbose" → affiché uniquement si DISPLAY_MODE=verbose
#   - "hard"    → affiché uniquement si DISPLAY_MODE=hard
#
#   Si plusieurs modes sont passés (ex: "verbose|hard"), le message
#   s'affiche si DISPLAY_MODE correspond à l'un d'eux.
#
# Comportement par défaut si aucun message fourni :
#   - soft    → message vide (aucun affichage)
#   - verbose → "[caller] (no message provided)"
#   - hard    → "[caller] (no message provided)"
#
# Syntaxe :
#   display_msg <modes> <...arguments de print_fancy>
#
# Exemples :
#   display_msg "soft" "✔ Local config activée"
#   display_msg "verbose" --theme "info" --align "center" "CONFIGURATION LOCALE"
#   display_msg "verbose|hard" --theme "danger" "Erreur critique"
###############################################################################
display_msg() {
    local modes="$1"
    shift

    if [[ -z "$modes" ]]; then
        echo "[display_msg] ERREUR : au moins un mode obligatoire (soft|verbose|hard)"
        return 1
    fi

    local caller="${FUNCNAME[1]:-main}"
    local display_mode="${DISPLAY_MODE:-soft}"

    # Aucun message fourni
    if [[ "$#" -eq 0 ]]; then
        case "$modes" in
            *soft*) return 0 ;;  # soft = silencieux par défaut
            *) set -- "[$caller] (no message provided)" ;;
        esac
    fi

    # Vérifie si DISPLAY_MODE correspond à un des modes demandés
    IFS="|" read -ra wanted <<< "$modes"
    for mode in "${wanted[@]}"; do
        case "$mode" in
            soft|verbose|hard)
                if [[ "$display_mode" == "$mode" ]]; then
                    print_fancy "$@"
                    return 0
                fi
                ;;
            *)
                echo "[display_msg] ERREUR : mode inconnu '$mode' (soft|verbose|hard)"
                return 1
                ;;
        esac
    done
}
