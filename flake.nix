{
  description = "Pi Coding Agent - Separated Qwen and Z.ai Apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # 1. Qwen Specific Wrapper
        piQwen = pkgs.writeShellScriptBin "pi-qwen" ''
          #!/usr/bin/env bash
          export PI_HOME="$PWD/.pi/qwen"
          export PI_CODING_AGENT_DIR="$PI_HOME/agent"
          mkdir -p "$PI_CODING_AGENT_DIR"
          
          # Minimal settings for Qwen
          if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
            echo '{"packages": ["npm:pi-qwen-provider"], "defaultProvider": "qwen"}' > "$PI_CODING_AGENT_DIR/settings.json"
          fi

          export PATH="${pkgs.nodejs}/bin:$PATH"
          
          if [ ! -d "$PI_HOME/extensions/node_modules/pi-qwen-provider" ]; then
            echo "Installing Qwen provider..."
            npx --yes @mariozechner/pi-coding-agent install --local npm:pi-qwen-provider
          fi

          echo "Starting Pi Agent (Qwen Edition)..."
          exec npx --yes @mariozechner/pi-coding-agent "$@"
        '';

        # 2. Z.ai Specific Wrapper
        piZai = pkgs.writeShellScriptBin "pi-zai" ''
          #!/usr/bin/env bash
          export PI_HOME="$PWD/.pi/zai"
          export PI_CODING_AGENT_DIR="$PI_HOME/agent"
          mkdir -p "$PI_CODING_AGENT_DIR"

          # Handle Token Argument/Env
          ZAI_TOKEN_VAL="$ZAI_TOKEN"
          CLEAN_ARGS=()
          while [[ $# -gt 0 ]]; do
            case $1 in
              --zai_token) ZAI_TOKEN_VAL="$2"; shift 2 ;;
              *) CLEAN_ARGS+=("$1"); shift ;;
            esac
          done

          if [ ! -z "$ZAI_TOKEN_VAL" ]; then
            echo "{\"zai\": {\"type\": \"api_key\", \"key\": \"$ZAI_TOKEN_VAL\"}}" > "$PI_CODING_AGENT_DIR/auth.json"
            echo "Z.ai token configured."
          fi

          if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
            echo '{"defaultProvider": "zai"}' > "$PI_CODING_AGENT_DIR/settings.json"
          fi

          export PATH="${pkgs.nodejs}/bin:$PATH"
          echo "Starting Pi Agent (Z.ai Edition)..."
          exec npx --yes @mariozechner/pi-coding-agent "''${CLEAN_ARGS[@]}"
        '';

        # 3. Default Wrapper (Standard Pi)
        piDefault = pkgs.writeShellScriptBin "pi-agent" ''
          #!/usr/bin/env bash
          export PATH="${pkgs.nodejs}/bin:$PATH"
          exec npx --yes @mariozechner/pi-coding-agent "$@"
        '';
      in
      {
        packages = {
          qwen = piQwen;
          zai = piZai;
          default = piDefault;
        };
        
        apps = {
          qwen = { type = "app"; program = "${piQwen}/bin/pi-qwen"; };
          zai = { type = "app"; program = "${piZai}/bin/pi-zai"; };
          default = { type = "app"; program = "${piDefault}/bin/pi-agent"; };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs.nodejs ];
        };
      }
    );
}