#!/bin/bash
# Verifica se está rodando no bash
if [ -z "$BASH_VERSION" ]; then
    echo "❌ Este script precisa ser executado com bash!"
    echo "👉 Use: bash $0"
    exit 1
fi
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

    # Gera o instalador para os Clientes (Focado no Mirror Único)
    {
        echo "#!/bin/bash"
        echo "SERVER_IP=\"$SERVER_IP\""
        echo "PORT_MASTER=8080"
        echo "ENUM_FLAG=\"$enum_flag\""
        
        cat << 'EOF'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==========================================================${NC}"
echo -e "   🚀 CONFIGURAÇÃO DO MIRROR FLATPAK COMITENERD"
echo -e "${BLUE}==========================================================${NC}"

# 1. PERGUNTA O MODO DE INSTALAÇÃO
echo -e "Como deseja configurar o repositório no seu PC?"
echo -e "1) ${YELLOW}Sistema${NC} (Global - Requer sudo)"
echo -e "2) ${YELLOW}Usuário${NC} (Apenas seu login - Sem sudo)"
read -p "Escolha uma opção [1-2]: " OPC_MODO

case $OPC_MODO in
    1) MODE_FLAG="--system"; SUDO_CMD="sudo"; CACHE_PATH="/var/lib/flatpak/appstream/local-master"; echo -e "\n📡 Modo Sistema selecionado.";;
    *) MODE_FLAG="--user"; SUDO_CMD=""; CACHE_PATH="$HOME/.local/share/flatpak/appstream/local-master"; echo -e "\n📡 Modo Usuário selecionado.";;
esac

# 2. TESTE DE CONEXÃO
echo -e "${BLUE}🔍 Verificando servidor em http://$SERVER_IP:$PORT_MASTER...${NC}"
if ! curl -s --connect-timeout 3 "http://$SERVER_IP:$PORT_MASTER" > /dev/null; then
    echo -e "${RED}❌ ERRO: Servidor não encontrado!${NC}"
    echo -e "Certifique-se que o computador principal está com o './server.sh' rodando."
    exit 1
fi

# 3. LIMPEZA PROFUNDA (Anti-Cache)
echo -ne "🧹 Limpando configurações e caches antigos... "
$SUDO_CMD flatpak remote-delete $MODE_FLAG local-master --force 2>/dev/null || true
$SUDO_CMD rm -rf "$CACHE_PATH" 2>/dev/null
echo -e "${GREEN}OK${NC}"

# 4. CONFIGURAR O REPOSITÓRIO
echo -e "⭐ Conectando ao Mirror Local (local-master)..."
REPO_URL="http://$SERVER_IP:$PORT_MASTER/ostree-repo-full"

if $SUDO_CMD flatpak remote-add $MODE_FLAG --if-not-exists --no-gpg-verify local-master "$REPO_URL"; then
    
    # 5. AJUSTE DE PRIORIDADES (O SEGREDO DO SUCESSO)
    # No Flatpak, a menor prioridade (1) ganha. 
    echo -ne "🔝 Definindo local-master como favorito... "
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --priority 1 local-master 2>/dev/null || \
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --set priority=1 local-master 2>/dev/null
    
    # Empurra o Flathub e Zorin para o final da fila (99)
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --priority 99 flathub 2>/dev/null || \
    $SUDO_CMD flatpak remote-modify $MODE_FLAG --set priority=99 flathub 2>/dev/null
    echo -e "${GREEN}OK${NC}"
    
    # 6. SINCRONIZAÇÃO DO CATÁLOGO
    echo -e "${BLUE}📦 Sincronizando catálogo de aplicativos (Isso pode demorar alguns segundos)...${NC}"
    $SUDO_CMD flatpak update $MODE_FLAG --appstream local-master -y >/dev/null 2>&1 || true
    
    # Reparo silencioso para evitar refs quebradas
    $SUDO_CMD flatpak repair $MODE_FLAG >/dev/null 2>&1 || true
    
    # Ajuste de Visibilidade (Enumeration)
    if [ -n "$ENUM_FLAG" ]; then
        $SUDO_CMD flatpak remote-modify $MODE_FLAG $ENUM_FLAG local-master 2>/dev/null || true
    fi

    echo -e "\n${GREEN}✅ TUDO PRONTO! SEU PC ESTÁ CONECTADO AO COMITENERD.${NC}"
    echo -e "----------------------------------------------------------"
    echo -e "💻 Comando para testar: ${YELLOW}flatpak remote-ls local-master${NC}"
    echo -e "🚗 ${BLUE}ComiteNerd Tech: Tecnologia robusta, mesmo offline!${NC}"
    echo -e "----------------------------------------------------------"

    # [NOVO] Tenta abrir a vitrine no navegador se houver interface gráfica
    if command -v xdg-open > /dev/null && [ -n "$DISPLAY" ]; then
        echo -e "🚀 Abrindo a vitrine de aplicativos... "
        # Se for root, tenta abrir como o usuário que está na sessão atual
        if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
            (sleep 2 && sudo -u "$SUDO_USER" xdg-open "http://$SERVER_IP:8080/index.html") &
        else
            (sleep 2 && xdg-open "http://$SERVER_IP:8080/index.html") &
        fi
    else
        echo -e "💡 Acesse a vitrine manualmente em: ${CYAN}http://$SERVER_IP:8080/index.html${NC}"
    fi
else
    echo -e "${RED}❌ FALHA CRÍTICA: Não foi possível adicionar o repositório.${NC}"
    exit 1
fi
echo -e "${BLUE}==========================================================${NC}"
EOF
    } > "$client_script"
    
    chmod +x "$client_script"
    echo -e "${GREEN}✅ Script de instalação para os clientes gerado em: $client_script${NC}"
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

    # 4.5 Filtro de Palavras-Chave (Novo!)
    local def_keys=${KEYWORD_FILTER:-".*"} # ".*" significa "trazer tudo" por padrão
    echo -e "\n🔍 ${CYAN}Filtro de Busca (Palavras-Chave):${NC}"
    echo "Exemplo: firefox|chrome|vlc|libreoffice"
    echo "(Deixe em branco ou use .* para baixar tudo)"
    read -p "🔎 Buscar por [$def_keys]: " input_keys
    KEYWORD_FILTER=${input_keys:-$def_keys}
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
    local lockfile="$LOG_DIR/progress.lock"

    (
        flock -x 200

        local val=$(cat "$file" 2>/dev/null || echo 0)
        val=${val//[^0-9]/}   # limpa lixo
        
        echo $((val + 1)) > "$file"

    ) 200>"$lockfile"
}

get_progress() { cat "$LOG_DIR/progress.count" 2>/dev/null || echo 0; }

# ======== Funcao para falhas ==============

inc_fail() {
    local file="$LOG_DIR/fail.count"
    local lock="$LOG_DIR/fail.lock"

    (
        flock -x 200
        local val=$(cat "$file" 2>/dev/null || echo 0)
        val=${val//[^0-9]/}
        echo $((val + 1)) > "$file"
    ) 200>"$lock"
}
export -f inc_fail

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
        echo -e "   🚀 FLATPAK MIRROR MANAGER | v1.1"
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
    
    # Garante que o slot seja calculado corretamente (THREADS precisa estar exportada)
    local slot=$(( (PARALLEL_SEQ - 1) % ${THREADS:-4} + 1 ))
    
    # Usar caminhos absolutos evita que o log suma no limbo
    local thread_file="${LOG_DIR}/thread_${slot}.txt"
    local error_log="${LOG_DIR}/falhas_download.log"

    if ostree rev-parse --repo="$REPO_MASTER" "flathub:$ref" >/dev/null 2>&1; then
        echo "⏭️ Já existe: ${ref: -30}" > "$thread_file"
        inc_progress
        return 0
    fi

    echo "⬇️ Baixando: ${ref: -35}" > "$thread_file"

    local current_kb=$(du -s "$RAIZ" 2>/dev/null | cut -f1 || echo 0)
    local current_gb=$((current_kb / 1024 / 1024))

    if [ "$current_gb" -ge "$MAX_ALLOWED_GB" ]; then
        echo "🛑 DISCO CHEIO!" > "$thread_file"
        touch "${LOG_DIR}/ERRO_ESPACO"
        return 0 
    fi

    # Tenta o download
    if ostree pull --repo="$REPO_MASTER" flathub "$ref" --depth=1 >/dev/null 2>&1; then
        inc_progress
        echo "✅ Concluído: ${ref: -30}" > "$thread_file"
        return 0
    else
        # AGORA VAI: Forçamos a escrita e um 'sync' para garantir que o dado vá para o HD
        echo "❌ PULADO (ERRO): ${ref: -25}" > "$thread_file"
        echo "[$(date '+%H:%M:%S')] FALHA: $ref" >> "$error_log"
        inc_fail
        sync "$error_log" # Garante a gravação física no disco
        return 0
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
    export MAX_ALLOWED_GB REPO_MASTER LOG_DIR RAIZ FORCAR_LOCAL LANG_FILTER THREADS

    # --- AUTO-RESET DE LOGS ---
    echo -e "${YELLOW}🧹 Preparando ambiente...${NC}"
    rm -f "$LOG_DIR/STOP_ALL" "$LOG_DIR/ERRO_ESPACO"
    rm -f "$LOG_DIR/thread_*.txt"
    rm -f "$LOG_DIR/falhas_download.log"
    echo "0" > "$LOG_DIR/progress.count"
    echo "0" > "$LOG_DIR/fail.count"


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

    # --- A PENEIRA DE ComiteNerd (VERSÃO FILTRO TOTAL) ---
    local busca="${KEYWORD_FILTER:-.*}"
    echo -e "${BLUE}🔍 Filtrando rigorosamente por: '$busca'...${NC}"

    # 1. Filtra a lista bruta APENAS pelo que você buscou (ex: vlc)
    # Isso já elimina 90% do que você não quer
    if ! grep -iE "$busca" "$all" > "$filtered"; then
        echo -e "${RED}❌ Nenhum resultado para o filtro!${NC}"
    fi

    # 2. Agora, desse resultado, removemos o lixo (Debug e Sources)
    grep -vE "${FILTRO_IGNORAR:-"Debug|Sources"}" "$filtered" > "$final" || true
    
    # 3. Filtro de Idiomas (Opcional, mas ajuda a limpar Locales de outros idiomas)
    # Se quiser ser ainda mais rigoroso com os Locales do VLC:
    awk -v lang="${LANG_FILTER:-pt_BR|pt-BR|pt}" "
    /Locale/ {
        if (\$0 ~ lang) print
        next
    }
    { print }
    " "$final" > "$filtered"

    # 4. Organização Final
    sort -u "$filtered" -o "$final"
    
    local TOTAL=$(wc -l < "$final")
    echo -e "${GREEN}✅ Lista ComiteNerd pronta com $TOTAL itens (Busca: $busca).${NC}"

    # 4. Dashboard e Execução Paralela
    if [ "$TOTAL" -gt 0 ]; then
        show_progress "$TOTAL" "$THREADS" &
        DASH_PID=$!
        
        # Pull Direto no HD
        parallel --halt never -j "$THREADS" \
                 --env REPO_MASTER --env LOG_DIR --env MAX_ALLOWED_GB --env RAIZ \
                 pull_item :::: "$final" || true

        trap "kill $DASH_PID 2>/dev/null" EXIT
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
    FAILS=$(cat "$LOG_DIR/fail.count" 2>/dev/null || echo 0)
    if [ "$FAILS" -gt 0 ]; then
        echo -e "\n${YELLOW}⚠️ Finalizado com $FAILS falhas!${NC}"
    else
        echo -e "\n${GREEN}✅ Tudo baixado com sucesso!${NC}"
    fi
}

main