#!/bin/bash

# Carrega as configurações (RAIZ, SERVER_IP e DISCO_LIMITS)
CONFIG_FILE="./config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[0;31m❌ Erro: Arquivo config.env não encontrado. Rode o main.sh primeiro.\033[0m"
    exit 1
fi
source "$CONFIG_FILE"

# Cores
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==========================================================${NC}"
echo -e "   🌐 SERVIDOR FLATPAK LOCAL - SARZEDO"
echo -e "   📍 IP do Servidor: ${CYAN}$SERVER_IP${NC}"
echo -e "${BLUE}==========================================================${NC}"

# 1. FUNÇÃO PARA GERAR SUMMARY (O MAPA DO REPOSITÓRIO)
prepare_repo() {
    local repo_path="$1"
    # Só tenta gerar o resumo se a pasta for um repositório OSTree válido
    if [ -d "$repo_path/objects" ]; then
        echo -ne "🛠️  Atualizando índice em $(basename "$repo_path")... "
        ostree summary -u --repo="$repo_path" > /dev/null 2>&1
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}⚠️  Aviso: $(basename "$repo_path") ainda não é um repositório válido.${NC}"
    fi
}

# 2. LIMPAR PROCESSOS ANTIGOS
echo -e "🧹 Limpando servidores anteriores..."
pkill -f "python3 -m http.server" 2>/dev/null || true
sleep 1

# 3. LANÇAR O MASTER (Porta 8080)
REPO_MASTER="$RAIZ/ostree-repo-full"
prepare_repo "$REPO_MASTER"

# GARANTIA: Copia o instalador para dentro do repo para que o wget funcione
cp "./setup_client.sh" "$REPO_MASTER/" 2>/dev/null || true

echo -e "🚀 Lançando MASTER em: ${YELLOW}http://$SERVER_IP:8080${NC}"
python3 -m http.server -d "$REPO_MASTER" 8080 > /dev/null 2>&1 &

# 4. LANÇAR OS DISCOS DINAMICAMENTE
PORT=8081
for d in $(printf '%s\n' "${!DISCO_LIMITS[@]}" | sort); do
    if [ -d "$d" ]; then
        prepare_repo "$d"
        # GARANTIA: Também copia o instalador para o disco, caso você queira
        # usar o IP do disco (8081) em vez do master (8080)
        cp "./setup_client.sh" "$d/" 2>/dev/null || true
        
        echo -e "💿 Lançando DISCO [$(basename "$d")] em: ${YELLOW}http://$SERVER_IP:$PORT${NC}"
        python3 -m http.server -d "$d" "$PORT" > /dev/null 2>&1 &
        ((PORT++))
    fi
done

echo -e "\n${GREEN}✅ TODOS OS SERVIDORES ESTÃO ONLINE!${NC}"
echo -e "----------------------------------------------------------"
echo -e "💻 ${YELLOW}COMANDO PARA OS FILHOS (RODAR NO TERMINAL DELES):${NC}"
echo -e "${CYAN}bash <(wget -qO- http://$SERVER_IP:8080/setup_client.sh)${NC}"
echo -e "----------------------------------------------------------"
echo -e "Pressione ${RED}[CTRL+C]${NC} para encerrar tudo."

# Mantém o script rodando e mata os processos filhos ao sair
trap "echo -e '\n🛑 Encerrando servidores...'; pkill -f 'python3 -m http.server'; exit" INT TERM
wait