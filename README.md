# 🚀 Flatpak Local Mirror Manager

Este ecossistema de scripts foi desenvolvido para criar um espelho (mirror) local do Flathub. Ele permite baixar aplicações Flatpak uma única vez da internet e distribuí-las para vários computadores em uma rede local (LAN), economizando largura de banda e acelerando instalações em até 100x.

**Cenário Ideal:** Lares ou escritórios com múltiplos PCs Linux (Zorin OS, Mint, Ubuntu) e conexões de internet limitadas ou que desejam performance máxima na rede interna.

## 📦 O que é o Flatpak?
O Flatpak é o padrão moderno de distribuição de apps no Linux. Ao contrário dos pacotes tradicionais (.deb ou .rpm), o Flatpak isola o aplicativo do sistema principal (sandbox), trazendo todas as dependências necessárias para rodar o software dentro de um "container".

**Por que o Mirror Local é necessário?**  
Embora revolucionários, os apps Flatpak podem ser grandes (centenas de MBs). Em uma casa com 3 ou 4 computadores, baixar o mesmo navegador ou suíte de escritório em todos eles é um desperdício de tempo e franquia de dados.  

O Mirror Local resolve isso transformando um PC da sua casa em um "servidor de cache" inteligente.

---

## 📋 Sumário
- [🌟 Benefícios](#-benefícios)
- [📂 Estrutura do Projeto](#-estrutura-do-projeto)
- [🚀 Como Instalar e Executar](#-como-instalar-e-executar)
- [🛠️ Descrição dos Scripts](#-descrição-dos-scripts)
- [🔮 Roadmap](#-roadmap)
- [👋 Contato e Créditos](#-contato-e-créditos)

---

## 🌟 Benefícios

| Recurso              | Descrição |
|----------------------|-----------|
| **Economia de Banda** | Baixe o app uma vez, instale em todos os PCs da rede. |
| **Velocidade Giga**   | Instalações na velocidade da LAN (1Gbps ou mais). |
| **Peneira de Idiomas**| Filtra automaticamente apenas PT-BR e EN, economizando GBs. |
| **Modo Direto**       | Baixa os arquivos diretamente no HD Externo, poupando seu SSD. |

---

## 📂 Estrutura do Projeto

- **`config.env`**: O "cérebro". Guarda IPs, caminhos e o limite de espaço em GB.
- **`main.sh`**: O motor. Faz a coleta, aplica a peneira de idiomas e gerencia o download paralelo.
- **`server.sh`**: O distribuidor. Inicia o servidor HTTP para disponibilizar o repositório na rede.
- **`setup_client.sh`**: O conector. Script auto-gerado que configura os outros PCs para usar o seu espelho.

---

## 🚀 Como Instalar e Executar

### 1. Preparação (No Servidor)
Instale as dependências no seu PC principal (Zorin OS/Mint/Ubuntu):
```bash
sudo apt update && sudo apt install flatpak ostree parallel python3 bc tput curl
```

### 2. Configuração e Download
Dê permissão de execução e inicie o assistente:
```bash
chmod +x *.sh
./main.sh
```
**Dica:** Na pergunta "Pasta do Espelho", aponte para o ponto de montagem do seu HD Externo.

### 3. Iniciar a Distribuição
Inicie o servidor para que os outros PCs vejam seus arquivos:
```bash
./server.sh
```

### 4. Configurar os Clientes (PCs dos meninos/outros)
No computador que vai receber os apps, execute o comando gerado pelo main.sh:
```bash
bash <(wget -qO- http://[IP_DO_SERVIDOR]:8080/setup_client.sh)
```

---

## 🛠️ Descrição dos Scripts

### main.sh
Utiliza `ostree` e `parallel` para baixar os pacotes do Flathub em alta velocidade. Possui um Dashboard em tempo real que monitora o progresso e o espaço ocupado no HD. Aplica filtros inteligentes para ignorar versões de Debug, Sources e idiomas desnecessários.

### server.sh
Cria um servidor de arquivos leve (Python HTTP) apontando para o seu repositório no HD. Gerencia o encerramento limpo dos processos ao sair.

---

## 🔮 Roadmap (Futuro)
- [ ] Suporte Multi-Disco: Implementação de lógica para distribuir o repositório entre múltiplos HDs físicos quando o primeiro lotar.
- [ ] Interface Web: Painel simples para ver quais apps já estão "espelhados".
- [ ] Auto-Update: Script agendado para atualizar o mirror nas madrugadas.

---

## 👋 Contato e Créditos
Desenvolvido por **Gustavo Caetano Reis** 🇧🇷

- 📦 [Meu Portfólio no GitHub](https://github.com/gtavinho)
- 💼 [LinkedIn](https://www.linkedin.com/in/gtavinho/)

---

## ⚖️ Licença
Este projeto está sob a licença MIT.