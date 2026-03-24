# Pi Coding Agent - Ambiente Nix (Qwen & Z.ai)

Este projeto configura um ambiente de desenvolvimento isolado para o [Pi Coding Agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) utilizando **Nix Flakes**. Ele permite o uso dos ecossistemas **Qwen 3.5 (Alibaba)** e **Z.ai (Zhipu AI)** com suporte a autenticação OAuth e injeção de tokens.

## 🚀 Funcionalidades

- **Isolamento Total**: Todas as configurações, logins e extensões são armazenados localmente na pasta `.pi/` do projeto, evitando conflitos com sua home global.
- **Autenticação Dual**:
  - **Qwen**: Suporte a login interativo via OAuth no navegador.
  - **Z.ai**: Injeção automática de tokens do Z.ai Coding Plan via linha de comando ou variável de ambiente.
- **Ecossistema 2026**: Configurado para suportar os modelos mais recentes como `qwen3.5-plus`, `qwen3-coder-next` e `zai/glm-5`.
- **Ambiente Nix**: Zero instalação global. Basta ter o Nix com suporte a flakes.

## 📋 Pré-requisitos

- **Nix** com experimental-features `nix-command` e `flakes` habilitados.

## 🛠️ Como Iniciar

### 1. Iniciar o Agente

Para rodar o agente pela primeira vez (ele instalará as extensões necessárias automaticamente):

```bash
nix run .#
```

### 2. Autenticação Qwen (OAuth)

Dentro do terminal do Pi Agent:
1. Digite `/login`.
2. Selecione `qwen`.
3. Siga o link no navegador para autorizar o acesso.

### 3. Autenticação Z.ai (Token)

Você pode passar o seu token do plano de codificação da Z.ai de duas formas:

**Via variável de ambiente:**
```bash
ZAI_TOKEN="seu_token_aqui" nix run .#
```

**Via flag de linha de comando:**
```bash
nix run .# -- --zai_token "seu_token_aqui"
```

## ⌨️ Comandos Úteis

- `/login`: Inicia o fluxo OAuth para provedores compatíveis (Qwen).
- `/model <id>`: Troca o modelo atual (ex: `/model zai/glm-5` ou `/model qwen/qwen3.5-plus`).
- `/list-models`: Lista todos os modelos disponíveis para seus provedores autenticados.
- `Ctrl+P`: Atalho para navegar rapidamente entre os modelos habilitados.
- `/`: Abre a lista de comandos disponíveis (autocompletar fixo).

## 📁 Estrutura do Projeto

- `flake.nix`: Define o ambiente Nix e o script de inicialização `pi-runner`.
- `.pi/`: Diretório criado automaticamente para armazenar:
  - `agent/auth.json`: Credenciais de acesso (não commite este arquivo).
  - `agent/settings.json`: Configurações de provedores e modelos.
  - `extensions/`: Extensões instaladas localmente (incluindo o provedor Qwen).

## ⚠️ Observações de 2026

- Se você receber o erro `429 Free allocated quota exceeded` ao usar o `qwen-max`, mude para um modelo mais leve como `qwen-plus` ou `qwen3.5-27b` usando o comando `/model`.
- O ambiente foi corrigido para evitar crashes no TUI (Interface de Terminal) causados por modelos inválidos no autocompletar.

---
*Configurado para Agentic Engineering com foco em Qwen3 e GLM-5.*