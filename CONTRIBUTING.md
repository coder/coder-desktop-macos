# Contributing to Coder Desktop

Thank you for your interest in contributing to Coder Desktop! Below are the
guidelines to help you get started.

## Prerequisites

Before opening the project in Xcode, you need to generate the Xcode project files.
We use [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) to handle this
process, and the project generation is integrated into the `Makefile`.

Running the app (but not `make test`) requires signing its System Extension,
which needs a paid [Apple Developer Program](https://developer.apple.com/programs/)
membership. Coder employees should ask in Slack for an invite to the Coder team;
external contributors need their own membership and must swap out Coder's team ID
and bundle identifiers.

## Setting Up the Development Environment

To ensure a consistent and reliable development environment, we use
[**mise**](https://mise.jdx.dev/) to install the tools required for development.
Their versions are pinned in `mise.toml`.

**Note:** mise is the only supported way to install these tools. While other
setups may work, we do not support custom tool installations or address issues
related to missing path setups or other tooling installation problems. For
example, a Homebrew `swiftformat` may format the code differently from CI.

1. [Install mise](https://mise.jdx.dev/installing-mise.html).
2. [Activate mise in your shell](https://mise.jdx.dev/getting-started.html#activate-mise),
   so the pinned tools are on your `PATH` whenever you are in the project
   directory.
3. Install the tools:

   ```bash
   mise install
   ```

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

Maintainers can find release and signing instructions in
[RELEASING.md](RELEASING.md).

Thank you for contributing! If you have any questions or need further assistance,
feel free to open an issue.
