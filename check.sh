#!/bin/bash
# Removi o -u temporariamente para a carga de arrays dinâmicos não quebrar
set -eo pipefail 

# ========= CONFIGURAÇÃO E CORES =========
CONFIG_FILE="./config.env"
# Inicializa o array antes para garantir que ele exista
declare -A DISCO_LIMITS=() 

if [ -f "$CONFIG_FILE" ]; then
    # Carrega as configurações
    source "$CONFIG_FILE"
fi

# Cores e Estilo
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Caminhos padrão
RAIZ=${RAIZ:-/home/gustavo/Flatpak}
LOG_DIR="$RAIZ/logs"
CHECK_LOG="$LOG_DIR/integrity-check.log"
mkdir -p "$LOG_DIR"

declare -A RESULTADOS

# ========= FUNÇÕES DE APOIO =========
header() {
    clear
    echo -e "${CYAN}${BOLD}==========================================================${NC}"
    echo -e "      🛡️  AUDITORIA DE INTEGRIDADE - MIRROR SARZEDO"
    echo -e "${CYAN}${BOLD}==========================================================${NC}"
}

log_status() {
    local color="$1"
    local msg="$2"
    echo -e "${color}${msg}${NC}" | tee -a "$CHECK_LOG"
}

verify_repo() {
    local repo_path="$1"
    local label="$2"
    local fix_mode="$3"

    echo -ne "🔍 Analisando ${BOLD}$label${NC}... "
    
    ostree summary -u --repo="$repo_path" > /dev/null 2>&1 || true

    if ostree fsck --repo="$repo_path" --shallow > /dev/null 2>&1; then
        echo -e "${GREEN}[SAUDÁVEL]${NC}"
        RESULTADOS["$label"]="${GREEN}✔ Saudável${NC}"
    else
        echo -e "${RED}[CORROMPIDO]${NC}"
        
        if [ "$fix_mode" = "true" ]; then
            log_status "$YELLOW" "🛠️  Tentando reparo em $label..."
            ostree fsck --repo="$repo_path" --delete-corrupted-refs --shallow > /dev/null 2>&1 || true
            ostree prune --repo="$repo_path" --refs-only > /dev/null 2>&1 || true
            RESULTADOS["$label"]="${YELLOW}⚠ Reparado (Incompleto)${NC}"
        else
            RESULTADOS["$label"]="${RED}✖ Corrompido${NC}"
        fi
    fi
}

# ========= MAIN =========
main() {
    header
    
    echo -e "Deseja que o script tente ${BOLD}REPARAR${NC} (deletar refs órfãs) automaticamente?"
    read -p "(s/n) [n]: " auto_fix
    local fix_flag=false
    [[ "$auto_fix" =~ ^[Ss]$ ]] && fix_flag=true

    echo -e "\n${BLUE}📂 Mapeando Repositórios...${NC}"
    
    local REPOS_TO_CHECK=()

    # 1. MASTER
    local master_path="$RAIZ/ostree-repo-full"
    [ -d "$master_path/objects" ] && REPOS_TO_CHECK+=("$master_path|⭐ MASTER")

    # 2. DISCOS (Com trava de segurança para variável vazia)
    if [ ${#DISCO_LIMITS[@]} -gt 0 ]; then
        for d_path in "${!DISCO_LIMITS[@]}"; do
            if [ -d "$d_path/objects" ]; then
                REPOS_TO_CHECK+=("$d_path|💿 $(basename "$d_path")")
            fi
        done
    fi

    echo -e "Encontrados ${BOLD}${#REPOS_TO_CHECK[@]}${NC} repositórios ativos.\n"

    for entry in "${REPOS_TO_CHECK[@]}"; do
        IFS="|" read -r path label <<< "$entry"
        verify_repo "$path" "$label" "$fix_flag"
    done

    echo -e "\n${CYAN}📊 RESUMO DA AUDITORIA:${NC}"
    echo -e "----------------------------------------------------------"
    # Ajustamos o alinhamento para não quebrar com o emoji
    printf "${BOLD}%-30s | %-20s${NC}\n" "REPOSITÓRIO" "STATUS"
    echo "----------------------------------------------------------"
    
    # Usamos o loop simples para evitar quebras de nomes com espaços ou estrelas
    for label in "${!RESULTADOS[@]}"; do
        status="${RESULTADOS[$label]}"
        printf "%-30b | %b\n" "$label" "$status"
    done
    echo "----------------------------------------------------------"

    if [[ " ${RESULTADOS[@]} " =~ "Corrompido" ]] || [[ " ${RESULTADOS[@]} " =~ "Reparado" ]]; then
        echo -e "\n${RED}📢 NOTA:${NC} Problemas encontrados. Rode o ${BOLD}main.sh${NC} para completar os arquivos."
    fi
}

main