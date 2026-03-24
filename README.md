# Pi Coding Agent - Ambiente Nix (Apps Separados)

Este projeto configura o [Pi Coding Agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) com ambientes isolados para diferentes provedores.

## 🚀 Aplicativos Disponíveis

### 1. Qwen Edition
Ambiente focado no ecossistema Qwen com suporte a OAuth.
- **Diretório local**: `.pi/qwen`
- **Execução**:
  ```bash
  nix run .#qwen
  ```

### 2. Z.ai Edition
Ambiente focado no Z.ai (Zhipu AI) com suporte a token.
- **Diretório local**: `.pi/zai`
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
- `/login`: Inicia OAuth (no app Qwen).
- `/model <id>`: Troca o modelo.
- `/list-models`: Lista modelos disponíveis.
- `Ctrl+P`: Alterna entre modelos.

---
*Ambiente configurado para isolamento total entre ecossistemas.*