# Contributing to projeto_flatpak_offline

Obrigado por seu interesse em contribuir! A comunidade local de Flatpak offline funciona melhor quando o fluxo de contribuições é claro.

## Como contribuir

1. Fork o repositório.
2. Crie uma branch com nome descritivo:
   - `git checkout -b feature/add-new-script`
   - `git checkout -b fix/bug-xxx`
3. Faça mudanças pequenas e focadas.
4. Garanta que o script está funcionando no ambiente de testes.
5. Faça commit com mensagem significativa:
   - `git commit -m "fix: corrige checagem de dependência no main.sh"`
6. Envie seu branch para o fork:
   - `git push origin feature/add-new-script`
7. Abra um Pull Request no repositório principal.

## Guidelines de código

- Bash deve usar `set -euo pipefail`.
- Em loops, use sempre `local var` para evitar variáveis globais acidentais.
- Código deve ser legível e comentado nas partes complexas.

## Estrutura de Branches

- `main`: código estável, pronto para produção.
- `dev` (opcional): desenvolvimento diário e integração.
- `feature/*`, `fix/*`, `chore/*`: convênios para PRs.

## Relatar bugs

1. Abra issue com título claro.
2. Informe o ambiente (distro, versão do Bash, flatpak, ostree, etc.).
3. Forneça passos para reproduzir.
4. Inclua logs, mensagens de erro e comportamentos observados.

## Testes

- Execute `bash main.sh` em modo de testes com um pequeno filtro e um disco temporário.
- Verifique a geração correta de `config.env` e `setup_client.sh`.

## Licença

Ao contribuir, você concorda em manter o código compatível com a licença MIT do projeto.
