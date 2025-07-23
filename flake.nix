{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.bun2nix.url = "github:baileyluTCD/bun2nix";

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      bunNix = import ./bun.nix;
      nodeModules = inputs.bun2nix.lib.x86_64-linux.mkBunNodeModules { packages = bunNix; };

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.prettier.enable = true;
        programs.nixfmt.enable = true;
        programs.biome.enable = true;
        programs.shfmt.enable = true;
        settings.formatter.prettier.priority = 1;
        settings.formatter.biome.priority = 2;
        settings.global.excludes = [
          "LICENSE"
          "*.ico"
        ];
      };

      formatter = treefmtEval.config.build.wrapper;

      tsc = pkgs.runCommand "tsc" { } ''
        cp -L ${./index.ts} ./index.ts
        cp -L ${./tsconfig.json} ./tsconfig.json
        cp -Lr ${nodeModules}/node_modules ./node_modules
        ${lib.getExe pkgs.typescript}
        touch $out
      '';

      biome = pkgs.runCommand "biome" { } ''
        cp -L ${./biome.jsonc} ./biome.jsonc
        cp -L ${./index.ts} ./index.ts
        cp -L ${./package.json} ./package.json
        cp -L ${./tsconfig.json} ./tsconfig.json
        cp -Lr ${nodeModules}/node_modules ./node_modules
        ${lib.getExe pkgs.biome} check --error-on-warnings
        touch $out
      '';

      publish = pkgs.writeShellApplication {
        name = "publish";
        runtimeInputs = [
          pkgs.jq
          pkgs.bun
          pkgs.curl
        ];
        text = ''
          repo_root=$(git rev-parse --show-toplevel)

          if [ -z "$NPM_CONFIG_TOKEN" ]; then
            export NPM_CONFIG_USERCONFIG="$repo_root/.npmrc"
            auth_prefix="//registry.npmjs.org/:_authToken=npm_"
            if ! grep -q "^$auth_prefix" "$NPM_CONFIG_USERCONFIG"; then
              echo "No NPM token found, running bunx npm login"
              bunx npm login
            fi
          fi

          current_version=$(jq -r .version "$repo_root/package.json")
          name=$(jq -r .name "$repo_root/package.json")
          published_version=$(curl -s "https://registry.npmjs.org/$name" | jq -r '.["dist-tags"].latest')
          if [ "$published_version" = "$current_version" ]; then
            echo "Version $current_version is already published"
            exit 0
          fi
          nix flake check
          bun publish
        '';
      };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.bun
          pkgs.biome
          pkgs.typescript
          pkgs.vscode-langservers-extracted
          pkgs.nixd
          pkgs.typescript-language-server
        ];
      };

      packages = devShells // {
        publish = publish;
        formatting = treefmtEval.config.build.check self;
        formatter = formatter;
        allInputs = collectInputs inputs;
        tsc = tsc;
        biome = biome;
        nodeModules = nodeModules;
        bun2nix = inputs.bun2nix.packages.x86_64-linux.default;
      };

    in
    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      devShells.x86_64-linux = devShells;

    };
}
