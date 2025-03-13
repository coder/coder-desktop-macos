# Contributing to Coder Desktop

Thank you for your interest in contributing to Coder Desktop! Below are the
guidelines to help you get started.

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

If you don’t already have Nix installed, you can:

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

With `direnv`, the development environment will automatically be set up whenever
you enter the project directory. This step is optional but can significantly
streamline your workflow.

## Generating the Xcode Project Files

Once your development environment is set up, generate the Xcode project files by
running:

```bash
make
```

This will use **XcodeGen** to create the required Xcode project files.
The configuration for the project is defined in `Coder-Desktop/project.yml`.

## Common Make Commands

Here are some useful `make` commands for working with the project:

- `make fmt`: Format Swift files using SwiftFormat.
- `make lint`: Lint Swift files using SwiftLint.
- `make test`: Run all tests using `xcodebuild`.
- `make clean`: Clean the Xcode project.
- `make proto`: Generate Swift files from protobufs.
- `make help`: Display all available `make` commands with descriptions.

For continuous development, you can also use:

```bash
make watch-gen
```

This command watches for changes to `Coder-Desktop/project.yml` and regenerates
the Xcode project file as needed.

## Testing and Formatting

To maintain code quality, ensure you run the following before submitting any changes:

1. **Format Swift files:**

   ```bash
   make fmt
   ```

2. **Lint Swift files:**

   ```bash
   make lint
   ```

3. **Run tests:**

   ```bash
   make test
   ```

## Contributing Workflow

1. Fork the repository and create your feature branch:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes and commit them with clear messages.
3. Push your branch to your forked repository:

   ```bash
   git push origin feature/your-feature-name
   ```

4. Open a pull request to the main repository.

Thank you for contributing! If you have any questions or need further assistance,
feel free to open an issue.
