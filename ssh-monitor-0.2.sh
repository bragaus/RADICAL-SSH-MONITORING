#!/bin/bash

# ==============================================================================
# 監視システムSSH - 鎖を断て
# ==============================================================================

# 終了時の処理 - カーソルを戻して画面を整える
trap 'tput cnorm; echo -e "\033[0m"; clear; exit' INT TERM EXIT
tput civis

# 派手な色で監視の顔を覆い隠す
COR_BORDA=$'\033[38;5;45m'
COR_TITULO=$'\033[38;5;201m'
COR_CABECALHO=$'\033[38;5;226m'
COR_TEXTO=$'\033[38;5;15m'
COR_VALOR=$'\033[38;5;118m'
COR_AVISO=$'\033[38;5;196m'
COR_ATENUADA=$'\033[38;5;240m'
REINICIALIZACAO=$'\033[0m'

# --- CONFIGURAÇÃO ---
TAXA_ATUALIZACAO=2
DESLOCAMENTO_ROLAGEM=0
LINHAS_MAXIMAS_EXIBICAO=0

# --- FUNÇÕES AUXILIARES ---

desenhar_barra() {
    local valor=$1
    local maximo=$2
    local largura=$3
    local preenchido=$(( valor * largura / maximo ))
    local vazio=$(( largura - preenchido ))

    printf "["
    for ((i=0; i<preenchido; i++)); do printf "■"; done
    for ((i=0; i<vazio; i++)); do printf " "; done
    printf "]"
}

obter_informacoes_sistema() {
    NOME_HOST=$(hostname)
    TEMPO_ATIVO=$(uptime -p | sed 's/up //')
    CARGA_MEDIA=$(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
    USO_CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    MEMORIA_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
    MEMORIA_USADA_MB=$(free -m | awk '/Mem:/ {print $3}')
    PERCENTUAL_MEMORIA=$(( MEMORIA_USADA_MB * 100 / MEMORIA_TOTAL_MB ))
}

# --- CICLO PRINCIPAL ---
while true; do
    # サイズを確認する
    NUMERO_LINHAS=$(tput lines)
    NUMERO_COLUNAS=$(tput cols)

    # 小さすぎる端末は使えない
    if (( NUMERO_LINHAS < 20 || NUMERO_COLUNAS < 80 )); then
        clear
        echo -e "${COR_AVISO}Terminal insuficiente!${REINICIALIZACAO}"
        echo -e "Requisito: 80x20 | Atual: ${NUMERO_COLUNAS}x${NUMERO_LINHAS}"
        sleep 2
        continue
    fi

    obter_informacoes_sistema

    # 情報を集める
    mapfile -t CONEXOES_TCP < <(ss -tnp 2>/dev/null | grep ESTAB)
    mapfile -t USUARIOS_SSH < <(who -u 2>/dev/null | awk '!/(:0|tty7)/ {print}')

    # 画面の先頭へ戻る
    tput cup 0 0

    # --- CABEÇALHO ---
    echo -e "${COR_BORDA}┌$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┐${REINICIALIZACAO}"
    printf "${COR_BORDA}│${REINICIALIZACAO} %-20s ${COR_TITULO}%*s${REINICIALIZACAO} %20s ${COR_BORDA}│${REINICIALIZACAO}\n" \
        "SYS: $NOME_HOST" $((NUMERO_COLUNAS-46)) "⚡ NEON MONITOR ⚡" "$(date +'%H:%M:%S')"
    echo -e "${COR_BORDA}├$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┤${REINICIALIZACAO}"

    # 状態を表示する
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_CABECALHO}UPTIME:${REINICIALIZACAO} %-12s ${COR_CABECALHO}LOAD:${REINICIALIZACAO} %-5s ${COR_CABECALHO}CPU:${REINICIALIZACAO} %-4s%% ${COR_CABECALHO}MEM:${REINICIALIZACAO} %-15s ${COR_BORDA}│${REINICIALIZACAO}\n" \
        "$TEMPO_ATIVO" "$CARGA_MEDIA" "$USO_CPU" "$MEMORIA_USADA_MB/${MEMORIA_TOTAL_MB}MB ($PERCENTUAL_MEMORIA%)"
    echo -e "${COR_BORDA}├$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┤${REINICIALIZACAO}"

    # --- TCP CONNECTIONS ---
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_TITULO}🌐 ACTIVE TCP CONNECTIONS (${#CONEXOES_TCP[@]})${REINICIALIZACAO}%*s${COR_BORDA}│${REINICIALIZACAO}\n" $((NUMERO_COLUNAS-27-${#CONEXOES_TCP[@]})) ""
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_CABECALHO}%-20s %-8s %-10s %-10s %-20s${REINICIALIZACAO} ${COR_BORDA}│${REINICIALIZACAO}\n" \
        "REMOTE IP" "PORT" "STATE" "SEND-Q" "PROCESS"

    # 表示できる行数を決める
    LIMITE_EXIBICAO_TCP=$(( NUMERO_LINHAS - 18 ))
    (( LIMITE_EXIBICAO_TCP < 3 )) && LIMITE_EXIBICAO_TCP=3

    for ((i=0; i<LIMITE_EXIBICAO_TCP; i++)); do
        indice=$(( i + DESLOCAMENTO_ROLAGEM ))
        if [[ -n "${CONEXOES_TCP[$indice]}" ]]; then
            linha="${CONEXOES_TCP[$indice]}"
            IP_REMOTO=$(echo "$linha" | awk '{print $5}' | cut -d: -f1)
            PORTA=$(echo "$linha" | awk '{print $5}' | cut -d: -f2)
            ESTADO=$(echo "$linha" | awk '{print $1}')
            FILA_ENVIO=$(echo "$linha" | awk '{print $3}')
            PROCESSO=$(echo "$linha" | grep -oP 'users:\(\("\K[^"]+' || echo "?")

            printf "${COR_BORDA}│${REINICIALIZACAO} %-20s %-8s %-10s %-10s %-20s ${COR_BORDA}│${REINICIALIZACAO}\n" \
                "${IP_REMOTO:0:20}" "$PORTA" "$ESTADO" "$FILA_ENVIO" "${PROCESSO:0:20}"
        else
            printf "${COR_BORDA}│${REINICIALIZACAO} %*s ${COR_BORDA}│${REINICIALIZACAO}\n" $((NUMERO_COLUNAS-4)) ""
        fi
    done

    # --- SSH SESSIONS ---
    echo -e "${COR_BORDA}├$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┤${REINICIALIZACAO}"
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_TITULO}👥 SSH SESSIONS (${#USUARIOS_SSH[@]})${REINICIALIZACAO}%*s${COR_BORDA}│${REINICIALIZACAO}\n" $((NUMERO_COLUNAS-20-${#USUARIOS_SSH[@]})) ""
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_CABECALHO}%-12s %-18s %-15s %-8s %-10s${REINICIALIZACAO} ${COR_BORDA}│${REINICIALIZACAO}\n" \
        "USER" "SOURCE IP" "LOGIN TIME" "IDLE" "PID"

    for ((i=0; i<3; i++)); do
        if [[ -n "${USUARIOS_SSH[$i]}" ]]; then
            linha="${USUARIOS_SSH[$i]}"
            USUARIO=$(echo "$linha" | awk '{print $1}')
            IP_ORIGEM=$(echo "$linha" | grep -oP '\(\K[^)]+' || echo "local")
            TEMPO_LOGIN=$(echo "$linha" | awk '{print $3" "$4}')
            OCIOSO=$(echo "$linha" | awk '{print $5}')
            PID_PROCESSO=$(echo "$linha" | awk '{print $6}')
            printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_VALOR}%-12s${REINICIALIZACAO} %-18s %-15s %-8s %-10s ${COR_BORDA}│${REINICIALIZACAO}\n" \
                "$USUARIO" "$IP_ORIGEM" "$TEMPO_LOGIN" "$OCIOSO" "$PID_PROCESSO"
        else
            printf "${COR_BORDA}│${REINICIALIZACAO} %*s ${COR_BORDA}│${REINICIALIZACAO}\n" $((NUMERO_COLUNAS-4)) ""
        fi
    done

    # --- GRAFICOS ---
    echo -e "${COR_BORDA}├$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┤${REINICIALIZACAO}"

    # CPU
    USO_CPU_INTEIRO=${USO_CPU%.*}
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_CABECALHO}CPU LOAD ${REINICIALIZACAO} %3s%% " "$USO_CPU_INTEIRO"
    echo -en "${COR_VALOR}"
    desenhar_barra "$USO_CPU_INTEIRO" 100 $((NUMERO_COLUNAS-20))
    echo -e "${REINICIALIZACAO} ${COR_BORDA}│${REINICIALIZACAO}"

    # MEM
    printf "${COR_BORDA}│${REINICIALIZACAO} ${COR_CABECALHO}MEM LOAD ${REINICIALIZACAO} %3s%% " "$PERCENTUAL_MEMORIA"
    echo -en "${COR_TITULO}"
    desenhar_barra "$PERCENTUAL_MEMORIA" 100 $((NUMERO_COLUNAS-20))
    echo -e "${REINICIALIZACAO} ${COR_BORDA}│${REINICIALIZACAO}"

    echo -e "${COR_BORDA}└$(printf '─%.0s' $(seq 1 $((NUMERO_COLUNAS-2))))┘${REINICIALIZACAO}"
    printf " ${COR_ATENUADA}CTRL+C to EXIT | Refresh: ${TAXA_ATUALIZACAO}s | AUTO-SCROLL ENABLED${REINICIALIZACAO}\n"

    # 入力を処理する
    read -rsn1 -t $TAXA_ATUALIZACAO tecla
    if [[ $tecla == $'\x1b' ]]; then
        read -rsn2 -t 0.1 tecla
        case $tecla in
            "[A")
                (( DESLOCAMENTO_ROLAGEM-- ))
                (( DESLOCAMENTO_ROLAGEM < 0 )) && DESLOCAMENTO_ROLAGEM=0
                ;;
            "[B")
                (( DESLOCAMENTO_ROLAGEM++ ))
                deslocamento_maximo=$(( ${#CONEXOES_TCP[@]} - LIMITE_EXIBICAO_TCP ))
                (( deslocamento_maximo < 0 )) && deslocamento_maximo=0
                (( DESLOCAMENTO_ROLAGEM > deslocamento_maximo )) && DESLOCAMENTO_ROLAGEM=$deslocamento_maximo
                ;;
        esac
    elif [[ -z $tecla ]]; then
        # 自動スクロール - 多すぎる接続を流す
        if (( ${#CONEXOES_TCP[@]} > LIMITE_EXIBICAO_TCP )); then
            (( DESLOCAMENTO_ROLAGEM++ ))
            (( DESLOCAMENTO_ROLAGEM > ${#CONEXOES_TCP[@]} - LIMITE_EXIBICAO_TCP )) && DESLOCAMENTO_ROLAGEM=0
        fi
    fi
done
