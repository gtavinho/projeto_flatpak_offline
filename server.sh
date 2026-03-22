#!/bin/bash

# ========= CARREGAR CONFIGURAÇÕES =========
CONFIG_FILE="./config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Erro: Arquivo config.env não encontrado. Rode o main.sh primeiro."
    exit 1
fi
source "$CONFIG_FILE"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Array para guardar os PIDs dos processos filhos (Python)
declare -a PIDS=()

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }

# Função para desligar tudo corretamente sem entrar em loop
cleanup() {
    echo -e "\n${YELLOW}🛑 Desligando servidores Python...${NC}"
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    exit 0
}

# Captura o Ctrl+C (SIGINT) e chama o cleanup
trap cleanup SIGINT SIGTERM

# ========= PREPARAÇÃO DE SEGURANÇA =========
REPO_MASTER="$RAIZ/ostree-repo-full"

# Garante que o instalador gerado tenha permissão de leitura para o servidor HTTP
if [ -f "$REPO_MASTER/setup_client.sh" ]; then
    chmod 644 "$REPO_MASTER/setup_client.sh"
    log "📋 Instalador verificado e disponível para os clientes."
else
    log "⚠️  Aviso: setup_client.sh não encontrado em $REPO_MASTER"
fi

# ========= LIMPEZA DE PORTAS (Prevenção) =========
log "🧹 Limpando portas antigas..."
# Mata qualquer processo que esteja travando a porta 8080 ou a faixa dos discos
fuser -k ${PORT_MASTER:-8080}/tcp 2>/dev/null || true
for p in {8081..8090}; do fuser -k $p/tcp 2>/dev/null || true; done

# ========= INICIAR SERVIDORES =========

# 1. MASTER SERVER (Porta 8080)
PORT_M=${PORT_MASTER:-8080}
if [ -d "$REPO_MASTER" ]; then
    log "${GREEN}⭐ MASTER ON: http://$SERVER_IP:$PORT_M${NC}"
    (cd "$REPO_MASTER" && python3 -m http.server "$PORT_M") > /dev/null 2>&1 &
    PIDS+=($!)
else
    log "❌ Erro: Pasta Master não encontrada em $REPO_MASTER"
    exit 1
fi

# 2. DISK SERVERS (Porta 8081 em diante)
PORT_D=8081
# Ordenação idêntica à do main.sh para manter consistência entre portas e discos
mapfile -t sorted_disks < <(printf '%s\n' "${!DISCO_LIMITS[@]}" | sort)

for dpath in "${sorted_disks[@]}"; do
    if [ -d "$dpath" ]; then
        disco_nome=$(basename "$dpath")
        log "${YELLOW}💿 $disco_nome ON: http://$SERVER_IP:$PORT_D${NC}"
        (cd "$dpath" && python3 -m http.server "$PORT_D") > /dev/null 2>&1 &
        PIDS+=($!)
        ((PORT_D++))
    fi
done

echo -e "\n${GREEN}🚀 Sistema Online em Sarzedo! Pressione Ctrl+C para parar.${NC}"
echo -e "Comando para os clientes:"
echo -e "${CYAN}bash <(wget -qO- http://$SERVER_IP:8080/setup_client.sh)${NC}\n"

# Mantém o script vivo aguardando os processos background
wait