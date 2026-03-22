#!/bin/bash
set -euo pipefail

# ========= CORES PARA O TERMINAL =========
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="./config.env"
declare -A DISCO_LIMITS=()

# ========= 1. CARREGAR CONFIGURAÇÕES PRÉVIAS =========
if [ -f "$CONFIG_FILE" ]; then
    # Silenciosamente carrega as variáveis se o arquivo existir
    source "$CONFIG_FILE"
fi

# ========= 2. VERIFICAÇÃO DE DEPENDÊNCIAS =========
check_deps() {
    echo -e "${BLUE}🔍 Verificando dependências...${NC}"
    local deps=("ostree" "flatpak" "parallel" "bc" "du" "grep" "tput")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}❌ Erro: '$dep' não está instalado.${NC}"
            exit 1
        fi
    done
}

# ========= 3. PERSISTÊNCIA (SALVAR CONFIG) =========
save_config() {
    # Captura o IP uma única vez para usar em ambos os arquivos
    local current_ip=$(hostname -I | awk '{print $1}')
    SERVER_IP=${current_ip:-"127.0.0.1"} # Fallback se o IP falhar

    echo -e "\n${BLUE}💾 Salvando configurações em $CONFIG_FILE...${NC}"
    {
        echo "# Arquivo Gerado Automaticamente - $(date)"
        echo "RAIZ=\"$RAIZ\""
        echo "FILTRO_IGNORAR=\"$FILTRO_IGNORAR\""
        echo "LANG_FILTER=\"$LANG_FILTER\""
        echo "THREADS=\"$THREADS\""
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "PORT_MASTER=8080"
        
        echo "unset DISCO_LIMITS"
        echo "declare -g -A DISCO_LIMITS"
        # Ordenamos as chaves para que a porta 8081 bata sempre com o mesmo disco
        for k in $(printf '%s\n' "${!DISCO_LIMITS[@]}" | sort); do
            echo "DISCO_LIMITS[\"$k\"]=\"${DISCO_LIMITS[$k]}\""
        done
    } > "$CONFIG_FILE"

    # --- GERAR O INSTALADOR AUTO-CONTIDO ---
    local client_script="$REPO_MASTER/setup_client.sh"
    mkdir -p "$REPO_MASTER"

    {
        echo "#!/bin/bash"
        echo "# INSTALADOR AUTO-GERADO EM $(date)"
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "PORT_MASTER=8080"
        
        local sorted_disks=$(printf '"%s" ' $(printf '%s\n' "${!DISCO_LIMITS[@]}" | sort))
        echo "DISCOS_NOMES=($sorted_disks)" 
        
        cat << 'EOF'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==========================================================${NC}"
echo -e "   🔧 CONFIGURAÇÃO DO MIRROR FLATPAK LOCAL"
echo -e "${BLUE}==========================================================${NC}"

# 1. PERGUNTA O MODO DE INSTALAÇÃO
echo -e "Como deseja configurar os repositórios?"
echo -e "1) ${YELLOW}Sistema${NC} (Para todos os usuários - Requer senha sudo)"
echo -e "2) ${YELLOW}Usuário${NC} (Apenas para você - Não requer senha)"
read -p "Escolha uma opção [1-2]: " OPC_MODO

case $OPC_MODO in
    1) MODE_FLAG="--system"; SUDO_CMD="sudo"; echo -e "\n📡 Modo Sistema selecionado.";;
    *) MODE_FLAG="--user"; SUDO_CMD=""; echo -e "\n📡 Modo Usuário selecionado.";;
esac

# 2. TESTE DE CONEXÃO
echo -e "${BLUE}🔍 Verificando servidor em http://$SERVER_IP:$PORT_MASTER...${NC}"
if ! curl -s --connect-timeout 2 "http://$SERVER_IP:$PORT_MASTER" > /dev/null; then
    echo -e "${RED}❌ ERRO: Servidor offline! Rode o './server.sh' no PC principal.${NC}"
    exit 1
fi

# 3. CONFIGURAR MASTER
echo -e "⭐ Adicionando MASTER..."
$SUDO_CMD flatpak remote-delete $MODE_FLAG local-master 2>/dev/null || true
# Adicionamos apenas o básico primeiro
$SUDO_CMD flatpak remote-add $MODE_FLAG --if-not-exists --no-gpg-verify local-master "http://$SERVER_IP:$PORT_MASTER"

# Agora configuramos as opções UMA POR UMA (Evita o erro de 'opção desconhecida')
$SUDO_CMD flatpak remote-modify $MODE_FLAG --priority=99 local-master
$SUDO_CMD flatpak remote-modify $MODE_FLAG --no-enumerate local-master

# 4. CONFIGURAR DISCOS
PORT_D=8081
PRIO_D=89
for disco in "${DISCOS_NOMES[@]}"; do
    NOME=$(basename "$disco" | tr '[:upper:]' '[:lower:]')
    echo -e "💿 Adicionando local-$NOME..."
    
    $SUDO_CMD flatpak remote-delete $MODE_FLAG "local-$NOME" 2>/dev/null || true
    $SUDO_CMD flatpak remote-add $MODE_FLAG --if-not-exists --no-gpg-verify "local-$NOME" "http://$SERVER_IP:$PORT_D"
    
    # Comandos separados para garantir que o Zorin aceite
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --priority=$PRIO_D "local-$NOME"
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --no-enumerate "local-$NOME"
    
    ((PORT_D++))
    ((PRIO_D--))
done

echo -e "\n${GREEN}✅ CLIENTE CONFIGURADO COM SUCESSO NO MODO ${MODE_FLAG^^}!${NC}"
EOF
    } > "$client_script"
    
    chmod +x "$client_script"
    chmod 644 "$client_script"
}

# ========= 4. CONFIGURAÇÃO INTERATIVA =========
ask_configs() {
    echo -e "${YELLOW}=== CONFIGURAÇÃO DO ESPELHO FLATPAK ===${NC}"
    
    # Pasta Raiz
    local def_raiz=${RAIZ:-/home/gustavo/Flatpak}
    read -p "📂 Pasta Raiz [$def_raiz]: " input_raiz
    RAIZ=${input_raiz:-$def_raiz}
    mkdir -p "$RAIZ"

    # Filtro Ignorar
    local def_ignore=${FILTRO_IGNORAR:-"(Debug|Sources)"}
    read -p "🚫 Ignorar (Regex) [$def_ignore]: " input_ignore
    FILTRO_IGNORAR=${input_ignore:-$def_ignore}

    # Idiomas
    local def_lang=${LANG_FILTER:-"(\.pt|pt_BR|pt-BR|\.en|en_US|en_GB)"}
    read -p "🌎 Idiomas (Regex) [$def_lang]: " input_lang
    LANG_FILTER=${input_lang:-$def_lang}

    # Threads
    local def_threads=${THREADS:-4}
    read -p "⚡ Threads [$def_threads]: " input_threads
    THREADS=${input_threads:-$def_threads}

    # Discos Dinâmicos
    if declare -p DISCO_LIMITS &>/dev/null; then
        if [ "${#DISCO_LIMITS[@]}" -gt 0 ] && [ -z "${RECONFIG_DISKS:-}" ]; then
            echo -e "\n${BLUE}📋 Discos atuais detectados:${NC}"
            for d in "${!DISCO_LIMITS[@]}"; do echo "   -> $d (${DISCO_LIMITS[$d]}GB)"; done
            read -p "➕ Deseja reconfigurar os discos? (s/n) [n]: " reconf
            if [[ "$reconf" =~ ^[Ss]$ ]]; then
                unset DISCO_LIMITS
                declare -g -A DISCO_LIMITS
                configure_disks_loop
            fi
        else
            configure_disks_loop
        fi
    else
        # Se não existe (caso do config.env limpo), cria agora
        declare -g -A DISCO_LIMITS
        configure_disks_loop
    fi

    save_config
}

configure_disks_loop() {
    local i=1
    local caminhos_vistos=""
    while true; do
        echo -e "\n💿 Configurando Disco #$i:"
        read -p "   Caminho [$RAIZ/DISCO$i]: " dpath
        dpath=${dpath:-$RAIZ/DISCO$i}
        
        if [[ " $caminhos_vistos " == *" $dpath "* ]]; then
            echo -e "${RED}❌ Erro: Caminho duplicado!${NC}"; continue
        fi

        read -p "   Limite em GB [50]: " dlimit
        dlimit=${dlimit:-50}
        
        DISCO_LIMITS["$dpath"]="$dlimit"
        caminhos_vistos+="$dpath "
        
        read -p "➕ Adicionar outro disco? (s/n) [n]: " resp
        [[ ! "$resp" =~ ^[Ss]$ ]] && break
        ((i++))
    done
}

# ========= 5. FUNÇÕES DE APOIO E DASHBOARD =========
log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_DIR/flatpak-mirror.log"; }

inc_progress() {
    local lock="$LOG_DIR/progress.lock"
    flock "$lock" bash -c "count=\$(cat '$LOG_DIR/progress.count' 2>/dev/null || echo 0); echo \$((count+1)) > '$LOG_DIR/progress.count'"
}

get_progress() { cat "$LOG_DIR/progress.count" 2>/dev/null || echo 0; }

show_progress() {
    local total="$1"
    local num_threads="$2"
    local start_time=$(date +%s)
    clear
    while true; do
        # 1. TRATATIVA DE ERRO: Garante que 'done' seja sempre um número
        local done=$(get_progress)
        done=${done:-0}
        [[ ! "$done" =~ ^[0-9]+$ ]] && done=0

        # 2. CÁLCULO DE TAMANHO DA RAIZ (Uso de Disco)
        # Captura o tamanho de forma legível (Ex: 15G, 500M)
        local root_size=$(du -sh "$RAIZ" 2>/dev/null | cut -f1 || echo "0B")

        # 3. CÁLCULO DE TEMPO E ETA
        local now=$(date +%s)
        local elapsed=$((now - start_time))
        
        if [ "$done" -gt 0 ] && [ "$elapsed" -gt 0 ]; then
            local rate=$(echo "scale=4; $done / $elapsed" | bc)
            local remaining=$((total - done))
            local eta_s=$(echo "$remaining / $rate" | bc 2>/dev/null | cut -d'.' -f1 || echo 0)
            local eta=$(printf '%dh:%dm:%ds' $((eta_s/3600)) $((eta_s%3600/60)) $((eta_s%60)))
        else
            local eta="Calculando..."
        fi

        # 4. RENDERIZAÇÃO DA INTERFACE (TUI)
        tput cup 0 0
        echo -e "${BLUE}==========================================================${NC}"
        echo -e "   🚀 ${GREEN}FLATPAK MIRROR MANAGER${NC} | v1.0"
        echo -e "   👤 Dev: ${YELLOW}Gustavo Caetano Reis${NC}"
        echo -e "${BLUE}==========================================================${NC}"
        echo -e "📊 Progresso: ${CYAN}$done${NC} / ${CYAN}$total${NC} | ⏱️ Ativo: ${elapsed}s"
        echo -e "⏳ ETA: ${GREEN}$eta${NC} | ⚡ Threads: $num_threads"
        echo -e "📂 Tamanho em Disco: ${YELLOW}$root_size${NC}"
        echo -e "----------------------------------------------------------"
        echo -e "👷 ${YELLOW}ATIVIDADE DOS THREADS:${NC}"
        for i in $(seq 1 "$num_threads"); do
            local task=$(cat "$LOG_DIR/thread_$i.txt" 2>/dev/null || echo "Aguardando...")
            # Limita a exibição do nome do app para não quebrar a linha
            printf "  [Slot %2d]: %-50s\n" "$i" "${task:0:50}"
        done
        echo -e "${BLUE}==========================================================${NC}"
        
        # O intervalo de 2 segundos evita sobrecarga de leitura no disco (I/O)
        sleep 2
    done
}

# ========= 6. PROCESSO DE DOWNLOAD E SYNC =========
pull_item() {
    local ref="$1"
    local slot=${PARALLEL_SEQ:-1}
    local thread_file="$LOG_DIR/thread_$slot.txt"
    echo "$ref" > "$thread_file"

    local retry=0
    while [ $retry -lt 3 ]; do
        if ostree pull --repo="$REPO_MASTER" flathub "$ref" --depth=1 >/dev/null 2>&1; then
            inc_progress
            echo "✅ OK: ${ref: -30}" > "$thread_file"
            return 0
        fi
        retry=$((retry+1))
        sleep 2
    done
    echo "$ref" >> "$LOG_DIR/failed-pulls.txt"
    inc_progress
    return 1
}
export -f pull_item inc_progress

sync_to_disks() {
    echo -e "\n${BLUE}🔄 Sincronizando pastas de destino...${NC}"
    for d in "${!DISCO_LIMITS[@]}"; do
        local limit=${DISCO_LIMITS[$d]}
        local atual_kb=$(du -s "$d" 2>/dev/null | cut -f1 || echo 0)
        local atual_gb=$((atual_kb / 1024 / 1024))

        if [ "$atual_gb" -ge "$limit" ]; then
            echo -e "${RED}⚠️  $d atingiu o limite de ${limit}GB. Pulando.${NC}"
            continue
        fi

        mkdir -p "$d"
        [ ! -d "$d/objects" ] && ostree init --repo="$d" --mode=archive-z2 && ostree remote add --repo="$d" flathub "https://dl.flathub.org/repo/" --set=gpg-verify=false
        
        echo -e "💾 Sincronizando: $(basename "$d")"
        ostree pull-local --repo="$d" "$REPO_MASTER" || true
        ostree summary -u --repo="$d"
    done
}

# ========= 7. MAIN =========
main() {
    check_deps
    
    # Previne erros de variáveis não associadas no início
    local temp_raiz="${RAIZ:-/home/gustavo/Flatpak}"
    REPO_MASTER="$temp_raiz/ostree-repo-full"
    LOG_DIR="$temp_raiz/logs"

    ask_configs
    
    # Atualiza caminhos após o ask_configs (onde o usuário define a RAIZ real)
    REPO_MASTER="$RAIZ/ostree-repo-full"
    LOG_DIR="$RAIZ/logs"
    mkdir -p "$LOG_DIR"
    
    local all="$LOG_DIR/all.txt"
    local filtered="$LOG_DIR/filtered.txt"
    local final="$LOG_DIR/prioritized.txt"

    echo -e "${BLUE}🔄 Coletando lista do Flathub...${NC}"
    flatpak remote-ls --system flathub --all --columns=ref > "$all"
    
    # --- FILTRAGEM INTELIGENTE ---
    grep -vE "${FILTRO_IGNORAR:-"(Debug|Sources)"}" "$all" > "${filtered}.tmp"
    grep -v "Locale" "${filtered}.tmp" > "$filtered" || true
    grep -E "Locale.*${LANG_FILTER:-"(\.pt|pt_BR|pt-BR)"}" "${filtered}.tmp" >> "$filtered" || true
    sort -u "$filtered" -o "$filtered"
    grep "^runtime/" "$filtered" > "$final" || true
    grep "^app/" "$filtered" >> "$final" || true
    
    local TOTAL=$(wc -l < "$final")
    echo 0 > "$LOG_DIR/progress.count"
    for i in $(seq 1 "$THREADS"); do echo "Iniciando..." > "$LOG_DIR/thread_$i.txt"; done

    # --- INICIALIZAÇÃO DO REPOSITÓRIO ---
    if [ ! -d "$REPO_MASTER/objects" ]; then
        ostree init --repo="$REPO_MASTER" --mode=archive-z2
        ostree remote add --repo="$REPO_MASTER" flathub "https://dl.flathub.org/repo/" --set=gpg-verify=false
    fi

    # --- INICIAR DASHBOARD (Em Background) ---
    show_progress "$TOTAL" "$THREADS" &
    DASH_PID=$!
    
    # --- EXECUÇÃO PARALELA ---
    export LOG_DIR REPO_MASTER
    parallel -j "$THREADS" --env pull_item --env REPO_MASTER --env LOG_DIR pull_item :::: "$final"

    # --- FINALIZAÇÃO E PÓS-PROCESSAMENTO ---
    kill $DASH_PID 2>/dev/null || true
    wait $DASH_PID 2>/dev/null # Garante que o terminal limpe antes de continuar
    
    echo -e "\n\n${GREEN}🏁 Download concluído!${NC}"
    
    # 1. GERA O ÍNDICE (Essencial para os clientes não darem erro)
    echo -e "${BLUE}🔄 Gerando índice do repositório (Summary)...${NC}"
    ostree summary -u --repo="$REPO_MASTER"

    # 2. SINCRONIZA COM OS DISCOS (Cria DISCO1, DISCO2...)
    sync_to_disks
    
    # 3. SALVA O CONFIG.ENV E O SETUP_CLIENT.SH (O novo com a pergunta de Usuário/Sistema)
    save_config

    echo -e "\n${YELLOW}✅ PROCESSO FINALIZADO COM SUCESSO EM SARZEDO!${NC}"
    echo -e "${BLUE}DICA:${NC} Agora é só rodar o ${GREEN}./server.sh${NC} e configurar seus filhos!"
}

main