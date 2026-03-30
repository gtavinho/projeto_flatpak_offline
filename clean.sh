#!/usr/bin/env bash

# ========= VALIDAÇÕES =========
[ -z "$BASH_VERSION" ] && { echo "❌ Use: bash $0"; exit 1; }

# ========= CONFIG =========
CONFIG_FILE="./config.env"
[ ! -f "$CONFIG_FILE" ] && { echo "❌ config.env não encontrado!"; exit 1; }

source "$CONFIG_FILE"
REPO_MASTER="$RAIZ/ostree-repo-full"

# ========= CORES =========
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ========= FUNÇÕES =========

header() {
    clear
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "   🧹 FAXINA E ANÁLISE DE DISCO: COMITENERD"
    echo -e "${BLUE}==========================================================${NC}"
}

pause() {
    read -p "Pressione Enter para continuar..."
}

# Converte tamanho (MB/GB/KB → MB)
to_mb() {
    local size="$1"

    # Remove lixo (como ?)
    size=$(echo "$size" | tr -d '?')

    # Separa número e unidade
    local valor unidade
    valor=$(echo "$size" | grep -oE '[0-9]+([.][0-9]+)?')
    unidade=$(echo "$size" | grep -oE '[A-Za-z]+')

    # fallback
    valor=${valor:-0}
    unidade=${unidade:-MB}

    case "$unidade" in
        GB) awk "BEGIN {printf \"%.2f\", $valor * 1024}" ;;
        MB) awk "BEGIN {printf \"%.2f\", $valor}" ;;
        KB) awk "BEGIN {printf \"%.2f\", $valor / 1024}" ;;
        *)  echo "0" ;;
    esac
}

# Define cor baseada no tamanho
get_color() {
    local size_mb="$1"

    awk -v size="$size_mb" '
    BEGIN {
        if (size+0 > 500) print "'$RED'"
        else if (size+0 > 150) print "'$YELLOW'"
        else print "'$GREEN'"
    }'
}

# ========= TOP OFFENDERS =========
list_top_offenders() {
    header
    read -p "Quantos itens listar? [10]: " LIMIT
    LIMIT=${LIMIT:-10}

    echo -e "\n${YELLOW}🔍 Buscando maiores apps...${NC}\n"

    local data
    data=$(LC_ALL=C flatpak list --app --columns=application,size \
        | sort -k2 -hr | head -n "$LIMIT")

    [ -z "$data" ] && { echo "⚠️ Sem dados."; pause; return; }

    printf "${BOLD}%-40s | %-10s${NC}\n" "APLICAÇÃO" "TAMANHO"
    echo "----------------------------------------------------------"

    while read -r app size; do
        size_mb=$(to_mb "$size")
        color=$(get_color "$size_mb")

        printf "${color}%-40s${NC} | %-10s\n" "$app" "$size"
    done <<< "$data"

    echo "----------------------------------------------------------"
    pause
}

# ========= LIMPEZA =========
cleanup_repo() {
    header

    DEFAULT_FILTER="Debug|Sources|Docs|Sdk\.Docs|18\.08|19\.08|20\.08"
    echo -e "${CYAN}Sugestão:${NC} $DEFAULT_FILTER"

    read -p "Filtro regex: " USER_FILTER
    LIXO_REGEX=${USER_FILTER:-$DEFAULT_FILTER}

    local refs
    refs=$(ostree --repo="$REPO_MASTER" refs | grep -iE "$LIXO_REGEX" || true)

    [ -z "$refs" ] && {
        echo -e "${GREEN}✨ Nada para limpar!${NC}"
        pause; return;
    }

    echo -e "\n${YELLOW}📊 Calculando economia real (aguarde)...${NC}"

    TOTAL_BYTES=0

    while read -r ref; do
        [ -z "$ref" ] && continue
        
        # Soma o tamanho de todos os arquivos dentro dessa ref usando o ls -R do ostree
        # O awk soma a 4ª coluna da saída do ls -R (tamanho em bytes)
        size=$(ostree --repo="$REPO_MASTER" ls -R "$ref" 2>/dev/null | awk '/^-/ {sum += $4} END {print sum}')
        
        # Se vier vazio, vira 0
        size=${size:-0}
        TOTAL_BYTES=$(awk "BEGIN {print $TOTAL_BYTES + $size}")

    done <<< "$refs"

    # Converte para GB com 2 casas decimais
    ECONOMIA_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES/1024/1024/1024}")

    echo -e "\n${RED}⚠️ Itens que serão removidos:${NC}"
    echo "$refs" | sed 's/^/  - /'

    echo -e "\n${GREEN}💰 Economia estimada: ${YELLOW}$ECONOMIA_GB GB${NC}"

    read -p "Confirmar exclusão definitiva? (s/n): " confirm

    [[ ! "$confirm" =~ ^[Ss]$ ]] && return

    echo -e "\n${BLUE}🗑️ Removendo referências (nomes)...${NC}"
    echo "$refs" | xargs -r -I {} ostree --repo="$REPO_MASTER" refs --delete {}

    echo -e "${BLUE}🧹 Prunando objetos órfãos (Limpando o HD de verdade)...${NC}"
    # O --depth=0 garante que TUDO que não está em uso seja deletado
    ostree prune --repo="$REPO_MASTER" --depth=0
    
    echo -e "${BLUE}📝 Reconstruindo o sumário do repositório...${NC}"
    ostree summary -u --repo="$REPO_MASTER"

    echo -e "\n${GREEN}✅ FAXINA CONCLUÍDA!${NC}"
    du -sh "$REPO_MASTER" | awk '{print "📂 Tamanho atual do Repo: " $1}'

    pause
}

# ========= MENU =========
while true; do
    header
    echo "1) 📊 Top Offensores"
    echo "2) 🧹 Limpeza por filtro"
    echo "3) 🚪 Sair"
    echo "--------------------------------"

    read -p "Escolha: " opt

    case "$opt" in
        1) list_top_offenders ;;
        2) cleanup_repo ;;
        3) exit 0 ;;
        *) echo "Opção inválida"; sleep 1 ;;
    esac
done