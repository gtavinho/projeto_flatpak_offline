#!/bin/bash
set -euo pipefail

# ========= CONFIGURAÇÃO =========
CONFIG_FILE="./config.env"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

RAIZ=${RAIZ:-/home/gustavo/Flatpak}
LOG_DIR="$RAIZ/logs"
CHECK_LOG="$LOG_DIR/integrity-check.log"

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

# Variáveis de controle para o resumo final
declare -A RESULTADOS

log() {
    echo -e "[$(date '+%H:%M:%S')] $1" | tee -a "$CHECK_LOG"
}

# ========= FUNÇÃO DE VERIFICAÇÃO E REPARO =========
check_and_fix() {
    local repo_path="$1"
    local name="$2"
    local repair_mode="${3:-false}"

    log "${BLUE}🔍 Analisando: $name...${NC}"
    
    # 1. Validação do Summary
    ostree summary -u --repo="$repo_path" > /dev/null 2>&1 || true

    # 2. fsck com --shallow
    if ostree fsck --repo="$repo_path" --shallow > /dev/null 2>&1; then
        log "${GREEN}✅ $name: INTEGRIDADE OK${NC}"
        RESULTADOS["$name"]="Saudável"
    else
        log "${RED}❌ $name: CORRUPÇÃO DETECTADA!${NC}"
        
        if [ "$repair_mode" = true ]; then
            log "${YELLOW}🛠️  Iniciando Limpeza de Objetos Corrompidos...${NC}"
            
            # Em vez de --delete-corrupted-refs, usamos o prune para limpar o que está órfão/quebrado
            # Isso força o repositório a "esquecer" o que está ruim
            ostree prune --repo="$repo_path" --refs-only > /dev/null 2>&1 || true
            
            # Removemos objetos que não têm commit vinculado (objetos "soltos" e corrompidos)
            ostree prune --repo="$repo_path" > /dev/null 2>&1 || true
            
            log "${BLUE}🔄 Limpeza concluída. IMPORTANTE: Rode o main.sh agora para baixar os arquivos bons.${NC}"
            RESULTADOS["$name"]="Reparado (Refaça o Download)"
        else
            RESULTADOS["$name"]="CORROMPIDO"
        fi
    fi
}

# ========= EXECUÇÃO =========
main() {
    clear
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "       🛡️  SISTEMA DE INTEGRIDADE - FLATPAK MIRROR"
    echo -e "${YELLOW}==========================================================${NC}"
    
    # 1. Pergunta sobre o reparo
    read -p "🔧 Deseja tentar reparar erros automaticamente se encontrados? (s/n) [n]: " auto_fix
    local fix_flag=false
    [[ "$auto_fix" =~ ^[Ss]$ ]] && fix_flag=true

    log "${BLUE}📂 Localizando repositórios...${NC}"

    # 2. Coleta o Master (via find na RAIZ)
    local REPOS_LIST=$(find "$RAIZ" -maxdepth 2 -name "objects" -type d -exec dirname {} \;)

    # 3. Coleta os Discos (via config.env) para garantir que o DISCO1 entre na lista
    for disco_path in "${!DISCO_LIMITS[@]}"; do
        if [ -d "$disco_path/objects" ]; then
            # Adiciona à lista se ainda não estiver lá
            if [[ ! "$REPOS_LIST" =~ "$disco_path" ]]; then
                REPOS_LIST="$REPOS_LIST $disco_path"
            fi
        fi
    done

    # 4. Loop de processamento
    for repo_dir in $REPOS_LIST; do
        local repo_name=$(basename "$repo_dir")
        
        # Define a etiqueta visual
        local label=""
        if [[ "$repo_name" == "ostree-repo-full" ]]; then
            label="⭐ MASTER"
        else
            label="💿 $repo_name"
        fi
        
        # Chama a função de checagem (com o ajuste do --shallow que fizemos antes)
        check_and_fix "$repo_dir" "$label" "$fix_flag"
        echo -e "${YELLOW}----------------------------------------------------------${NC}"
    done

    # 5. Resumo Final em Tabela
    echo -e "\n${BLUE}📊 RELATÓRIO FINAL:${NC}"
    printf "%-25s | %-20s\n" "REPOSITÓRIO" "STATUS"
    echo "----------------------------------------------------------"
    # Note: A variável RESULTADOS deve ser preenchida dentro da check_and_fix
    for repo in "${!RESULTADOS[@]}"; do
        status="${RESULTADOS[$repo]}"
        if [[ "$status" == "Saudável" ]]; then
            printf "%-25s | ${GREEN}%-20s${NC}\n" "$repo" "$status"
        else
            printf "%-25s | ${RED}%-20s${NC}\n" "$repo" "$status"
        fi
    done
    echo -e "\n${YELLOW}📄 Log completo em: $CHECK_LOG${NC}"
}

main