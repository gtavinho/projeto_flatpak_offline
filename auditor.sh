#!/bin/bash
# Verifica se está rodando no bash
if [ -z "$BASH_VERSION" ]; then
    echo "❌ Este script precisa ser executado com bash!"
    echo "👉 Use: bash $0"
    exit 1
fi
# Auditoria Seletiva: Integridade ou Dependências
set -eo pipefail 

# ========= CONFIGURAÇÃO E CORES =========
CONFIG_FILE="./config.env"
declare -A DISCO_LIMITS=() 

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

RAIZ=${RAIZ:-/home/gustavo/Flatpak}
REPO_MASTER="$RAIZ/ostree-repo-full"
LOG_DIR="$RAIZ/logs"
mkdir -p "$LOG_DIR"

declare -A RESULTADOS

# ========= FUNÇÕES DE APOIO =========
# Função de animação para processos demorados
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}
header() {
    clear
    echo -e "${CYAN}${BOLD}==========================================================${NC}"
    echo -e "      🛡️  SISTEMA DE AUDITORIA - ComiteNerd"
    echo -e "${CYAN}${BOLD}==========================================================${NC}"
}

# 🛠️ FUNÇÃO 1: INTEGRIDADE (FSCK)
run_integrity() {
    echo -e "\n${BLUE}📂 Verificando Integridade dos Repositórios (Multi-Thread)...${NC}"
    
    echo -e "Deseja tentar ${BOLD}REPARAR${NC} erros automaticamente?"
    read -p "(s/n) [n]: " auto_fix
    local fix_flag=false
    [[ "$auto_fix" =~ ^[Ss]$ ]] && fix_flag=true

    # Monta a lista de repositórios existentes
    local REPOS_TO_CHECK=()
    [ -d "$REPO_MASTER/objects" ] && REPOS_TO_CHECK+=("$REPO_MASTER|MASTER")
    
    if [ ${#DISCO_LIMITS[@]} -gt 0 ]; then
        for d_path in "${!DISCO_LIMITS[@]}"; do
            [ -d "$d_path/objects" ] && REPOS_TO_CHECK+=("$d_path|$(basename "$d_path")")
        done
    fi

    [ ${#REPOS_TO_CHECK[@]} -eq 0 ] && { echo -e "${RED}Nenhum repo encontrado.${NC}"; return; }

    echo -ne "${CYAN}🔍 Analisando ${#REPOS_TO_CHECK[@]} repositório(s) em paralelo...${NC} "

    # Arquivo temporário para os resultados das threads
    local tmp_res="/tmp/integrity_results.tmp"
    > "$tmp_res"

    # --- DISPARO EM PARALELO ---
    (
        export fix_flag
        printf "%s\n" "${REPOS_TO_CHECK[@]}" | xargs -P "${THREADS:-2}" -I {} bash -c '
            IFS="|" read -r path label <<< "{}"
            
            # Executa o fsck
            if ostree fsck --repo="$path" > /dev/null 2>&1; then
                echo "$label|OK"
            else
                if [ "$fix_flag" = "true" ]; then
                    # Tenta o reparo se houver erro
                    ostree fsck --repo="$path" --delete-corrupted-refs > /dev/null 2>&1 || true
                    ostree prune --repo="$path" --depth=0 > /dev/null 2>&1 || true
                    # Re-checa após reparo
                    if ostree fsck --repo="$path" > /dev/null 2>&1; then
                        echo "$label|REPARADO"
                    else
                        echo "$label|FALHA"
                    fi
                else
                    echo "$label|ERRO"
                fi
            fi
        ' >> "$tmp_res"
    ) &

    local pid_parallel=$!
    spinner $pid_parallel
    wait $pid_parallel

    # --- PROCESSAMENTO DOS RESULTADOS ---
    echo -e "\r${CYAN}📊 RESUMO DA SAÚDE FÍSICA:                              ${NC}"
    echo "----------------------------------------------------------"
    while IFS="|" read -r label status; do
        case $status in
            OK)       res_txt="${GREEN}✔ Saudável${NC}" ;;
            REPARADO) res_txt="${YELLOW}⚠ Reparado (Prunado)${NC}" ;;
            ERRO)     res_txt="${RED}✖ Corrompido${NC}" ;;
            FALHA)    res_txt="${RED}✖ Falha no Reparo${NC}" ;;
        esac
        printf "%-30b | %b\n" "$label" "$res_txt"
        RESULTADOS["$label"]="$res_txt"
    done < "$tmp_res"
    echo "----------------------------------------------------------"
    
    rm -f "$tmp_res"
}
run_dependencies() {
    # Garante que o alvo venha do config ou use o padrão
    local alvo="${FILTRO_IGNORAR:-18\.08|19\.08|20\.08}"
    local num_threads="${THREADS:-4}"
    
    # Resolve o caminho absoluto do REPO_MASTER para não ter erro de "Repo not found"
    local repo_abs=$(realpath "$REPO_MASTER")
    
    echo -e "\n${BLUE}🔗 Checando Dependências Críticas...${NC}"
    echo -e "${CYAN}Filtro ativo:${NC} $alvo"
    
    # Busca as refs. Se falhar, tenta listar sem o prefixo app/ para diagnosticar
    local apps=$(ostree --repo="$repo_abs" refs | grep "^app/" || ostree --repo="$repo_abs" refs || true)

    if [ -z "$apps" ]; then
        echo -e "${RED}❌ Nenhum dado encontrado no repositório em: $repo_abs${NC}"
        return
    fi

    local total_apps=$(echo "$apps" | wc -l)
    echo -ne "${CYAN}🔍 Escaneando metadados de $total_apps apps com $num_threads threads...${NC} "

    local tmp_alertas="/tmp/alertas_deps.tmp"
    > "$tmp_alertas"

    # --- EXECUÇÃO EM PARALELO ---
    (
        # Exporta para as threads do xargs
        export repo_abs alvo
        
        echo "$apps" | xargs -P "$num_threads" -I {} bash -c '
            ref="$1"
            # Extrai apenas os metadados brutos (chave=valor)
            metadata=$(ostree --repo="$repo_abs" show --metadata "$ref" 2>/dev/null || true)
            
            # Filtra se a runtime ou sdk bate com o filtro de "lixo"
            conflicts=$(echo "$metadata" | grep -iE "runtime=|sdk=" | grep -E "$alvo" || true)
            
            if [ ! -z "$conflicts" ]; then
                # Pega o nome do App (segundo campo da ref app/NOME/ARCH/BRANCH)
                app_name=$(echo "$ref" | cut -d/ -f2)
                # Extrai a versão problemática
                ver=$(echo "$conflicts" | grep -oE "[0-9]+\.[0-9]+" | grep -E "$alvo" | head -1)
                echo "$app_name|$ver"
            fi
        ' -- {} >> "$tmp_alertas"
    ) &
    
    local pid_deps=$!
    spinner $pid_deps
    wait $pid_deps

    # --- EXIBIÇÃO DOS RESULTADOS ---
    echo -e "\r${CYAN}📊 RESULTADO DA ANÁLISE DE APPS:                         ${NC}"
    
    if [ ! -s "$tmp_alertas" ]; then
        echo -e "${GREEN}✅ Sucesso! Todos os $total_apps apps estão em conformidade.${NC}"
    else
        echo "----------------------------------------------------------"
        echo -e "${RED}⚠️  APPS QUE DEPENDEM DO FILTRO ($alvo):${NC}"
        # Ordena e remove duplicados para uma lista limpa
        sort -u "$tmp_alertas" | while IFS="|" read -r app runtime; do
            [ -z "$app" ] && continue
            printf "   ${RED}✖${NC} %-35s -> Versão: ${YELLOW}%s${NC}\n" "$app" "$runtime"
        done
        echo "----------------------------------------------------------"
        echo -e "${RED}📢 AVISO:${NC} Estes apps dependem de runtimes que você marcou para ignorar."
    fi
    rm -f "$tmp_alertas"
}

# ========= MENU PRINCIPAL =========
main() {
    header
    echo -e "O que você deseja verificar hoje?"
    echo -e "1) 🏥 Integridade Física (Procurar arquivos corrompidos)"
    echo -e "2) 🔗 Dependências de Pacotes (Verificar apps faltando dependências)"
    echo -e "3) 🧪 Auditoria Completa (Opção 1 + Opção 2)"
    echo -e "4) 🚪 Sair"
    echo -e "----------------------------------------------------------"
    read -p "Opção: " escolha

    case $escolha in
        1) run_integrity ;;
        2) run_dependencies ;;
        3) run_integrity && run_dependencies ;;
        4) exit 0 ;;
        *) echo -e "${RED}Opção inválida!${NC}" && sleep 1 && main ;;
    esac

    echo -e "\n${CYAN}Auditoria finalizada.${NC}"
}

main