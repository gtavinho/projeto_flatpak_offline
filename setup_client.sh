#!/bin/bash
# setup_client.sh - Configure este PC para usar o Mirror do Gustavo

# ========= CORES =========
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========= CONFIGURAÇÃO =========
# Se você estiver rodando o script na mesma pasta do config.env, ele lê automático.
# Caso contrário, ele vai pedir o IP do servidor.
if [ -f "./config.env" ]; then
    source ./config.env
else
    echo -e "${YELLOW}❓ config.env não encontrado.${NC}"
    read -p "🌐 Digite o IP do Servidor (ex: 192.168.1.50): " SERVER_IP
fi

PORT_M=8080
PORT_D_START=8081

echo -e "${BLUE}Configurando Remotos Flatpak do servidor $SERVER_IP...${NC}"

# 1. Adicionar o MASTER (Prioridade Máxima)
echo -e "\n⭐ Adicionando MASTER (Porta $PORT_M)..."
flatpak remote-add --if-not-exists --no-gpg-verify --priority=99 \
    local-master "http://$SERVER_IP:$PORT_M"

# 2. Adicionar os DISCOS (Fallbacks/Backups)
# Vamos tentar adicionar até 5 discos. Se a porta não estiver aberta no servidor, 
# o Flatpak apenas não encontrará o repositório, mas a config fica pronta.
PORT_D=$PORT_D_START
for i in {1..5}; do
    NAME="local-disco$i"
    PRIORITY=$((90 - i)) # Disco 1 = 89, Disco 2 = 88...
    
    echo -e "💿 Adicionando $NAME (Porta $PORT_D | Prioridade $PRIORITY)..."
    flatpak remote-add --if-not-exists --no-gpg-verify --priority=$PRIORITY \
        "$NAME" "http://$SERVER_IP:$PORT_D"
    
    ((PORT_D++))
done

echo -e "\n${GREEN}✅ CLIENTE CONFIGURADO COM SUCESSO!${NC}"
echo -e "Agora este PC prefere o seu servidor local antes de ir na internet."
echo -e "Para testar, tente: ${YELLOW}flatpak update${NC}"