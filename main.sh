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

# ========= 1. CARREGAR CONFIGURAÇÕES PRÉVIAS =========
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

    {
        echo "# Arquivo Gerado Automaticamente - $(date)"
        echo "RAIZ=\"$RAIZ\""
        echo "DESTINO_SYNC=\"${DESTINO_SYNC:-}\""
        echo "MAX_ALLOWED_GB=\"$MAX_ALLOWED_GB\""
        echo "FILTRO_IGNORAR=\"$FILTRO_IGNORAR\""
        echo "LANG_FILTER=\"$LANG_FILTER\""
        echo "THREADS=\"$THREADS\""
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "FORCAR_LOCAL=\"${FORCAR_LOCAL:-false}\""
    } > "$CONFIG_FILE"

    # Gerador de Instalador simplificado para os clientes
    {
        echo "#!/bin/bash"
        echo "SERVER_IP=\"$SERVER_IP\""
        cat << 'EOF'
echo "🔧 Configurando repositório local..."
sudo flatpak remote-add --if-not-exists --no-gpg-verify local-master "http://$SERVER_IP:8080"
sudo flatpak remote-modify --priority=99 local-master
echo "✅ Concluído!"
EOF
    } > "$client_script"
    chmod +x "$client_script"
}

# ========= 4. CONFIGURAÇÃO INTERATIVA =========
ask_configs() {
    echo -e "${YELLOW}=== CONFIGURAÇÃO DO ESPELHO FLATPAK ===${NC}"
    
    local def_raiz=${RAIZ:-/home/gustavo/Flatpak}
    read -p "📂 Pasta de Trabalho (Download) [$def_raiz]: " input_raiz
    RAIZ=${input_raiz:-$def_raiz}
    mkdir -p "$RAIZ"

    local def_limit=${MAX_ALLOWED_GB:-50}
    read -p "🛑 Limite total de armazenamento (GB) [$def_limit]: " input_limit
    MAX_ALLOWED_GB=${input_limit:-$def_limit}

    local def_dest=${DESTINO_SYNC:-/home/gustavo/DISCOS/DISCO1}
    read -p "💿 Pasta de Destino (Sincronização) [$def_dest]: " input_dest
    DESTINO_SYNC=${input_dest:-$def_dest}

    local def_threads=${THREADS:-4}
    read -p "⚡ Threads [$def_threads]: " input_threads
    THREADS=${input_threads:-$def_threads}

    FILTRO_IGNORAR=${FILTRO_IGNORAR:-"(Debug|Sources)"}
    LANG_FILTER=${LANG_FILTER:-"(\.pt|pt_BR|pt-BR)"}
    FORCAR_LOCAL=${FORCAR_LOCAL:-"false"}

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
        sleep 2
    done
}

# ========= 6. PROCESSO DE DOWNLOAD =========
pull_item() {
    local ref="$1"
    local slot=${PARALLEL_SEQ:-1}
    local thread_file="$LOG_DIR/thread_$slot.txt"

    # 1. CÁLCULO DE ESPAÇO REAL (Soma Master + Discos Extras)
    local total_kb=$(du -s "$RAIZ" 2>/dev/null | cut -f1 || echo 0)
    
    # DISCO_PATHS é exportada pela main() contendo os caminhos dos HDs
    for d in ${DISCO_PATHS:-}; do
        if [ -d "$d" ]; then
            local disco_kb=$(du -s "$d" 2>/dev/null | cut -f1 || echo 0)
            total_kb=$((total_kb + disco_kb))
        fi
    done

    local total_gb=$((total_kb / 1024 / 1024))

    # 2. TRAVA DE SEGURANÇA
    if [ "$total_gb" -ge "${MAX_ALLOWED_GB:-1}" ]; then
        echo "🛑 LIMITE ATINGIDO!" > "$thread_file"
        touch "$LOG_DIR/STOP_ALL"
        return 1
    fi

    # 3. PROCESSO DE DOWNLOAD
    [ -f "$LOG_DIR/STOP_ALL" ] && return 1
    echo "⬇️ Baixando: ${ref: -30}" > "$thread_file"

    if ostree pull --repo="$REPO_MASTER" flathub "$ref" --depth=1 >/dev/null 2>&1; then
        inc_progress
        echo "✅ OK: ${ref: -30}" > "$thread_file"
        return 0
    else
        inc_progress
        echo "❌ ERRO: ${ref: -30}" > "$thread_file"
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

    # 1. Definição de Pastas
    REPO_MASTER="$RAIZ/ostree-repo-full"
    LOG_DIR="$RAIZ/logs"
    mkdir -p "$LOG_DIR"

    # --- AUTO-RESET ---
    echo -e "${YELLOW}🧹 Preparando ambiente...${NC}"
    rm -f "$LOG_DIR/STOP_ALL"  
    rm -f "$LOG_DIR/thread_*.txt" 
    echo "0" > "$LOG_DIR/progress.count"

    # 2. Arquivos Temporários para a Peneira
    local all="$LOG_DIR/all.txt"
    local filtered_tmp="$LOG_DIR/filtered.tmp"
    local filtered="$LOG_DIR/filtered.txt"
    local final="$LOG_DIR/prioritized.txt"

    echo -e "${BLUE}🔄 Coletando e Filtrando lista do Flathub (Padrão Sarzedo)...${NC}"
    
    # ETAPA 1: Pega a lista bruta
    flatpak remote-ls --system flathub --all --columns=ref > "$all"
    
    # ETAPA 2: Remove lixo técnico (Debug/Sources)
    grep -vE "${FILTRO_IGNORAR:-"(Debug|Sources)"}" "$all" > "$filtered_tmp"
    
    # ETAPA 3: A PENEIRA DE IDIOMAS (O que você tinha antes)
    # Primeiro: Pega tudo que NÃO é Locale (os Apps e Runtimes em si)
    grep -v "Locale" "$filtered_tmp" > "$filtered" || true
    
    # Segundo: Pega APENAS os Locales que batem com o seu filtro PT/EN e joga no bolo
    grep -E "Locale.*${LANG_FILTER:-"(\.pt|pt_BR|pt-BR|\.en|en_US|en_GB)"}" "$filtered_tmp" >> "$filtered" || true
    
    # ETAPA 4: Organização Final
    sort -u "$filtered" -o "$filtered"
    
    # Prioriza Runtimes (base) antes dos Apps
    grep "^runtime/" "$filtered" > "$final" || true
    grep "^app/" "$filtered" >> "$final" || true
    
    local TOTAL=$(wc -l < "$final")
    echo -e "${GREEN}✅ Lista pronta com $TOTAL itens filtrados.${NC}"

    # 3. Inicializa Repo Master
    if [ ! -d "$REPO_MASTER/objects" ]; then
        ostree init --repo="$REPO_MASTER" --mode=archive-z2
        ostree remote add --repo="$REPO_MASTER" flathub "https://dl.flathub.org/repo/" --set=gpg-verify=false
    fi

    # 4. Dashboard e Execução Paralela
    show_progress "$TOTAL" "$THREADS" &
    DASH_PID=$!
    
    # Exporta variáveis para o GNU Parallel
    export MAX_ALLOWED_GB REPO_MASTER LOG_DIR RAIZ
    # Aqui passamos os caminhos dos discos para o pull_item calcular o espaço total
    export DISCO_PATHS="${!DISCO_LIMITS[@]}" 

    parallel -j "$THREADS" \
             --env REPO_MASTER --env LOG_DIR --env MAX_ALLOWED_GB --env RAIZ --env DISCO_PATHS \
             pull_item :::: "$final"

    # Finalização
    kill $DASH_PID 2>/dev/null || true
    
    echo -e "${YELLOW}🧹 Removendo referências incompletas para limpar o índice...${NC}"
    ostree fsck --repo="$REPO_MASTER" --delete-corrupted-refs --shallow > /dev/null 2>&1 || true

    echo -e "${BLUE}🔄 Gerando índice apenas do que temos em disco...${NC}"
    ostree summary -u --repo="$REPO_MASTER"

    # Sincroniza para o DISCO1 (Sarzedo) com a marretada de refs que funciona
    sync_to_destination
    
    save_config
    echo -e "\n${YELLOW}✅ PROCESSO FINALIZADO COM SUCESSO!${NC}"
}

main