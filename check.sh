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
    
    # 1. fsck padrão para validar checksums
    if ostree fsck --repo="$repo_path" > /dev/null 2>&1; then
        log "${GREEN}✅ $name: INTEGRIDADE OK${NC}"
        RESULTADOS["$name"]="Saudável"
    else
        log "${RED}❌ $name: CORRUPÇÃO DETECTADA!${NC}"
        
        if [ "$repair_mode" = true ]; then
            log "${YELLOW}🛠️  Tentando reparo automático (deletando refs corrompidas)...${NC}"
            # Deleta referências que não batem com o checksum para que o 'main.sh' baixe de novo depois
            ostree fsck --repo="$repo_path" --delete-corrupted-refs | tee -a "$CHECK_LOG"
            log "${BLUE}🔄 Reparo concluído. Rode o main.sh para baixar o que foi removido.${NC}"
            RESULTADOS["$name"]="Reparado (Refaça o Sync)"
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
    
    # Pergunta se deseja tentar reparar automaticamente
    read -p "🔧 Deseja tentar reparar erros automaticamente se encontrados? (s/n) [n]: " auto_fix
    local fix_flag=false
    [[ "$auto_fix" =~ ^[Ss]$ ]] && fix_flag=true

    # Localiza todos os repositórios (Master e Discos)
    local repos=$(find "$RAIZ" -maxdepth 2 -name "objects" -type d)

    for obj_path in $repos; do
        local repo_dir=$(dirname "$obj_path")
        local repo_name=$(basename "$repo_dir")
        
        # Etiqueta amigável
        [[ "$repo_name" == "ostree-repo-full" ]] && label="⭐ MASTER" || label="💿 $repo_name"
        
        check_and_fix "$repo_dir" "$label" "$fix_flag"
        echo "----------------------------------------------------------"
    done

    # Resumo Final em Tabela
    echo -e "\n${BLUE}📊 RELATÓRIO FINAL:${NC}"
    printf "%-25s | %-20s\n" "REPOSITÓRIO" "STATUS"
    echo "----------------------------------------------------------"
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