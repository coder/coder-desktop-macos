# Coder Desktop Development Guide

## Build & Test Commands
- Build Xcode project: `make`
- Format Swift files: `make fmt`
- Lint Swift files: `make lint`
- Run all tests: `make test`
- Run specific test class: `xcodebuild test -project "Coder Desktop/Coder Desktop.xcodeproj" -scheme "Coder Desktop" -only-testing:"Coder DesktopTests/AgentsTests"`
- Run specific test method: `xcodebuild test -project "Coder Desktop/Coder Desktop.xcodeproj" -scheme "Coder Desktop" -only-testing:"Coder DesktopTests/AgentsTests/agentsWhenVPNOff"`
- Generate Swift from proto: `make proto`
- Watch for project changes: `make watch-gen`

## Code Style Guidelines
- Use Swift 6.0 for development
- Follow SwiftFormat and SwiftLint rules
- Use Swift's Testing framework for tests (`@Test`, `#expect` directives)
- Group files logically (Views, Models, Extensions)
- Use environment objects for dependency injection
- Prefer async/await over completion handlers
- Use clear, descriptive naming for functions and variables
- Implement proper error handling with Swift's throwing functions
- Tests should use descriptive names reflecting what they're testing