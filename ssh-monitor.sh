#!/bin/bash

# ==============================================================================
# SSH SYSTEM MONITOR
# ==============================================================================

# Cleanup on exit
trap 'tput cnorm; echo -e "\033[0m"; clear; exit' INT TERM EXIT
tput civis # Hide cursor

# --- NEON COLORS (256-color mode) ---
# Using bright neon-like colors
C_BORDER='\033[38;5;45m'   # Neon Blue/Cyan
C_TITLE='\033[38;5;201m'    # Neon Magenta/Pink
C_HEADER='\033[38;5;226m'   # Neon Yellow
C_TEXT='\033[38;5;15m'      # White
C_VALUE='\033[38;5;118m'    # Neon Green/Lime
C_WARN='\033[38;5;196m'     # Neon Red
C_DIM='\033[38;5;240m'      # Dark Gray
RESET='\033[0m'

# --- CONFIGURATION ---
REFRESH_RATE=2
SCROLL_OFFSET=0
MAX_DISPLAY_LINES=0

# --- HELPER FUNCTIONS ---

draw_bar() {
    local val=$1
    local max=$2
    local width=$3
    local filled=$(( val * width / max ))
    local empty=$(( width - filled ))
    
    printf "["
    for ((i=0; i<filled; i++)); do printf "■"; done
    for ((i=0; i<empty; i++)); do printf " "; done
    printf "]"
}

get_system_info() {
    HOST=$(hostname)
    UPTIME=$(uptime -p | sed 's/up //')
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    MEM_PERC=$(( MEM_USED * 100 / MEM_TOTAL ))
}

# Main Loop
while true; do
    # Get terminal size
    LINES=$(tput lines)
    COLS=$(tput cols)
    
    # Check if terminal is too small
    if (( LINES < 20 || COLS < 80 )); then
        clear
        echo -e "${C_WARN}Terminal too small!${RESET}"
        echo -e "Required: 80x20 | Current: ${COLS}x${LINES}"
        sleep 2
        continue
    fi

    get_system_info
    
    # Collect Data
    mapfile -t TCP_CONNS < <(ss -tnp 2>/dev/null | grep ESTAB)
    mapfile -t SSH_USERS < <(who -u 2>/dev/null | awk '!/(:0|tty7)/ {print}')
    
    # Clear screen (flicker-free move to top)
    tput cup 0 0
    
    # --- HEADER SECTION ---
    echo -e "${C_BORDER}┌$(printf '─%.0s' $(seq 1 $((COLS-2))))┐${RESET}"
    printf "${C_BORDER}│${RESET} %-20s ${C_TITLE}%*s${RESET} %20s ${C_BORDER}│${RESET}\n" \
        "SYS: $HOST" $((COLS-46)) "⚡ NEON MONITOR ⚡" "$(date +'%H:%M:%S')"
    echo -e "${C_BORDER}├$(printf '─%.0s' $(seq 1 $((COLS-2))))┤${RESET}"
    
    # System Stats Row
    printf "${C_BORDER}│${RESET} ${C_HEADER}UPTIME:${RESET} %-12s ${C_HEADER}LOAD:${RESET} %-5s ${C_HEADER}CPU:${RESET} %-4s%% ${C_HEADER}MEM:${RESET} %-15s ${C_BORDER}│${RESET}\n" \
        "$UPTIME" "$LOAD" "$CPU_USAGE" "$MEM_USED/${MEM_TOTAL}MB ($MEM_PERC%)"
    echo -e "${C_BORDER}├$(printf '─%.0s' $(seq 1 $((COLS-2))))┤${RESET}"

    # --- TCP CONNECTIONS SECTION ---
    printf "${C_BORDER}│${RESET} ${C_TITLE}🌐 ACTIVE TCP CONNECTIONS (${#TCP_CONNS[@]})${RESET}%*s${C_BORDER}│${RESET}\n" $((COLS-27-${#TCP_CONNS[@]})) ""
    printf "${C_BORDER}│${RESET} ${C_HEADER}%-20s %-8s %-10s %-10s %-20s${RESET} ${C_BORDER}│${RESET}\n" \
        "REMOTE IP" "PORT" "STATE" "SEND-Q" "PROCESS"
    
    # Calculate space for connections
    # Total lines - (Header: 5 + SSH: 6 + Footer: 6) = available for TCP
    TCP_DISPLAY_LIMIT=$(( LINES - 18 ))
    (( TCP_DISPLAY_LIMIT < 3 )) && TCP_DISPLAY_LIMIT=3
    
    for ((i=0; i<TCP_DISPLAY_LIMIT; i++)); do
        idx=$(( i + SCROLL_OFFSET ))
        if [[ -n "${TCP_CONNS[$idx]}" ]]; then
            line="${TCP_CONNS[$idx]}"
            remote=$(echo "$line" | awk '{print $5}' | cut -d: -f1)
            port=$(echo "$line" | awk '{print $5}' | cut -d: -f2)
            state=$(echo "$line" | awk '{print $1}')
            sendq=$(echo "$line" | awk '{print $3}')
            proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' || echo "?")
            
            printf "${C_BORDER}│${RESET} %-20s %-8s %-10s %-10s %-20s ${C_BORDER}│${RESET}\n" \
                "${remote:0:20}" "$port" "$state" "$sendq" "${proc:0:20}"
        else
            printf "${C_BORDER}│${RESET} %*s ${C_BORDER}│${RESET}\n" $((COLS-4)) ""
        fi
    done
    
    # --- SSH USERS SECTION ---
    echo -e "${C_BORDER}├$(printf '─%.0s' $(seq 1 $((COLS-2))))┤${RESET}"
    printf "${C_BORDER}│${RESET} ${C_TITLE}👥 SSH SESSIONS (${#SSH_USERS[@]})${RESET}%*s${C_BORDER}│${RESET}\n" $((COLS-20-${#SSH_USERS[@]})) ""
    printf "${C_BORDER}│${RESET} ${C_HEADER}%-12s %-18s %-15s %-8s %-10s${RESET} ${C_BORDER}│${RESET}\n" \
        "USER" "SOURCE IP" "LOGIN TIME" "IDLE" "PID"
    
    for ((i=0; i<3; i++)); do
        if [[ -n "${SSH_USERS[$i]}" ]]; then
            line="${SSH_USERS[$i]}"
            user=$(echo "$line" | awk '{print $1}')
            ip=$(echo "$line" | grep -oP '\(\K[^)]+' || echo "local")
            ltime=$(echo "$line" | awk '{print $3" "$4}')
            idle=$(echo "$line" | awk '{print $5}')
            pid=$(echo "$line" | awk '{print $6}')
            printf "${C_BORDER}│${RESET} ${C_VALUE}%-12s${RESET} %-18s %-15s %-8s %-10s ${C_BORDER}│${RESET}\n" \
                "$user" "$ip" "$ltime" "$idle" "$pid"
        else
            printf "${C_BORDER}│${RESET} %*s ${C_BORDER}│${RESET}\n" $((COLS-4)) ""
        fi
    done

    # --- FOOTER & GRAPH SECTION ---
    echo -e "${C_BORDER}├$(printf '─%.0s' $(seq 1 $((COLS-2))))┤${RESET}"
    
    # CPU Graph
    cpu_int=${CPU_USAGE%.*}
    printf "${C_BORDER}│${RESET} ${C_HEADER}CPU LOAD ${RESET} %3s%% " "$cpu_int"
    echo -en "${C_VALUE}"
    draw_bar "$cpu_int" 100 $((COLS-20))
    echo -e "${RESET} ${C_BORDER}│${RESET}"
    
    # MEM Graph
    printf "${C_BORDER}│${RESET} ${C_HEADER}MEM LOAD ${RESET} %3s%% " "$MEM_PERC"
    echo -en "${C_TITLE}"
    draw_bar "$MEM_PERC" 100 $((COLS-20))
    echo -e "${RESET} ${C_BORDER}│${RESET}"

    echo -e "${C_BORDER}└$(printf '─%.0s' $(seq 1 $((COLS-2))))┘${RESET}"
    printf " ${C_DIM}CTRL+C to EXIT | Refresh: ${REFRESH_RATE}s | AUTO-SCROLL ENABLED${RESET}\n"

    # Handle Input & Scrolling
    # Use read with a timeout to allow for non-blocking input
    read -rsn1 -t $REFRESH_RATE key
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key # read the rest of the escape sequence
        case $key in
            "[A") # Up Arrow
                (( SCROLL_OFFSET-- ))
                (( SCROLL_OFFSET < 0 )) && SCROLL_OFFSET=0
                ;;
            "[B") # Down Arrow
                (( SCROLL_OFFSET++ ))
                max_offset=$(( ${#TCP_CONNS[@]} - TCP_DISPLAY_LIMIT ))
                (( SCROLL_OFFSET > max_offset )) && SCROLL_OFFSET=$max_offset
                ;;
        esac
    elif [[ -z $key ]]; then
        # Auto-scroll if no key pressed and we have too many connections
        if (( ${#TCP_CONNS[@]} > TCP_DISPLAY_LIMIT )); then
            (( SCROLL_OFFSET++ ))
            (( SCROLL_OFFSET > ${#TCP_CONNS[@]} - TCP_DISPLAY_LIMIT )) && SCROLL_OFFSET=0
        fi
    fi
done

