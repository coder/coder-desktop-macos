{
  description = "Coder Desktop macOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachSystem
      (with flake-utils.lib.system; [
        aarch64-darwin
        x86_64-darwin
      ])
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          formatter = pkgs.nixfmt-rfc-style;

          create-dmg = pkgs.buildNpmPackage rec {
            pname = "create-dmg";
            version = "7.0.0";

            src = pkgs.fetchFromGitHub {
              owner = "sindresorhus";
              repo = pname;
              rev = "v${version}";
              hash = "sha256-+GxKfhVDmtgEh9NOAzGexgfj1qAb0raC8AmrrnJ2vNA=";
            };

            npmDepsHash = "sha256-48r9v0sTlHbyH4RjynClfC/QsFAlgMTtXCbleuMSM80=";

            # create-dmg author does not want to include a lockfile in their releases,
            # thus we need to vendor it in ourselves.
            postPatch = ''
              cp ${./nix/create-dmg/package-lock.json} package-lock.json
            '';

            # Plain JS, so nothing to build
            dontNpmBuild = true;
            dontNpmPrune = true;
          };
        in
        {
          inherit formatter;

          devShells = rec {
            # Need to use a devshell for CI, as we want to reuse the already existing Xcode on the runner
            ci = pkgs.mkShellNoCC {
              buildInputs = with pkgs; [
                actionlint
                clang
                coreutils
                create-dmg
                gh
                git
                gnumake
                protobuf_28
                protoc-gen-swift
                swiftformat
                swiftlint
                xcbeautify
                xcodegen
                xcpretty
                zizmor
              ];
            };

            default = pkgs.mkShellNoCC {
              buildInputs =
                with pkgs;
                [
                  apple-sdk_15
                  formatter
                  watchexec
                ]
                ++ ci.buildInputs;
            };
          };
        }
      );
}
