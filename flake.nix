{
  description = "Dulang nix flake with Erlang, Haskell and FDR4 support";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # stable Nixpkgs

  outputs =
    { self, ... }@inputs:

    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs { inherit system; };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        let
          hlsPkgs = import (builtins.fetchTarball {
              url = "https://github.com/NixOS/nixpkgs/archive/f8f124009497b3f9908f395d2533a990feee1de8.tar.gz";
              sha256 = "sha256:06v5kpa90iy2mv2bkxkg3zlbrr1g6kx2pvh5ijv4d5sji83fjbc9";
          }) { inherit system; };
          fdrEnv = import ./fdr4.nix { inherit pkgs; };
          runFdr = pkgs.writeShellScriptBin "fdr4" ''
            ${fdrEnv}/bin/${fdrEnv.name} -c '$ROOT/fdr/bin/fdr4'
          '';
          runRefines = pkgs.writeShellScriptBin "refines" ''
            ${fdrEnv}/bin/${fdrEnv.name} -c '$ROOT/fdr/bin/refines'
          '';
        in
        {
          default = pkgs.mkShell {
                packages = [
                  pkgs.erlang pkgs.rebar3 # To compile and use the Erlang language and the BEAM VM

                  # Haskell Packages from pinned tarball
                  hlsPkgs.haskellPackages.ghc
                  hlsPkgs.haskellPackages.alex
                  hlsPkgs.haskellPackages.happy
                  hlsPkgs.haskellPackages.cabal-install

                  # Commands from the FDR4 FHS Environment
                  runFdr
                  runRefines
                ];
                shellHook = ''
                    # Get the root directory to always refer correctly to the FDR4 binaries
                    export ROOT=$(pwd)
                    # Extract fdr application if the directory does not exists
                    [ -d fdr/ ] || tar -xzf $ROOT/fdr-3814-linux-x86_64.tar.gz
                '';
              };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);
    };
}
