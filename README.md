# Coder Desktop for macOS

Coder Desktop allows you to work on your Coder workspaces as though they're
on your local network, with no port-forwarding required. It provides seamless
access to your remote development environments through features like Coder
Connect (VPN-like connectivity) and file synchronization between local and
remote directories.

Learn more about Coder Desktop in the
[official documentation](https://coder.com/docs/user-guides/desktop).

This repo contains the Swift source code for Coder Desktop for macOS. You can
download the latest version from the GitHub releases.

## Features

- **Coder Connect**: VPN-like connectivity to your Coder workspaces
- **File Synchronization**: Seamless sync between local and remote directories using Mutagen
- **Native macOS Integration**: Built with Swift and native macOS frameworks
- **Secure**: All connections are encrypted and authenticated

## Prerequisites

Before opening the project in Xcode, you need to generate the Xcode project files.
We use [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) to handle this
process, and the project generation is integrated into the `Makefile`.

## Setting Up the Development Environment

To ensure a consistent and reliable development environment, we recommend using
[**Nix**](https://nix.dev/) with Flake support. All the tools required for
development are defined in the `flake.nix` file.

**Note:** Nix is the only supported development environment for this project.
While setups outside of Nix may work, we do not support custom tool installations
or address issues related to missing path setups or other tooling installation
problems. Using Nix ensures consistency across development environments and avoids
these potential issues.

### Installing Nix with Flakes Enabled

If you don't already have Nix installed, you can:

1. Use the [Determinate Systems installer](https://nixinstaller.com/) for a
   simple setup.
2. Alternatively, use the [official installer](https://nixos.org/download.html)
   and enable Flake support by adding the following to your Nix configuration:

   ```nix
   experimental-features = nix-command flakes
   ```

This project does **not** support non-Flake versions of Nix.

### Entering the Development Environment

Run the following command to enter the development environment with all necessary
tools:

```bash
nix develop
```

### Using `direnv` for Environment Automation (Optional)

As an optional recommendation, you can use [`direnv`](https://direnv.net/) to
automatically load and unload the Nix development environment when you navigate
to the project directory. After installing `direnv`, enable it for this project by:

1. Adding the following line to your `.envrc` file in the project directory:

   ```bash
   use flake
   ```

2. Allowing the `.envrc` file by running:

   ```bash
   direnv allow
   ```

## Building the Project

### Generating the Xcode Project Files

Once your development environment is set up, generate the Xcode project files by
running:

```bash
make setup
```

This will:
- Download required Mutagen resources
- Generate the Xcode project using XcodeGen
- Generate Swift files from Protocol Buffer definitions
- Set up all necessary dependencies

### Opening in Xcode

After running `make setup`, you can open the project in Xcode:

```bash
open Coder-Desktop/Coder-Desktop.xcodeproj
```

## Development Commands

Here are the available `make` commands for working with the project:

- `make setup`: Set up the project (download dependencies, generate Xcode project)
- `make fmt`: Format Swift files using SwiftFormat
- `make lint`: Lint Swift files using SwiftLint
- `make test`: Run all tests using `xcodebuild`
- `make clean`: Clean the Xcode project
- `make proto`: Generate Swift files from Protocol Buffers
- `make help`: Display all available `make` commands with descriptions

For continuous development, you can also use:

```bash
make watch-gen
```

This command watches for changes to `Coder-Desktop/project.yml` and regenerates
the Xcode project file as needed.

## Project Structure

- **Coder-Desktop/**: Main application source code
- **Coder-DesktopHelper/**: Helper application for privileged operations
- **CoderSDK/**: Swift SDK for interacting with Coder APIs
- **VPN/**: VPN client implementation
- **VPNLib/**: Core VPN functionality and Protocol Buffer definitions
- **Resources/**: Application resources including Mutagen binaries
- **Tests/**: Unit and UI tests

## Architecture

The macOS version of Coder Desktop is built using:

- **Swift 6.0**: Modern Swift with strict concurrency
- **SwiftUI**: For the user interface
- **Network Extension**: For VPN functionality
- **Mutagen**: For file synchronization
- **Protocol Buffers**: For communication protocols
- **XcodeGen**: For project file generation

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

## License

The Coder Desktop for macOS source is licensed under the GNU Affero General
Public License v3.0 (AGPL-3.0).

Some vendored files in this repo are licensed separately. The license for these
files can be found in the same directory as the files.

The binary distributions of Coder Desktop for macOS have additional license
disclaimers that can be found during installation.