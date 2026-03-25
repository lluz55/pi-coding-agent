# Pi Coding Agent - Ambiente Nix (Apps Separados)

Este projeto configura o [Pi Coding Agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) com ambientes isolados para diferentes provedores.

## 🚀 Aplicativos Disponíveis

### 1. Qwen Edition
Ambiente focado no ecossistema Qwen com o `pi-agent` usando OAuth do Qwen.
- **Diretório local**: `.pi/qwen`
- Ao iniciar, valida e renova a credencial OAuth local; se necessário, abre o fluxo de login automaticamente.
- **Execução**:
  ```bash
  nix run .#qwen
  ```
- **Opções úteis**:
  ```bash
  nix run .#qwen -- --reauth
  nix run .#qwen -- --logout
  nix run .#qwen -- --reset
  ```

### 2. Z.ai Edition
Ambiente focado no Z.ai (Zhipu AI) com suporte a token.
- **Diretório local**: `.pi/zai`
- Suporta `--logout` e `--reset` para limpar as credenciais locais.
- **Execução**:
  ```bash
  ZAI_TOKEN="seu_token" nix run .#zai
  # OU
  nix run .#zai -- --zai_token "seu_token"
  ```

### 3. Pi Agent (Padrão)
Executa o agente original sem wrappers de isolamento de diretório.
- **Execução**:
  ```bash
  nix run .#
  ```

## 📋 Pré-requisitos
- **Nix** com suporte a flakes.

## ⌨️ Comandos Úteis
- `--login` ou `--reauth`: força nova autenticação do Qwen no início da sessão.
- `--logout` ou `--reset`: remove apenas `.pi/qwen/agent/auth.json` e inicia novo OAuth.
- `/model <id>`: Troca o modelo.
- `/list-models`: Lista modelos disponíveis.
- `Ctrl+P`: Alterna entre modelos.

---
*Ambiente configurado para isolamento total entre ecossistemas.*
