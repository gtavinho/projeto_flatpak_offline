# 🚀 Flatpak Local Mirror Manager

Este ecossistema de scripts foi desenvolvido para criar um **espelho (mirror) local do Flathub**. Ele permite baixar aplicações Flatpak uma única vez da internet e distribuí-las para vários computadores em uma rede local (LAN), economizando largura de banda e acelerando instalações.

---

## 📋 Sumário
* [🌟 Benefícios](#-benefícios)
* [📂 Estrutura do Projeto](#-estrutura-do-projeto)
* [🚀 Como Instalar e Executar](#-como-instalar-e-executar)
* [🛠️ Descrição dos Scripts](#-descrição-dos-scripts)

---

## 🌟 Benefícios

| Recurso | Descrição |
| :--- | :--- |
| **Economia de Banda** | Baixe o app uma vez, instale em todos os PCs da casa. |
| **Velocidade Giga** | Instalações na velocidade da rede local (1Gbps). |
| **Resiliência** | Se a internet cair, sua "loja local" continua online. |
| **Multi-Disco** | Distribui dados em vários HDs de forma inteligente. |

---

## 📂 Estrutura do Projeto

* **`config.env`**: O "cérebro". Guarda IPs, caminhos e limites de disco.
* **`main.sh`**: O motor. Baixa do Flathub, filtra idiomas e indexa o repositório.
* **`server.sh`**: O distribuidor. Inicia os servidores HTTP para a rede local.
* **`check.sh`**: O zelador. Garante que os dados não estão corrompidos.
* **`setup_client.sh`**: O conector. Script auto-gerado para configurar os clientes.

---

## 🚀 Como Instalar e Executar

### 1. Preparação (No Servidor)
Instale as dependências necessárias no seu PC principal (Zorin OS/Mint/Ubuntu):
```bash
sudo apt update && sudo apt install flatpak ostree parallel python3 bc tput curl
```

### 2. Configuração e Download
Dê permissão de execução e inicie o download dos pacotes:
```bash
chmod +x *.sh
./main.sh
```

### 3. Iniciar a Distribuição
Abra as portas para que outros computadores vejam seus arquivos:
```bash
./server.sh
```

### 4. Configurar os Clientes (Outros PCs)
No computador que deseja receber os apps, substitua `[IP_DO_SERVIDOR]` pelo IP real do seu PC principal (ex: `192.168.1.100`):
```bash
bash <(wget -qO- http://[IP_DO_SERVIDOR]:8080/setup_client.sh)
```

> Nota: Usamos `bash <(...)` em vez de pipe direto para permitir que o script interaja com o teclado (escolha entre modo Sistema ou Usuário).

🛠️ Descrição Detalhada
main.sh
Consulta o Flathub, filtra idiomas (PT-BR/EN) e baixa tudo via threads paralelas. Ao final, gera um índice (Summary) vital para que os clientes consigam ler o catálogo e cria o instalador cliente atualizado.

server.sh
Inicia instâncias do servidor Python nas portas 8080 (Master) e 8081+ (Discos). Gerencia o encerramento limpo (kill) de todos os processos ao sair com Ctrl+C.

check.sh
Varre os repositórios em busca de erros de integridade. Identifica referências "podres" para que o main.sh as conserte automaticamente no próximo ciclo.

👋 Contato e Créditos
Desenvolvido por Gustavo Caetano Reis — Sarzedo/MG 🇧🇷

[📦 Meu Portfólio no GitHub](https://github.com/gtavinho)

[💼 Conecte-se comigo no LinkedIn](https://www.linkedin.com/in/gtavinho/)

## ⚖️ Licença

Este projeto está sob a licença **MIT**. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

---

## 🛡️ Badges

![License](https://img.shields.io/badge/license-MIT-blue)
![Build](https://img.shields.io/badge/build-passing-brightgreen)
![GitHub Issues](https://img.shields.io/github/issues/gtavinho/projeto_flatpak_offline)