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
        repoRoot = builtins.toString ./.;
      in
      {
        packages = {
          # 1. Qwen Specific Wrapper
          qwen = pkgs.writeShellScriptBin "pi-qwen" ''
            #!/usr/bin/env bash
            export PI_PROJECT_ROOT="$(pwd)/.pi/qwen"
            export HOME="$PI_PROJECT_ROOT"
            export PI_CODING_AGENT_DIR="$HOME/agent"
            export PATH="${pkgs.nodejs}/bin:$PATH"

            mkdir -p "$PI_CODING_AGENT_DIR"

            CLEAN_ARGS=()
            QWEN_LOGOUT=0
            QWEN_REAUTH=0
            for arg in "$@"; do
              if [[ "$arg" == "--logout" ]] || [[ "$arg" == "--reset" ]]; then
                QWEN_LOGOUT=1
              elif [[ "$arg" == "--login" ]] || [[ "$arg" == "--reauth" ]]; then
                QWEN_REAUTH=1
              else
                CLEAN_ARGS+=("$arg")
              fi
            done

            mkdir -p "$PI_PROJECT_ROOT"
            mkdir -p "$PI_CODING_AGENT_DIR"
            echo '{"defaultProvider":"qwen-cli"}' > "$PI_CODING_AGENT_DIR/settings.json"

            AUTH_HELPER="${repoRoot}/extensions/qwen-cli/oauth.mjs"
            if [[ ! -f "$AUTH_HELPER" ]]; then
              echo "Qwen auth helper not found: $AUTH_HELPER" >&2
              exit 1
            fi

            AUTH_ARGS=(--auth-file "$PI_CODING_AGENT_DIR/auth.json")
            if [[ "$QWEN_LOGOUT" -eq 1 ]]; then
              AUTH_ARGS+=(--logout)
            fi
            if [[ "$QWEN_REAUTH" -eq 1 ]]; then
              AUTH_ARGS+=(--reauth)
            fi

            node "$AUTH_HELPER" ''${AUTH_ARGS[@]} || exit 1

            echo "Starting Pi Agent (Qwen OAuth - TOTAL ISOLATION)..."
            npx --yes @mariozechner/pi-coding-agent --no-extensions -e "${repoRoot}/extensions/qwen-cli" ''${CLEAN_ARGS[@]}
          '';

          # 2. Z.ai Specific Wrapper
          zai = pkgs.writeShellScriptBin "pi-zai" ''
            #!/usr/bin/env bash
            export PI_PROJECT_ROOT="$(pwd)/.pi/zai"
            export HOME="$PI_PROJECT_ROOT"
            export PI_CODING_AGENT_DIR="$HOME/agent"
            mkdir -p "$PI_CODING_AGENT_DIR"

            # Handle Arguments
            ZAI_TOKEN_VAL="$ZAI_TOKEN"
            CLEAN_ARGS=()
            while [[ $# -gt 0 ]]; do
              case $1 in
                --zai_token) ZAI_TOKEN_VAL="$2"; shift 2 ;;
                --logout|--reset) 
                  echo "Clearing Z.ai credentials..."
                  rm -rf "$PI_PROJECT_ROOT/agent"
                  mkdir -p "$PI_CODING_AGENT_DIR"
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
            echo "Starting Pi Agent (Z.ai - TOTAL ISOLATION)..."
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
