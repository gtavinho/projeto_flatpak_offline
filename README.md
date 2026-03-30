# 🚀 Flatpak Local Mirror Manager (Edição ComiteNerd)

Este ecossistema de scripts transforma seu PC (ou aquele seu **ComiteNerd Tech** com HD de 750GB) em um poderoso **Servidor de Aplicativos Local**. Ele permite baixar aplicações Flatpak uma única vez da internet e distribuí-las para vários computadores em uma rede local (LAN), funcionando até **100% Offline**, economizando largura de banda e acelerando instalações em até 100x.

**Cenário Ideal:** Lares ou escritórios com múltiplos PCs Linux (Zorin OS, Mint, Ubuntu) e conexões de internet limitadas ou que desejam performance máxima na rede interna.

---

## 🏬 A "Loja" ComiteNerd (Vitrine Web)
O grande diferencial desta edição é a **Vitrine Automática**. Ao rodar o servidor, ele gera uma interface visual para que qualquer pessoa na rede possa escolher e instalar apps sem digitar comandos complexos.

* **Navegação Visual:** Veja os ícones e nomes dos apps já espelhados no seu HD.
* **Instalação de Um Clique:** A vitrine gera o comando de instalação exato para o usuário.
* **Auto-Configuração:** Um único comando configura o PC do cliente, limpa caches antigos, ajusta prioridades e abre a loja no navegador.

---

## 🏆 O Diferencial "ComiteNerd"
Diferente de soluções profissionais complexas, este projeto foca na **simplicidade, economia de espaço e interface para o usuário final**:

| Recurso | Outras Soluções | **Este Projeto (ComiteNerd)** |
| :--- | :--- | :--- |
| **Interface** | Logs de texto densos. | **Vitrine Web:** Painel visual para os usuários da rede. |
| **Setup Cliente** | Configuração manual de remotos. | **Um Comando:** Configura prioridades e abre a loja. |
| **Peneira de Dados** | Baixa tudo (Debug/Docs). | **Seletivo:** Filtra idiomas e remove "lixo" técnico. |
| **Inteligência** | Não avisa sobre quebras. | **Auditor:** Avisa se um app depende de Runtimes antigas. |
| **Manutenção** | Comandos complexos. | **Scripts Dedicados:** Limpeza e integridade em um clique. |

> [!WARNING]
> **AVISO DE PERFORMANCE:** O download paralelo usa intensamente o disco. Para discos rígidos comuns (HDDs de 5400/7200 RPM como o de 750GB do ComiteNerd), recomenda-se o uso de **1 a 2 threads (slots)** no `config.env` para evitar gargalos e travamentos no sistema hospedeiro.

<img width="822" height="300" alt="Dashboard do Mirror" src="https://github.com/user-attachments/assets/0894a7a5-22e5-4b83-b20f-003a692547d7" />

**ATENÇÃO: o download pode usar todos os recursos do SSD provocando gargalos e travamentos durante o download. Use de 1 a 2 threads (slots) para discos comuns.**

<img width="822" height="300" alt="image" src="https://github.com/user-attachments/assets/0894a7a5-22e5-4b83-b20f-003a692547d7" />

$\color{red}{\text{Evite discos com péssima qualidade!}}$

---

## 📋 Sumário
- [🌟 Benefícios](#-benefícios)
- [📂 Estrutura do Projeto](#-estrutura-do-projeto)
- [🛠️ Ferramentas de Manutenção](#-ferramentas-de-manutenção)
- [🚀 Como Instalar e Executar](#-como-instalar-e-executar)
- [👋 Contato e Créditos](#-contato-e-créditos)

---

## 🌟 Benefícios

* **100% Offline:** Instale apps sem gastar 1kb de internet após o espelhamento inicial.
* **Velocidade Giga:** Instalações na velocidade da LAN (1Gbps ou mais).
* **Peneira de Idiomas:** Filtra automaticamente apenas PT-BR e EN, economizando dezenas de GBs.
* **Prioridade Inteligente:** Configura o PC cliente para preferir sempre o seu Mirror Local ao Flathub oficial.

---

## 🛠️ Ferramentas de Manutenção

O ecossistema conta com ferramentas robustas para garantir a saúde do seu repositório local:

### 🏥 `auditor.sh` (O Doutor)
Realiza o diagnóstico completo do seu Mirror:
1.  **Integridade Física (FSCK):** Procura por arquivos corrompidos no HD e oferece reparo automático.
2.  **Análise de Dependências:** Verifica se algum App ainda depende de Runtimes antigas (18.08 a 20.08) antes de você removê-las.

### 🧹 `clean.sh` (A Faxina)
Script de limpeza pesada com **Calculadora de Economia**:
* Permite definir filtros Regex personalizados para remoção.
* **Mostra a economia estimada em GB** antes de confirmar a exclusão.
* Executa o `ostree prune` para compactar o banco de dados e liberar espaço real.

---

## 📂 Estrutura de Arquivos

* **`config.env`**: O "cérebro". Guarda IPs, filtros de ignorar e limites de slots.
* **`main.sh`**: O motor de download paralelo com Dashboard em tempo real.
* **`server.sh`**: O coração da distribuição. Sobe o servidor HTTP e gera a **Vitrine Web**.
* **`setup_client.sh`**: Script gerado automaticamente para configurar PCs clientes em um comando.
* **`auditor.sh`**: Sistema de checagem de saúde física e lógica.
* **`clean.sh`**: Gestor de espaço e remoção seletiva de versões obsoletas.

---

## 🚀 Como Instalar e Executar

### 1. Preparação (No Servidor)
Instale as dependências essenciais no seu PC principal:
```bash
sudo apt update && sudo apt install flatpak ostree parallel python3 bc tput curl
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
