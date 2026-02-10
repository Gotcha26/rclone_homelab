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
    print_fancy --align center --bg red --style bold --highlight "Le script a rencontré une erreur fatale !"
    print_fancy --theme error "$*" >&2
    print_fancy --align center --bg red --style bold --highlight "--- Veuillez corriger et/ou utiliser le menu interractif ---"
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
    sed -r "s/\x1B\[[0-9;]*[mK]//g"
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

   # Traduction des couleurs en séquences ANSI (get_fg_color/get_bg_color renvoient déjà des \033[...]m ou "" )
    [[ "$color" =~ ^\\e ]] || color=$(get_fg_color "${color:-bright_white}")
    [[ "$bg" =~ ^\\e ]] || bg=$(get_bg_color "$bg")

    # Style
    local style_seq=""
    [[ "$style" =~ bold ]] && style_seq+="$BOLD"
    [[ "$style" =~ italic ]] && style_seq+="$ITALIC"
    [[ "$style" =~ underline ]] && style_seq+="$UNDERLINE"

    # Visible length + padding (strwidth supprime déjà ANSI)
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

    # Pads purs (sans ANSI) — pas d'index sur eux, donc sûrs
    local pad_left_str=$(printf '%*s' "$pad_left" '' | tr ' ' "$fill")
    local pad_right_str=$(printf '%*s' "$pad_right" '' | tr ' ' "$fill")
    local output="${pad_left_str}${color}${bg}${style_seq}${text}${RESET}${pad_right_str}"

    # Highlight
    if [[ -n "$highlight" ]]; then
        local full_line
        full_line=$(printf '%*s' "$TERM_WIDTH_DEFAULT" '' | tr ' ' "$fill")
        full_line="${full_line:0:pad_left}${color}${bg}${style_seq}${text}${RESET}${bg}${full_line:$((pad_left + visible_len))}"
        output="${bg}${full_line}${RESET}"
    fi

    if [[ -n "$raw_mode" ]]; then
        printf "%b" "$output"
    else
        $newline && printf "%b\n" "$output" || printf "%b" "$output"
    fi
}


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


###############################################################################
# Fonction : Bordures tableau
###############################################################################
# Bordures robustes : répètent explicitement le caractère '─' n fois.
draw_border() {
    local -n ref=$1
    printf "┌"
    local i n
    for i in "${!ref[@]}"; do
        n=$(( ref[i] + 2 ))
        (( n < 0 )) && n=0
        if (( n > 0 )); then
            if command -v seq >/dev/null 2>&1; then
                printf '─%.0s' $(seq 1 $n)
            else
                # fallback si seq absent
                for ((j=0; j<n; j++)); do printf '─'; done
            fi
        fi
        [[ $i -lt $(( ${#ref[@]} - 1 )) ]] && printf "┬"
    done
    printf "┐\n"
}

draw_separator() {
    local -n ref=$1
    printf "├"
    local i n
    for i in "${!ref[@]}"; do
        n=$(( ref[i] + 2 ))
        (( n < 0 )) && n=0
        if (( n > 0 )); then
            if command -v seq >/dev/null 2>&1; then
                printf '─%.0s' $(seq 1 $n)
            else
                for ((j=0; j<n; j++)); do printf '─'; done
            fi
        fi
        [[ $i -lt $(( ${#ref[@]} - 1 )) ]] && printf "┼"
    done
    printf "┤\n"
}

draw_bottom() {
    local -n ref=$1
    printf "└"
    local i n
    for i in "${!ref[@]}"; do
        n=$(( ref[i] + 2 ))
        (( n < 0 )) && n=0
        if (( n > 0 )); then
            if command -v seq >/dev/null 2>&1; then
                printf '─%.0s' $(seq 1 $n)
            else
                for ((j=0; j<n; j++)); do printf '─'; done
            fi
        fi
        [[ $i -lt $(( ${#ref[@]} - 1 )) ]] && printf "┴"
    done
    printf "┘\n"
}


###############################################################################
# Fonction : Affiche un contenu avec padding, ANSI compris
# Arguments :
#   $1 = contenu (ANSI autorisé)
#   $2 = largeur visible de la colonne
###############################################################################
print_cell() {
    local content="$1" col_width="$2"
    local clean vis_len padding

    # Nettoyer ANSI pour calculer largeur visible
    clean=$(echo -e "$content" | strip_ansi)
    vis_len=$(strwidth "$clean")

    # Tronquer si trop long
    if (( vis_len > col_width )); then
        clean="${clean:0:col_width-3}..."
        # Recréer le contenu avec ANSI si nécessaire
        # Ici on simplifie en affichant sans ANSI tronqué
        content="$clean"
        vis_len=$(strwidth "$clean")
    fi

    # Padding
    (( padding = col_width - vis_len ))
    (( padding<0 )) && padding=0

    printf "%s%*s" "$content" "$padding" ""
}


truncate_ansi() {
    local str="$1"
    local max="$2"
    local clean visible
    clean=$(echo -e "$str" | strip_ansi)
    visible="${clean:0:max-1}"
    # Ajout d’un … si tronqué
    (( ${#clean} > max )) && visible="${visible}…"

    # Réappliquer le style original
    # On suppose que $str commence par la séquence ANSI et finit par RESET
    local prefix=$(echo -e "$str" | grep -oP '^\x1B\[[0-9;]*m' || true)
    printf "%b%s%b" "$prefix" "$visible" "\033[0m"
}


###############################################################################
# Fonction interne : Calcul des largeurs de colonnes et affichage du tableau
# Arguments :
#   $1 = nom du tableau de lignes (par référence)
#   $2 = largeur max (défaut 80)
#   $3 = mode de redimensionnement : "last_only" ou "all"
#   $4 = troncature dernière colonne : "truncate" ou "full"
###############################################################################
_print_table_core() {
    local -n _lines=$1
    local max_length="${2:-80}"
    local resize_mode="${3:-last_only}"
    local truncate_last="${4:-full}"

    local headers=("Variable" "Autorisé" "Défaut" "Valeur")
    local w=(0 0 0 0)
    local min_width=5

    # Largeur minimale basée sur les headers
    for i in $(seq 0 3); do
        (( $(strwidth "${headers[i]}") > w[i] )) && w[i]=$(strwidth "${headers[i]}")
    done

    # Largeur max des données
    for row in "${_lines[@]}"; do
        IFS="¤" read -r c1 c2 c3 c4 valid_flag <<<"$row"
        (( $(strwidth "$c1") > w[0] )) && w[0]=$(strwidth "$c1")
        (( $(strwidth "$c2") > w[1] )) && w[1]=$(strwidth "$c2")
        (( $(strwidth "$c3") > w[2] )) && w[2]=$(strwidth "$c3")
        (( $(strwidth "$c4") > w[3] )) && w[3]=$(strwidth "$c4")
    done

    # Redimensionnement
    local total_width=$(( w[0]+w[1]+w[2]+w[3]+13 ))
    if (( total_width > max_length )); then
        if [[ "$resize_mode" == "all" ]]; then
            local excess=$(( total_width - max_length ))
            local cut=$(( (excess + 3) / 4 ))
            for i in $(seq 0 3); do
                w[i]=$(( w[i] - cut > min_width ? w[i] - cut : min_width ))
            done
        else
            local fixed=$(( w[0]+w[1]+w[2]+10 ))
            local avail=$(( max_length - fixed ))
            w[3]=$(( avail > min_width ? avail : min_width ))
        fi
    fi

    # Bordure supérieure
    draw_border w

    # Entête
    printf "│ "
    for i in $(seq 0 3); do
        print_cell "$(print_fancy --style bold --raw "${headers[i]}")" "${w[i]}"
        printf " │ "
    done
    printf "\n"
    draw_separator w

    # Corps
    for row in "${_lines[@]}"; do
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
        print_cell "$var_cell" "${w[0]}"
        printf " │ "
        print_cell "$auth_cell" "${w[1]}"
        printf " │ "
        print_cell "$def_cell" "${w[2]}"
        printf " │ "
        if [[ "$truncate_last" == "truncate" ]]; then
            print_cell "$(truncate_ansi "$val_cell" "${w[3]}")" "${w[3]}"
        else
            print_cell "$val_cell" "${w[3]}"
        fi
        printf " │\n"
    done

    draw_bottom w
}


###############################################################################
# Fonction : Affichage d'un tableau formaté (redimensionne la dernière colonne)
###############################################################################
print_table() {
    _print_table_core "$1" "${2:-80}" "last_only" "truncate"
}


###############################################################################
# Fonction : Affichage d'un tableau formaté (toutes les colonnes s'ajustent)
###############################################################################
print_table_auto() {
    _print_table_core "$1" "${2:-80}" "all" "full"
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

    # ===== Booléen =====
    if [[ "$allowed" == "bool" ]]; then
        display_allowed="false|true"
        [[ "$value" =~ ^(0|1|true|false|yes|no|on|off)$ ]] || valid=false

    # ===== Intervalle numérique =====
    elif [[ "$allowed" =~ ^[0-9]+-[0-9]+$ ]]; then
        display_allowed="$allowed"
        IFS="-" read -r min max <<< "$allowed"
        (( value < min || value > max )) && valid=false

    # ===== Joker '*' =====
    elif [[ "$allowed" == "*" ]]; then
        display_allowed="*"
        valid=true

    # ===== Liste de valeurs =====
    else
        IFS="|" read -ra allowed_arr <<<"$allowed"
        valid=false
        display_allowed=""
        for v in "${allowed_arr[@]}"; do
            [[ "$v" == "''" ]] && v=""
            [[ -z "$display_allowed" ]] && display_allowed="$v" || display_allowed+="|$v"
            [[ "$value" == "$v" ]] && valid=true
        done
    fi

    COMPUTE_VALUE="$value"
    COMPUTE_DISPLAY_ALLOWED="$display_allowed"
    COMPUTE_VALID="$valid"
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

        # Valeur actuelle (ou défaut)
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
                        "\n"
                    value="${default:-0}"
                    ;;
            esac
            export "$key"="$value"
            continue
        fi

        # Cas joker "*"
        if [[ "$allowed" == "*" ]]; then
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
