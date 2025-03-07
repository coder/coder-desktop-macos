{
  description = "Coder Desktop macOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    grpc-swift.url = "github:i10416/grpc-swift-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      grpc-swift,
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
                protobuf_28
                grpc-swift.packages.${system}.protoc-gen-grpc-swift
                grpc-swift.packages.${system}.protoc-gen-swift
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
