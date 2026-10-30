{
  description = "Coder Desktop macOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # The protoc plugins must stay in lockstep with the SwiftProtobuf and
    # grpc-swift (v1) runtime versions pinned in Coder-Desktop/project.yml.
    # They're built from source with nixpkgs' Swift toolchain, which newer
    # nixpkgs no longer supports on Darwin, so they get their own pin that's
    # independent of the rest of the toolchain.
    nixpkgs-grpc-swift.url = "github:nixos/nixpkgs/698214a32beb4f4c8e3942372c694f40848b360d";
    grpc-swift = {
      url = "github:i10416/grpc-swift-flake";
      inputs.nixpkgs.follows = "nixpkgs-grpc-swift";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      grpc-swift,
      ...
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

          formatter = pkgs.nixfmt;
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
                gh
                git
                gnumake
                protobuf_36
                grpc-swift.packages.${system}.protoc-gen-grpc-swift
                grpc-swift.packages.${system}.protoc-gen-swift
                swiftformat
                swiftlint
                xcbeautify
                xcodegen
                xcpretty
                zizmor
              ];
              shellHook = ''
                # Copied from https://github.com/ghostty-org/ghostty/blob/c4088f0c73af1c153c743fc006637cc76c1ee127/nix/devShell.nix#L189-L199
                # We want to rely on the system Xcode tools in CI!
                unset SDKROOT
                unset DEVELOPER_DIR
                # We need to remove the nix "xcrun" from the PATH.
                export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /xcrun/ || $0 == "/usr/bin" {print}' | sed 's/:$//')
              '';
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
