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

# Sempre cria o array primeiro (garantido)
declare -g -A DISCO_LIMITS=()

# Depois carrega config (se existir)
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ========= 2. VERIFICAÇÃO DE DEPENDÊNCIAS =========
check_deps() {
    echo -e "${BLUE}🔍 Verificando dependências...${NC}"
    local deps=("ostree" "flatpak" "parallel" "bc" "du" "grep" "tput" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}❌ Erro: '$dep' não está instalado.${NC}"
            exit 1
        fi
    done
}

# ========= 3. PERSISTÊNCIA (SALVAR CONFIG) =========
save_config() {
    local current_ip=$(hostname -I | awk '{print $1}')
    SERVER_IP=${current_ip:-"127.0.0.1"}
    REPO_MASTER="$RAIZ/ostree-repo-full"
    mkdir -p "$REPO_MASTER"
    
    local client_script="$REPO_MASTER/setup_client.sh"

    # Salva o arquivo de configuração do Mirror
   {
        echo "# Arquivo Gerado Automaticamente - $(date)"
        echo "RAIZ=\"$RAIZ\""
        echo "MAX_ALLOWED_GB=\"$MAX_ALLOWED_GB\""
        echo "FILTRO_IGNORAR=\"$FILTRO_IGNORAR\""
        echo "LANG_FILTER=\"$LANG_FILTER\""
        echo "THREADS=\"$THREADS\""
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "FORCAR_LOCAL=\"${FORCAR_LOCAL:-false}\""
        
        # --- A MÁGICA DOS DISCOS ---
        # Verifica se o array tem conteúdo antes de tentar percorrer
        if [ ${#DISCO_LIMITS[@]} -gt 0 ]; then
            for d in "${!DISCO_LIMITS[@]}"; do
                # Grava a linha formatada para o config.env
                echo "DISCO_LIMITS[\"$d\"]=\"${DISCO_LIMITS[$d]}\""
            done
        fi
    } > "$CONFIG_FILE"

    # Define a flag de visibilidade para o Flatpak
    # Se FORCAR_LOCAL for true, --no-enumerate=false (aparece sempre)
    # Se for false, --no-enumerate=true (esconde se estiver offline/lento)
    local enum_flag="true"
    [[ "$FORCAR_LOCAL" == "true" ]] && enum_flag="false"

    # Gerador de Instalador Robusto para os Clientes (PCs dos meninos)
    {
        echo "#!/bin/bash"
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "ENUM_FLAG=\"$enum_flag\""
        cat << 'EOF'
echo "==========================================="
echo "  🔧 CONFIGURANDO REPOSITÓRIO LOCAL"
echo "==========================================="

# 1. Adiciona o remoto
sudo flatpak remote-add --if-not-exists --no-gpg-verify local-master "http://$SERVER_IP:8080"

# 2. Configura Prioridade e Visibilidade
# --no-enumerate=false força a exibição na Gnome Software/Discover
sudo flatpak remote-modify --priority=99 --no-enumerate=$ENUM_FLAG local-master

echo "✅ Concluído! O PC agora prioriza o Mirror Local."
echo "URL: http://$SERVER_IP:8080"
echo "==========================================="
EOF
    } > "$client_script"
    chmod +x "$client_script"
}

## ========= FUNÇÃO DE CONFIGURAÇÃO DE DISCOS EXTRAS =========
configure_disks_loop() {
    echo -e "\n${BLUE}💿 Configuração do Disco de Destino (HD Externo)${NC}"
    
    # Pega o primeiro disco já salvo (se existir) para sugerir como padrão
    local disco_atual=""
    local gb_atual="50"
    
    if [ ${#DISCO_LIMITS[@]} -gt 0 ]; then
        disco_atual="${!DISCO_LIMITS[@]}"
        gb_atual="${DISCO_LIMITS[$disco_atual]}"
        echo -e "${YELLOW}ℹ️  HD atual: $disco_atual ($gb_atual GB)${NC}"
    fi

    echo "Insira o caminho do HD (Exemplo: /home/$(whoami)/DISCOS/DISCO1)"
    read -p "📍 Caminho do Disco [${disco_atual:-Pular}]: " d_path
    
    # Se der Enter e já existir um, mantém. Se não existir, pula.
    d_path=${d_path:-$disco_atual}
    
    if [ -n "$d_path" ]; then
        if [ -d "$d_path" ]; then
            read -p "📏 Limite de GB para este HD [$gb_atual]: " input_gb
            local d_gb=$(echo "$input_gb" | tr -dc '0-9')
            d_gb=${d_gb:-$gb_atual}

            # Limpa o array e adiciona APENAS este disco
            unset DISCO_LIMITS
            declare -g -A DISCO_LIMITS
            DISCO_LIMITS["$d_path"]=$d_gb
            
            echo -e "${GREEN}✅ HD Configurado: $d_path ($d_gb GB)${NC}"
        else
            echo -e "${RED}❌ Caminho não encontrado! O HD está montado?${NC}"
            # Opcional: Se errar, podemos limpar para não usar caminho fantasma
            unset DISCO_LIMITS
            declare -g -A DISCO_LIMITS
        fi
    else
        echo -e "${YELLOW}⚠️  Nenhum HD extra configurado. Usando apenas a Pasta Raiz.${NC}"
        unset DISCO_LIMITS
        declare -g -A DISCO_LIMITS
    fi
}

# ========= 4. CONFIGURAÇÃO INTERATIVA =========
ask_configs() {
    echo -e "${YELLOW}=== CONFIGURAÇÃO DO ESPELHO FLATPAK (MODO DIRETO) ===${NC}"
    
    # Pega o usuário logado
    local user=$(whoami)
    
    # Sugere a pasta Raiz DIRETAMENTE no seu HD de ComiteNerd (ou onde você preferir)
    local def_raiz=${RAIZ:-/media/$user/DISCO1/Flatpak_Mirror}
    read -p "📂 Onde salvar o Espelho (HD Externo) [$def_raiz]: " input_raiz
    RAIZ=${input_raiz:-$def_raiz}
    mkdir -p "$RAIZ"

    # Agora o limite é baseado apenas nesta pasta
    local def_max=${MAX_ALLOWED_GB:-100}
    read -p "⚖️ Limite de Espaço no HD (GB) [${def_max}GB]: " input_max
    MAX_ALLOWED_GB=${input_max:-$def_max}
    # ------------------------------
    # Filtro Ignorar
    local def_ignore=${FILTRO_IGNORAR:-"(Debug|Sources)"}
    read -p "🚫 Ignorar (Regex) [$def_ignore]: " input_ignore
    FILTRO_IGNORAR=${input_ignore:-$def_ignore}

    # Idiomas (RESTAURADO)
    local def_lang=${LANG_FILTER:-"(\.pt|pt_BR|pt-BR|\.en|en_US|en_GB)"}
    read -p "🌎 Idiomas (Regex) [$def_lang]: " input_lang
    LANG_FILTER=${input_lang:-$def_lang}

    # Threads
    local def_threads=${THREADS:-4}
    read -p "⚡ Threads [$def_threads]: " input_threads
    THREADS=${input_threads:-$def_threads}

    # Calcula e mostra o total somado para conferência
    local total_cfg=0
    for d in "${!DISCO_LIMITS[@]}"; do total_cfg=$((total_cfg + DISCO_LIMITS[$d])); done
    echo -e "${CYAN}📦 Total de armazenamento configurado: ${total_cfg}GB${NC}"

    # --- VISIBILIDADE DA LOJA (RESTAURADO) ---
    echo -e "\n${YELLOW}🛠️  Visibilidade da Loja:${NC}"
    echo "Deseja forçar os clientes a aguardarem o sincronismo com a loja local?"
    echo "  [s] Sim: Apps locais aparecem sempre (mesmo offline)."
    echo "  [n] Não: Pula para internet se o servidor cair (Recomendado)."
    read -p "Escolha (s/n) [n]: " input_enum
    if [[ "$input_enum" =~ ^[Ss]$ ]]; then 
        FORCAR_LOCAL="true" 
    else 
        FORCAR_LOCAL="false" 
    fi

    save_config
}

# ========= 5. FUNÇÕES DE APOIO E DASHBOARD =========
inc_progress() {
    local file="$LOG_DIR/progress.count"
    echo $(( $(cat "$file" 2>/dev/null || echo 0) + 1 )) > "$file"
}

get_progress() { cat "$LOG_DIR/progress.count" 2>/dev/null || echo 0; }

show_progress() {
    local total="$1"
    local num_threads="$2"
    local start_time=$(date +%s)
    clear
    while true; do
        local done=$(get_progress)
        local root_size=$(du -sh "$RAIZ" 2>/dev/null | cut -f1 || echo "0B")
        local now=$(date +%s)
        local elapsed=$((now - start_time))
        
        tput cup 0 0
        echo -e "${BLUE}==========================================================${NC}"
        echo -e "   🚀 FLATPAK MIRROR MANAGER | v1.0"
        echo -e "${BLUE}==========================================================${NC}"
        echo -e "📊 Progresso: $done / $total | ⏱️ Ativo: ${elapsed}s"
        echo -e "📂 Espaço em uso (Trabalho): ${YELLOW}$root_size${NC} / ${MAX_ALLOWED_GB}GB"
        echo -e "----------------------------------------------------------"
        for i in $(seq 1 "$num_threads"); do
            local task=$(cat "$LOG_DIR/thread_$i.txt" 2>/dev/null || echo "Aguardando...")
            printf "  [Slot %2d]: %-50s\n" "$i" "${task:0:50}"
        done
        echo -e "${BLUE}==========================================================${NC}"
        sleep 1
    done
}

# ========= 6. PROCESSO DE DOWNLOAD =========
pull_item() {
    local ref="$1"
    local slot=${PARALLEL_SEQ:-1}
    local thread_file="$LOG_DIR/thread_$slot.txt"

    # 1. ATUALIZA O DASHBOARD IMEDIATAMENTE (Limpa o "Sucesso" anterior)
    # Mostra apenas o final do nome do app para caber na tela
    echo "⬇️ Baixando: ${ref: -35}" > "$thread_file"

    # 2. Cálculo de espaço (Foco na RAIZ/HD)
    local current_kb=$(du -s "$RAIZ" 2>/dev/null | cut -f1 || echo 0)
    local current_gb=$((current_kb / 1024 / 1024))

    # 3. Checagem de Limite
    if [ "$current_gb" -ge "$MAX_ALLOWED_GB" ]; then
        echo "🛑 DISCO CHEIO!" > "$thread_file"
        touch "$LOG_DIR/ERRO_ESPACO"
        return 1 
    fi

    # 4. Execução do Pull Real
    # Redirecionamos o log do ostree para não sujar o dashboard
    if ostree pull --repo="$REPO_MASTER" flathub "$ref" --depth=1 >/dev/null 2>&1; then
        inc_progress
        # Marca como sucesso para o usuário ver que terminou este item
        echo "✅ Concluído: ${ref: -30}" > "$thread_file"
    else
        echo "❌ FALHA: ${ref: -30}" > "$thread_file"
        return 1
    fi
}

export -f pull_item inc_progress

sync_to_destination() {
    if [ -n "${DESTINO_SYNC:-}" ]; then
        echo -e "\n${BLUE}🔄 Sincronizando com o destino: $DESTINO_SYNC...${NC}"
        mkdir -p "$DESTINO_SYNC/refs/heads"
        
        if [ ! -d "$DESTINO_SYNC/objects" ]; then
            ostree init --repo="$DESTINO_SYNC" --mode=archive-z2
        fi

        echo "📦 Transferindo objetos e forçando gravação de refs..."
        
        ostree refs --repo="$REPO_MASTER" | grep "^flathub:" | while read -r remote_ref; do
            local local_ref="${remote_ref#flathub:}"
            local commit_hash=$(ostree rev-parse --repo="$REPO_MASTER" "$remote_ref")
            
            echo -n "   -> $local_ref... "
            
            # 1. Puxa os objetos físicos
            ostree pull-local --repo="$DESTINO_SYNC" "$REPO_MASTER" "$commit_hash" >/dev/null 2>&1
            
            # 2. A MARRETADA: Cria o arquivo da ref na mão (pula o comando ostree refs)
            # O ostree guarda as refs em refs/heads/nome/do/app
            local ref_path="$DESTINO_SYNC/refs/heads/$local_ref"
            mkdir -p "$(dirname "$ref_path")"
            echo "$commit_hash" > "$ref_path"
            
            if [ -f "$ref_path" ]; then
                echo -e "${GREEN}FORÇADO NO DISCO${NC}"
            else
                echo -e "${RED}ERRO DE ESCRITA${NC}"
            fi
        done

        echo -e "${BLUE}🔄 Reconstruindo Summary (Índice)...${NC}"
        # O summary -u lê a pasta refs/heads e monta o índice oficial
        if ostree summary -u --repo="$DESTINO_SYNC"; then
             echo -e "${GREEN}✅ Sincronização concluída com sucesso!${NC}"
        else
             echo -e "${RED}❌ ERRO crítico no Summary.${NC}"
        fi
    fi
}
# ========= 7. MAIN =========
main() {
    check_deps  
    ask_configs

    # 1. Definição de Pastas e Variáveis Globais
    # Agora REPO_MASTER nasce direto dentro do HD que você escolheu na RAIZ
    REPO_MASTER="$RAIZ/ostree-repo-full"
    LOG_DIR="$RAIZ/logs"
    mkdir -p "$LOG_DIR"
    mkdir -p "$REPO_MASTER"

    # Exportamos apenas o necessário para o Parallel
    # Removi DISCO_PATHS pois agora o pull_item só olha para RAIZ
    export MAX_ALLOWED_GB REPO_MASTER LOG_DIR RAIZ FORCAR_LOCAL LANG_FILTER

    # --- AUTO-RESET DE LOGS ---
    echo -e "${YELLOW}🧹 Preparando ambiente...${NC}"
    rm -f "$LOG_DIR/STOP_ALL" "$LOG_DIR/ERRO_ESPACO"
    rm -f "$LOG_DIR/thread_*.txt" 
    echo "0" > "$LOG_DIR/progress.count"

    # 2. Arquivos Temporários para a Peneira
    local all="$LOG_DIR/all.txt"
    local filtered="$LOG_DIR/filtered.txt"
    local final="$LOG_DIR/prioritized.txt"

    # 3. Inicializa Repo Master (No HD de Destino)
    if [ ! -d "$REPO_MASTER/objects" ]; then
        echo -e "${BLUE}📦 Inicializando repositório Ostree no HD...${NC}"
        ostree init --repo="$REPO_MASTER" --mode=archive-z2
        ostree remote add --repo="$REPO_MASTER" flathub "https://dl.flathub.org/repo/" --set=gpg-verify=false
    fi

    echo -e "${BLUE}🔄 Coletando e Filtrando lista do Flathub...${NC}"
    
    # Coleta robusta (Tenta ostree, senão flatpak)
    ostree remote-ls flathub --repo="$REPO_MASTER" --all --columns=ref > "$all" 2>/dev/null || \
    flatpak remote-ls --system flathub --all --columns=ref > "$all"

    # --- A PENEIRA DE ComiteNerd ---
    grep -vE "(${FILTRO_IGNORAR:-"Debug|Sources"}|Locale)" "$all" > "$filtered" || true
    grep "Locale" "$all" | grep -iE "${LANG_FILTER:-"pt_BR|pt-BR|pt"}" >> "$filtered" || true
    
    sort -u "$filtered" -o "$filtered"
    grep "^runtime/" "$filtered" > "$final" || true
    grep "^app/" "$filtered" >> "$final" || true
    
    local TOTAL=$(wc -l < "$final")
    echo -e "${GREEN}✅ Lista pronta com $TOTAL itens filtrados.${NC}"

    # 4. Dashboard e Execução Paralela
    if [ "$TOTAL" -gt 0 ]; then
        show_progress "$TOTAL" "$THREADS" &
        DASH_PID=$!
        
        # Pull Direto no HD
        parallel --halt now,fail=1 -j "$THREADS" \
                 --env REPO_MASTER --env LOG_DIR --env MAX_ALLOWED_GB --env RAIZ \
                 pull_item :::: "$final" || true

        kill $DASH_PID 2>/dev/null || true
    else
        echo -e "${RED}❌ Erro: Nenhum app encontrado!${NC}"
        exit 1
    fi
    
    # 5. Tratamento de Erro de Espaço
    if [ -f "$LOG_DIR/ERRO_ESPACO" ]; then
        echo -e "\n${RED}🛑 LIMITE DE ESPAÇO ATINGIDO NO HD!${NC}"
    fi

    # 6. Finalização
    echo -e "${BLUE}🔄 Atualizando Índice (Summary)...${NC}"
    ostree summary -u --repo="$REPO_MASTER"

    # Removido sync_to_destination (Já estamos no destino!)
    
    # Salva o config.env para a próxima vez
    save_config
    
    echo -e "\n${YELLOW}✅ PROCESSO FINALIZADO COM SUCESSO!${NC}"
}

main