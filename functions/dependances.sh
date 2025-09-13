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


###############################################################################
# Fonctions additionnels pour print_fancy()
#
# Ajouter des couleurs personnalisées pour print_fancy()
# Déclaration dans config.local.sh
# MY_FG_COLOR=$'\e[38;5;208m'   # orange par exemple pour le texte
# MY_BG_COLOR=$'\e[48;5;236m'   # fond gris foncé
#
# Explications :
# 38;5;<n> → couleur de texte en mode 256 couleurs
# 48;5;<n> → couleur de fond en mode 256 couleurs
# <n> est l’indice de la couleur dans la palette 256
#
# Utilisation
# print_fancy --fg "$MY_ORANGE" "Texte orange"
# print_fancy --bg "$MY_BG_GRAY" "Texte sur fond gris"
# print_fancy --fg "$MY_ORANGE" --bg "$MY_BG_GRAY" "Texte orange sur fond gris"
###############################################################################

# --- Déclarations globales pour print_fancy ---
# + ajoute 'reset' (et 'default' si tu veux) aux maps
declare -A FG_COLORS=(
  [reset]=0 [default]=39
  [black]=30 [black_pure]=$'\e[38;5;0m' [red]=31 [green]=32 [yellow]=33 [blue]=34 [magenta]=35 [cyan]=36 [white]=37
  [gray]=90 [light_red]=91 [light_green]=92 [light_yellow]=93 [light_blue]=94 [light_magenta]=95 [light_cyan]=96 [bright_white]=97
  [orange]=$'\e[38;5;208m'
)
declare -A BG_COLORS=(
  [reset]=49 [default]=49
  [black]=40 [black_pure]=$'\e[48;5;0m' [red]=41 [green]=42 [yellow]=43 [blue]=44 [magenta]=45 [cyan]=46 [white]=47
  [gray]=100 [light_red]=101 [light_green]=102 [light_yellow]=103 [light_blue]=104 [light_magenta]=105 [light_cyan]=106 [bright_white]=107
  [orange]=$'\e[48;5;208m'
)

get_fg_color() {
  local c="$1"
  [[ -z "$c" ]] && return 0
  if [[ -n "${FG_COLORS[$c]+_}" ]]; then
    # reset=0 -> \033[0m ; default=39 -> \033[39m ; etc.
    printf "\033[%sm" "${FG_COLORS[$c]}"
  else
    # codes bruts (ex: $'\e[38;5;208m')
    printf "%s" "$c"
  fi
}

get_bg_color() {
  local c="$1"
  [[ -z "$c" || "$c" == "none" || "$c" == "transparent" ]] && return 0
  if [[ -n "${BG_COLORS[$c]+_}" ]]; then
    printf "\033[%sm" "${BG_COLORS[$c]}"
  else
    printf "%s" "$c"
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
# ----

print_fancy() {
    local color=""
    local bg=""
    local fill=" "
    local align=""
    local text=""
    local style=""
    local highlight=""
    local theme=""
    local icon=""
    local newline=true
    local raw_mode=""

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
            --highlight) highlight="1"; shift ;;
            --theme)    theme="$2"; shift 2 ;;
            --icon)     icon="$2 "; shift 2 ;;
            -n)         newline=false; shift ;;
            --raw)      raw_mode="1"; shift ;;
            *)          text="$1"; shift; break ;;
        esac
    done

    while [[ $# -gt 0 ]]; do text+=" $1"; shift; done
    [[ -z "$text" ]] && { echo "$MSG_PRINT_FANCY_EMPTY" >&2; return 1; }

    # Application du thème (icône / couleur / style par défaut)
    case "$theme" in
        success) [[ -z "$icon" ]] && icon="✅  " ; [[ -z "$color" ]] && color="green"; [[ -z "$style" ]] && style="bold" ;;
        error)   [[ -z "$icon" ]] && icon="❌  " ; [[ -z "$color" ]] && color="red"; [[ -z "$style" ]] && style="bold" ;;
        warning) [[ -z "$icon" ]] && icon="⚠️  " ; [[ -z "$color" ]] && color="yellow"; [[ -z "$style" ]] && style="bold" ;;
        info)    [[ -z "$icon" ]] && icon="ℹ️  " ; [[ -z "$color" ]] && color="light_blue"; [[ -z "$style" ]] && style="italic" ;;
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

    local visible_len=${#text}
    local pad_left=0
    local pad_right=0

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

    local output=""
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

    # Affichage ou retour brut, ligne contnue ou pas
    if [[ -n "$raw_mode" ]]; then
        printf "%s" "$output"
    else
        if $newline; then
            printf "%b\n" "$output"
        else
            printf "%b" "$output"
        fi
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