{
  description = "Pi Coding Agent with Qwen and Z.ai Providers";

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
        packages.default = pkgs.writeShellScriptBin "pi-runner" ''
          #!/usr/bin/env bash
          # Total Isolation
          export PI_HOME="$PWD/.pi"
          export PI_CODING_AGENT_DIR="$PI_HOME/agent"
          
          mkdir -p "$PI_HOME"
          mkdir -p "$PI_CODING_AGENT_DIR/extensions"

          # 1. Remove OLD Z.ai extension implementation to prevent TUI crash
          rm -f "$PI_CODING_AGENT_DIR/extensions/zai-auth.ts"

          # 2. Argument parsing for --zai_token
          ZAI_TOKEN_VAL="$ZAI_TOKEN"
          CLEAN_ARGS=()
          while [[ $# -gt 0 ]]; do
            case $1 in
              --zai_token)
                ZAI_TOKEN_VAL="$2"
                shift 2
                ;;
              *)
                CLEAN_ARGS+=("$1")
                shift
                ;;
            esac
          done

          # 3. Inject Z.ai Token into auth.json if provided
          if [ ! -z "$ZAI_TOKEN_VAL" ]; then
            if [ -f "$PI_CODING_AGENT_DIR/auth.json" ]; then
              tmp=$(mktemp)
              ${pkgs.jq}/bin/jq --arg key "$ZAI_TOKEN_VAL" '.zai = {"type": "api_key", "key": $key}' "$PI_CODING_AGENT_DIR/auth.json" > "$tmp" && mv "$tmp" "$PI_CODING_AGENT_DIR/auth.json"
            else
              echo "{\"zai\": {\"type\": \"api_key\", \"key\": \"$ZAI_TOKEN_VAL\"}}" > "$PI_CODING_AGENT_DIR/auth.json"
            fi
            echo "Z.ai token configured."
          fi

          # 4. Create minimal local settings
          if [ ! -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
            echo '{"packages": ["npm:pi-qwen-provider"]}' > "$PI_CODING_AGENT_DIR/settings.json"
          fi

          # Add Node.js to path
          export PATH="${pkgs.nodejs}/bin:$PATH"

          # Install Qwen provider locally if missing
          if [ ! -d "$PI_HOME/extensions/node_modules/pi-qwen-provider" ]; then
            echo "Installing Qwen provider extension..."
            npx --yes @mariozechner/pi-coding-agent install --local npm:pi-qwen-provider
          fi

          echo "Starting Pi Agent..."
          echo "--------------------------------------------------------"
          echo "Use /login to connect with Qwen (OAuth)."
          echo "Use /model zai/glm-5 to switch to Z.ai (Token active)."
          echo "--------------------------------------------------------"
          
          # Execute the agent with remaining arguments
          exec npx --yes @mariozechner/pi-coding-agent "''${CLEAN_ARGS[@]}"
        '';
        
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/pi-runner";
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ pkgs.nodejs pkgs.jq ];
        };
      }
    );
}