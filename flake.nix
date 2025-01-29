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
        in
        {
          inherit formatter;

          devShells.default = pkgs.mkShellNoCC {
            buildInputs = with pkgs; [
              apple-sdk_15
              clang
              formatter
              gnumake
              protobuf_28
              protoc-gen-swift
              swiftformat
              swiftlint
              watchexec
              xcodegen
              xcbeautify
            ];
          };
        }
      );
}
