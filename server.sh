#!/bin/bash

# Verifica se está rodando no bash
if [ -z "$BASH_VERSION" ]; then
    echo "❌ Este script precisa ser executado com bash!"
    echo "👉 Use: bash $0"
    exit 1
fi

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
echo -e "   🌐 SERVIDOR FLATPAK LOCAL - ComiteNerd"
echo -e "   📍 IP do Servidor: ${CYAN}$SERVER_IP${NC}"
echo -e "${BLUE}==========================================================${NC}"

# 1. FUNÇÃO PARA GERAR A VITRINE WEB (INDEX.HTML)
generate_web_index() {
    local repo_path="$1"
    local output_html="$RAIZ/index.html"
    
    echo -ne "🌐 Gerando Vitrine Web em $(basename "$RAIZ")... "
    
    cat <<EOF > "$output_html"
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ComiteNerd - Vitrine Flatpak</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background-color: #121212; color: #e0e0e0; margin: 0; padding: 20px; }
        .container { max-width: 1000px; margin: auto; background: #1e1e1e; padding: 30px; border-radius: 15px; border: 1px solid #333; }
        h1 { color: #00bcff; text-align: center; margin-bottom: 5px; }
        .info { text-align: center; color: #777; margin-bottom: 30px; border-bottom: 1px solid #333; padding-bottom: 15px; }
        .app-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; }
        .app-card { background: #252525; padding: 20px; border-radius: 10px; border-left: 5px solid #00bcff; transition: 0.2s; }
        .app-card:hover { background: #2d2d2d; transform: scale(1.02); }
        .app-name { font-weight: bold; font-size: 1.1em; color: #fff; margin-bottom: 10px; word-break: break-all; }
        .copy-box { background: #000; color: #00ff00; padding: 10px; font-family: monospace; font-size: 0.85em; border-radius: 5px; cursor: pointer; }
        .footer { text-align: center; margin-top: 40px; font-size: 0.8em; color: #444; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 ComiteNerd - Vitrine Offline</h1>
        <p class="info">📍 Servidor: $SERVER_IP | 📦 Repositório: $(basename "$repo_path")</p>
        <div class="app-grid">
EOF

    # Extrai apps e gera os cards
    ostree refs --repo="$repo_path" | grep "app/" | cut -d'/' -f2 | sort -u | while read -r app_id; do
        cat <<EOF >> "$output_html"
            <div class="app-card">
                <div class="app-name">$app_id</div>
                <div class="copy-box" onclick="navigator.clipboard.writeText('sudo flatpak install local-master $app_id')">
                    sudo flatpak install local-master $app_id
                </div>
            </div>
EOF
    done

    cat <<EOF >> "$output_html"
        </div>
        <div class="footer">🚗 ComiteNerd Tech - Repositório Offline de 750GB</div>
    </div>
</body>
</html>
EOF
    echo -e "${GREEN}OK${NC}"
}

# 2. FUNÇÃO PARA PREPARAR O REPOSITÓRIO
prepare_repo() {
    local repo_path="$1"
    if [ -d "$repo_path/objects" ]; then
        echo -ne "🛠️  Sincronizando $repo_path... "
        
        # Sincroniza Appstream
        if [ -d "$repo_path/refs/remotes/flathub" ]; then
            mkdir -p "$repo_path/refs/heads/appstream" "$repo_path/refs/heads/appstream2"
            cp -rn "$repo_path/refs/remotes/flathub/appstream/"* "$repo_path/refs/heads/appstream/" 2>/dev/null
            cp -rn "$repo_path/refs/remotes/flathub/appstream2/"* "$repo_path/refs/heads/appstream2/" 2>/dev/null
        fi

        # [TURBO] Sincroniza vitrine de apps (Links Simbólicos)
        if [ -d "$repo_path/refs/remotes/flathub/app" ]; then
            mkdir -p "$repo_path/refs/heads/app"
            cp -rsn "$repo_path/refs/remotes/flathub/app/"* "$repo_path/refs/heads/app/" 2>/dev/null
        fi

        # Gera metadados e Summary FINAL (Importante ser por último)
        flatpak build-update-repo --generate-static-deltas "$repo_path" > /dev/null 2>&1
        ostree summary -u --repo="$repo_path" > /dev/null 2>&1
        
        echo -e "${GREEN}OK${NC}"
        
        # Gera lista de texto
        ostree refs --repo="$repo_path" | grep "app/" | cut -d'/' -f2 | sort -u > "$repo_path/apps_local.txt"
        
        if [[ "$repo_path" == *"$REPO_MASTER"* ]]; then
            generate_web_index "$repo_path"
        fi
    else
        echo -e "${YELLOW}⚠️  Aviso: $(basename "$repo_path") não é um repositório válido.${NC}"
    fi
}

# 3. LIMPAR PROCESSOS ANTIGOS
echo -e "🧹 Limpando servidores anteriores..."
pkill -f "python3 -m http.server" 2>/dev/null || true
sleep 1

# 4. LANÇAR O MASTER
echo -e "${BLUE}🛠️  Preparando Repositório Master...${NC}"
REPO_MASTER="$RAIZ/ostree-repo-full"

if [ -d "$REPO_MASTER" ]; then
    prepare_repo "$REPO_MASTER"
    cp "$REPO_MASTER/apps_local.txt" "$RAIZ/apps_local.txt" 2>/dev/null
else
    prepare_repo "$RAIZ"
fi

echo -ne "📦 Posicionando instalador na vitrine... "
cp "./setup_client.sh" "$RAIZ/setup_client.sh" 2>/dev/null || cp "$REPO_MASTER/setup_client.sh" "$RAIZ/setup_client.sh" 2>/dev/null
echo -e "${GREEN}OK${NC}"

echo -e "🚀 Lançando MASTER em: ${YELLOW}http://$SERVER_IP:8080${NC}"
python3 -m http.server -d "$RAIZ" 8080 > /dev/null 2>&1 &

# 5. LANÇAR DISCOS
PORT=8081
for d in $(printf '%s\n' "${!DISCO_LIMITS[@]}" | sort); do
    if [ -d "$d" ]; then
        prepare_repo "$d"
        cp "./setup_client.sh" "$d/" 2>/dev/null || true
        echo -e "💿 Lançando DISCO [$(basename "$d")] em: ${YELLOW}http://$SERVER_IP:$PORT${NC}"
        python3 -m http.server -d "$d" "$PORT" > /dev/null 2>&1 &
        ((PORT++))
    fi
done

echo -e "\n${GREEN}✅ TODOS OS SERVIDORES ESTÃO ONLINE!${NC}"
echo -e "----------------------------------------------------------"
echo -e "🌐 ${YELLOW}VITRINE WEB:${NC} http://$SERVER_IP:8080/index.html"
echo -e "💻 ${YELLOW}COMANDO PARA OS FILHOS:${NC}"
echo -e "${CYAN}bash <(wget -qO- http://$SERVER_IP:8080/setup_client.sh)${NC}"
echo -e "----------------------------------------------------------"

(sleep 2 && xdg-open "http://$SERVER_IP:8080/index.html") &

trap "echo -e '\n🛑 Encerrando servidores...'; pkill -f 'python3 -m http.server'; exit" INT TERM
wait