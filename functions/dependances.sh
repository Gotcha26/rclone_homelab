#!/usr/bin/env bash


###############################################################################
# Fonction : Affiche le logo ASCII GOTCHA (uniquement en mode manuel)
###############################################################################

print_logo() {
    echo
    echo
    local RED="$(get_fg_color red)"
    local RESET="$(get_fg_color reset)"

    # Règle "tout sauf #"
    sed -E "s/([^#])/${RED}\1${RESET}/g" <<'EOF'
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::'######:::::'#######:::'########:::'######:::'##::::'##:::::'###:::::::::
:::::'##... ##:::'##.... ##::... ##..:::'##... ##:: ##:::: ##::::'## ##::::::::
::::: ##:::..:::: ##:::: ##::::: ##::::: ##:::..::: ##:::: ##:::'##:. ##:::::::
::::: ##::'####:: ##:::: ##::::: ##::::: ##:::::::: #########::'##:::. ##::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##:::::::: ##.... ##:: #########::::::
::::: ##::: ##::: ##:::: ##::::: ##::::: ##::: ##:: ##:::: ##:: ##.... ##::::::
:::::. ######::::. #######:::::: ##:::::. ######::: ##:::: ##:: ##:::: ##::::::
::::::......::::::.......:::::::..:::::::......::::..:::::..:::..:::::..:::::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
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

    if [[ "$c" =~ ^ansi: ]]; then
        printf "\033[%sm" "${c#ansi:}"
    elif [[ "$c" =~ ^256: ]]; then
        printf "\033[38;5;%sm" "${c#256:}"
    elif [[ "$c" =~ ^rgb: ]]; then
        IFS=';' read -r r g b <<< "${c#rgb:}"
        printf "\033[38;2;%s;%s;%sm" "$r" "$g" "$b"
    else
        # fallback : nom de couleur classique
        printf "\033[%sm" "${FG_COLORS[$c]:-39}"
    fi
}

get_bg_color() {
    local c="$1"
    [[ -z "$c" || "$c" == "none" || "$c" == "transparent" ]] && return 0

    if [[ "$c" =~ ^ansi: ]]; then
        printf "\033[%sm" "${c#ansi:}"
    elif [[ "$c" =~ ^256: ]]; then
        printf "\033[48;5;%sm" "${c#256:}"
    elif [[ "$c" =~ ^rgb: ]]; then
        IFS=';' read -r r g b <<< "${c#rgb:}"
        printf "\033[48;2;%s;%s;%sm" "$r" "$g" "$b"
    else
        # fallback : nom de couleur classique
        printf "\033[%sm" "${BG_COLORS[$c]:-49}"
    fi
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
#   text=""
#   text+="${BOLD}Important:${RESET} "
#   text+="Voici un message ${UNDERLINE}souligné${RESET} et un emoji ⚡"
#   print_fancy --theme info "$text"

# ----

print_fancy() {
    local color=""
    local bg=""
    local fill=" "
    local align=""
    local text=""
    local style=""
    local highlight=""
    local offset=0
    local theme=""
    local icon=""
    local newline=true
    local raw_mode=""

    # Séquences ANSI
    local BOLD="\033[1m"
    local ITALIC="\033[3m"
    local UNDERLINE="\033[4m"
    local RESET="\033[0m"

    # Lecture des arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fg)       color="$2"; shift 2 ;;
            --bg)       bg="$2"; shift 2 ;;
            --fill)     fill="$2"; shift 2 ;;
            --align)    align="$2"; shift 2 ;;
            --style)    style="$2"; shift 2 ;;
            --highlight) highlight=1; shift ;;
            --offset)   offset="$2"; shift 2 ;;
            --theme)    theme="$2"; shift 2 ;;
            --icon)     icon="$2 "; shift 2 ;;
            -n)         newline=false; shift ;;
            --raw)      raw_mode=1; shift ;;
            *)          text="$1"; shift; break ;;
        esac
    done

    while [[ $# -gt 0 ]]; do text+=" $1"; shift; done
    [[ -z "$text" ]] && { echo "$MSG_PRINT_FANCY_EMPTY" >&2; return 1; }

    # Application du thème (icône / couleur / style par défaut)
    case "$theme" in
        success) [[ -z "$icon" ]] && icon="✅  "; [[ -z "$color" ]] && color="green"; [[ -z "$style" ]] && style="bold" ;;
        error)   [[ -z "$icon" ]] && icon="❌  "; [[ -z "$color" ]] && color="red"; [[ -z "$style" ]] && style="bold" ;;
        warning) [[ -z "$icon" ]] && icon="⚠️  "; [[ -z "$color" ]] && color="yellow"; [[ -z "$style" ]] && style="bold"; offset=-1 ;;
        info)    [[ -z "$icon" ]] && icon="ℹ️  "; [[ -z "$color" ]] && color="light_blue" ;;
        flash)   [[ -z "$icon" ]] && icon="⚡  " ;;
        follow)  [[ -z "$icon" ]] && icon="👉  " ;;
    esac

    # Ajout de l’icône si définie
    text="$icon$text"

    # --- Traduction des couleurs (sauf si séquence ANSI déjà fournie) ---

    # Couleur du texte
    if [[ "$color" =~ ^\\e ]]; then
        :  # laisse la séquence telle quelle
    else
        color=$(get_fg_color "${color:-white}")
    fi
    # Couleur du fond
    if [[ "$bg" =~ ^\\e ]]; then
        :  # rien à faire, la séquence est déjà complète
    else
        bg=$(get_bg_color "$bg")
    fi

    local style_seq=""
    [[ "$style" =~ bold ]]      && style_seq+="$BOLD"
    [[ "$style" =~ italic ]]    && style_seq+="$ITALIC"
    [[ "$style" =~ underline ]] && style_seq+="$UNDERLINE"

    # Calcul padding
    local visible_len=${#text}
    local pad_left=0
    local pad_right=0

    # Compensation manuelle pour les emojis "glitchés"
    visible_len=$((visible_len + offset))
    
    case "$align" in
        center)
            local total_pad=$((TERM_WIDTH_DEFAULT - visible_len))
            pad_left=$(( (total_pad+1)/2 ))
            pad_right=$(( total_pad - pad_left ))
            ;;
        right)
            pad_left=$((TERM_WIDTH_DEFAULT - visible_len - 1))
            (( pad_left < 0 )) && pad_left=0
            ;;
        left)
            pad_right=$((TERM_WIDTH_DEFAULT - visible_len))
            ;;
    esac

    # Génération du texte final
    local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
    local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
    local output="${pad_left_str}${color}${bg}${style_seq}${text}${RESET}${pad_right_str}"

    # Highlight sur toute la ligne
    if [[ -n "$highlight" ]]; then
        # Ligne complète remplie avec le fill
        local full_line
        full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
        # Insérer le texte avec style et couleur
        full_line="${full_line:0:pad_left}${color}${bg}${style_seq}${text}${RESET}${bg}${full_line:$((pad_left + visible_len))}"
        # Appliquer la couleur de fond sur toute la ligne
        output="${bg}${full_line}${RESET}"
    else
        # Version classique sans highlight
        local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
        local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
        output="${pad_left_str}${color}${bg}${style_seq}${text}${RESET}${pad_right_str}"
    fi

     # Mode debug : afficher symboles début/fin ligne
    if [[ "$DEBUG_MODE" == true ]]; then
        output="|${output}|"
    fi

    # Affichage ou retour brut, ligne contnue ou pas
    if [[ -n "$raw_mode" ]]; then
        printf "%b" "$output"   # toujours interpréter les séquences ANSI
    else
        $newline && printf "%b\n" "$output" || printf "%b" "$output"
    fi
}


###############################################################################
# Fonction Sortie avec code erreur
###############################################################################
die() {
    local code=$1
    shift
    print_fancy --theme "error" "$*" >&2
    echo
    exit "$code"
}


###############################################################################
# Fonction : Valide des variables selon des valeurs autorisées
# Utilisation :
#   VARS_TO_VALIDATE=(
#       "MODE:hard|soft|verbose:hard"
#       "OPTIONAL_CONF:file1|file2|:''"
#       "RETRY_COUNT:0-5:3"
#       "ENABLE_FEATURE:bool:0"
#   )
#   validate_vars VARS_TO_VALIDATE[@]
###############################################################################
validate_vars() {
    local -n var_array=$1   # Passage du nom de l'array en référence

    for entry in "${var_array[@]}"; do
        IFS=":" read -r var_name allowed default <<<"$entry"

        # Valeur actuelle de la variable
        local value="${!var_name:-$default}"

        # Gestion spéciale booléen
        if [[ "$allowed" == "bool" ]]; then
            case "${value,,}" in
                1|true|yes|on) value=1 ;;
                0|false|no|off) value=0 ;;
                '') value="${default:-0}" ;;  # si vide
                *)
                    print_fancy --theme "error" --align "center" \
                        "Valeur invalide pour $var_name : '$value'.\n"\
                        "Valeurs attendues : true/false, 1/0, yes/no, on/off.\n"\
                        "Valeur par défaut appliquée : '$default'"
                    value="${default:-0}"
                    ;;
            esac
            export "$var_name"="$value"
            continue
        fi

        # Conversion allowed en tableau
        IFS="|" read -ra allowed_arr <<<"$allowed"
        local valid=false

        for v in "${allowed_arr[@]}"; do
            # Cas intervalle numérique : 1-5
            if [[ "$v" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local min=${BASH_REMATCH[1]}
                local max=${BASH_REMATCH[2]}
                if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
                    valid=true
                    break
                fi
            # Cas valeur exacte numérique
            elif [[ "$v" =~ ^[0-9]+$ ]]; then
                if [[ "$value" == "$v" ]]; then
                    valid=true
                    break
                fi
            # Cas valeur littérale (y compris vide)
            else
                # Si vide indiqué par '', on le transforme en chaîne vide
                [[ "$v" == "''" ]] && v=""
                if [[ "$value" == "$v" ]]; then
                    valid=true
                    break
                fi
            fi
        done

        if [[ "$valid" == false ]]; then
            print_fancy --theme "error" --align "center" \
                "Valeur invalide pour $var_name : '$value'.\n"\
                "Valeurs attendues : ${allowed//|/, }.\n"\
                "Valeur par défaut appliquée : '$default'"
            export "$var_name"="$default"
        else
            export "$var_name"="$value"
        fi
    done
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
# Fonction : Rendu en tableau formaté
###############################################################################
print_vars_table() {
    local -n var_array=$1
    local rows=()
    local w1=0 w2=0 w3=0 w4=0
    local max_length="${max_length:-80}"

    # Préparer les lignes et calcul des largeurs sur texte brut
    for entry in "${var_array[@]}"; do
        IFS=":" read -r var_name allowed default <<<"$entry"
        local value="${!var_name:-$default}"
        local valid=true

        # Validation rapide
        if [[ "$allowed" == "bool" ]]; then
            [[ "$value" =~ ^(0|1|true|false)$ ]] || valid=false
        else
            IFS="|" read -ra allowed_arr <<<"$allowed"
            valid=false
            for v in "${allowed_arr[@]}"; do
                [[ "$v" == "''" ]] && v=""
                [[ "$value" == "$v" ]] && valid=true && break
            done
        fi

        rows+=("$var_name|$allowed|$default|$value|$valid")

        # Largeurs basées sur texte brut
        (( ${#var_name} > w1 )) && w1=${#var_name}
        (( ${#allowed}  > w2 )) && w2=${#allowed}
        (( ${#default}  > w3 )) && w3=${#default}
        (( ${#value}    > w4 )) && w4=${#value}
    done

    # Ajuster si dépasse max_length
    local total_width=$(( w1 + w2 + w3 + w4 + 13 )) # bordures + espaces
    if (( total_width > max_length )); then
        local excess=$(( total_width - max_length ))
        local cut=$(( (excess + 3) / 4 ))
        w1=$(( w1 - cut > 5 ? w1 - cut : 5 ))
        w2=$(( w2 - cut > 5 ? w2 - cut : 5 ))
        w3=$(( w3 - cut > 5 ? w3 - cut : 5 ))
        w4=$(( w4 - cut > 5 ? w4 - cut : 5 ))
    fi

    # Bordures
    draw_border() {
        local a=$1 b=$2 c=$3 d=$4
        printf "┌%s┐\n" \
            "$(printf '─%.0s' $(seq 1 $((a+2))))┬$(printf '─%.0s' $(seq 1 $((b+2))))┬$(printf '─%.0s' $(seq 1 $((c+2))))┬$(printf '─%.0s' $(seq 1 $((d+2))))"
    }
    draw_separator() {
        local a=$1 b=$2 c=$3 d=$4
        printf "├%s┤\n" \
            "$(printf '─%.0s' $(seq 1 $((a+2))))┼$(printf '─%.0s' $(seq 1 $((b+2))))┼$(printf '─%.0s' $(seq 1 $((c+2))))┼$(printf '─%.0s' $(seq 1 $((d+2))))"
    }
    draw_bottom() {
        local a=$1 b=$2 c=$3 d=$4
        printf "└%s┘\n" \
            "$(printf '─%.0s' $(seq 1 $((a+2))))┴$(printf '─%.0s' $(seq 1 $((b+2))))┴$(printf '─%.0s' $(seq 1 $((c+2))))┴$(printf '─%.0s' $(seq 1 $((d+2))))"
    }

    # Affichage
    draw_border $w1 $w2 $w3 $w4

    # En-tête en gras
    printf "│ %s │ %s │ %s │ %s │\n" \
        "$(print_fancy --style bold --raw --offset 0 "$(printf "%-*s" $w1 "Variable")")" \
        "$(print_fancy --style bold --raw --offset 1 "$(printf "%-*s" $w2 "Autorisé")")" \
        "$(print_fancy --style bold --raw --offset 0 "$(printf "%-*s" $w3 "Défaut")")" \
        "$(print_fancy --style bold --raw --offset 0 "$(printf "%-*s" $w4 "Valeur")")"

    draw_separator $w1 $w2 $w3 $w4

    # Corps : italique sur colonnes sauf Valeur
    for row in "${rows[@]}"; do
        IFS="|" read -r c1 c2 c3 c4 valid_flag <<<"$row"

        var_cell=$(print_fancy --style italic --raw "$(printf "%-*s" $w1 "$c1")")
        auth_cell=$(print_fancy --style italic --raw "$(printf "%-*s" $w2 "$c2")")
        def_cell=$(print_fancy --style italic --raw "$(printf "%-*s" $w3 "$c3")")
        val_cell=$(printf "%-*s" $w4 "$c4")
        [[ "$valid_flag" == "false" ]] && val_cell=$(print_fancy --fg red --raw "$val_cell")

        printf "│ %b │ %b │ %b │ %b │\n" "$var_cell" "$auth_cell" "$def_cell" "$val_cell"
    done

    draw_bottom $w1 $w2 $w3 $w4
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
