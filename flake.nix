{
  description = "Pi Coding Agent with Qwen Provider";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        piRunner = pkgs.writeShellScriptBin "pi-runner" ''
          #!/usr/bin/env bash
          # Isolate Pi configuration to the local directory
          export PI_HOME="$PWD/.pi"
          mkdir -p "$PI_HOME"

          echo "Initializing Pi Coding Agent environment..."
          
          # Add Node.js to PATH explicitly to ensure npx is available
          export PATH="${pkgs.nodejs_20}/bin:$PATH"

          # Check if the qwen provider is already in the local extensions
          if [ ! -d "$PI_HOME/extensions/node_modules/pi-qwen-provider" ]; then
            echo "Installing Qwen provider extension..."
            npx --yes @mariozechner/pi-coding-agent install npm:pi-qwen-provider
          fi

          echo "Starting Pi Agent..."
          echo "--------------------------------------------------------"
          echo "Tip: Type '/login' and select 'qwen' to authenticate."
          echo "--------------------------------------------------------"
          
          # Execute the agent
          exec npx --yes @mariozechner/pi-coding-agent "$@"
        '';
      in
      {
        packages.default = piRunner;
        apps.default = {
          type = "app";
          program = "${piRunner}/bin/pi-runner";
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs_20
          ];
        };
      }
    );
}