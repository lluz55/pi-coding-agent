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
      in
      {
        packages = {
          # 1. Qwen Specific Wrapper
          qwen = pkgs.writeShellScriptBin "pi-qwen" ''
            #!/usr/bin/env bash
            export PI_HOME="$PWD/.pi/qwen"
            export PI_CODING_AGENT_DIR="$PI_HOME/agent"
            mkdir -p "$PI_CODING_AGENT_DIR"
            
            # Logout/Reset Logic
            CLEAN_ARGS=()
            for arg in "$@"; do
              if [[ "$arg" == "--logout" ]] || [[ "$arg" == "--reset" ]]; then
                echo "Clearing Qwen credentials..."
                rm -f "$PI_CODING_AGENT_DIR/auth.json"
              else
                CLEAN_ARGS+=("$arg")
              fi
            done

            if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
              echo '{"packages": ["npm:pi-qwen-provider"], "defaultProvider": "qwen"}' > "$PI_CODING_AGENT_DIR/settings.json"
            fi

            export PATH="${pkgs.nodejs}/bin:$PATH"
            
            if [ ! -d "$PI_HOME/extensions/node_modules/pi-qwen-provider" ]; then
              echo "Installing Qwen provider..."
              npx --yes @mariozechner/pi-coding-agent install --local npm:pi-qwen-provider
            fi

            echo "Starting Pi Agent (Qwen Edition)..."
            echo "Tip: If you get 401/Expired error, run with '--logout' to reset."
            
            npx --yes @mariozechner/pi-coding-agent "''${CLEAN_ARGS[@]}"
          '';

          # 2. Z.ai Specific Wrapper
          zai = pkgs.writeShellScriptBin "pi-zai" ''
            #!/usr/bin/env bash
            export PI_HOME="$PWD/.pi/zai"
            export PI_CODING_AGENT_DIR="$PI_HOME/agent"
            mkdir -p "$PI_CODING_AGENT_DIR"

            # Handle Arguments
            ZAI_TOKEN_VAL="$ZAI_TOKEN"
            CLEAN_ARGS=()
            while [[ $# -gt 0 ]]; do
              case $1 in
                --zai_token) ZAI_TOKEN_VAL="$2"; shift 2 ;;
                --logout|--reset) 
                  echo "Clearing Z.ai credentials..."
                  rm -f "$PI_CODING_AGENT_DIR/auth.json"
                  shift 
                  ;;
                *) CLEAN_ARGS+=("$1"); shift ;;
              esac
            done

            # Save token if provided
            if [ ! -z "$ZAI_TOKEN_VAL" ]; then
              if [ -f "$PI_CODING_AGENT_DIR/auth.json" ]; then
                tmp=$(mktemp)
                ${pkgs.jq}/bin/jq --arg key "$ZAI_TOKEN_VAL" '.zai = {"type": "api_key", "key": $key}' "$PI_CODING_AGENT_DIR/auth.json" > "$tmp" && mv "$tmp" "$PI_CODING_AGENT_DIR/auth.json"
              else
                echo "{\"zai\": {\"type\": \"api_key\", \"key\": \"$ZAI_TOKEN_VAL\"}}" > "$PI_CODING_AGENT_DIR/auth.json"
              fi
              echo "Z.ai token saved locally."
            else
              if [ -f "$PI_CODING_AGENT_DIR/auth.json" ] && ${pkgs.jq}/bin/jq -e '.zai' "$PI_CODING_AGENT_DIR/auth.json" >/dev/null 2>&1; then
                echo "Using previously saved Z.ai token."
              fi
            fi

            if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
              echo '{"defaultProvider": "zai"}' > "$PI_CODING_AGENT_DIR/settings.json"
            fi

            export PATH="${pkgs.nodejs}/bin:$PATH"
            echo "Starting Pi Agent (Z.ai Edition)..."
            npx --yes @mariozechner/pi-coding-agent "''${CLEAN_ARGS[@]}"
          '';

          # 3. Default Wrapper (Standard Pi)
          default = pkgs.writeShellScriptBin "pi-agent" ''
            #!/usr/bin/env bash
            export PATH="${pkgs.nodejs}/bin:$PATH"
            exec npx --yes @mariozechner/pi-coding-agent "$@"
          '';
        };
        
        apps = {
          qwen = { type = "app"; program = "${self.packages.${system}.qwen}/bin/pi-qwen"; };
          zai = { type = "app"; program = "${self.packages.${system}.zai}/bin/pi-zai"; };
          default = { type = "app"; program = "${self.packages.${system}.default}/bin/pi-agent"; };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs.nodejs pkgs.jq ];
        };
      }
    );
}