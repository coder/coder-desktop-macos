# Coder Connect for iOS

This repo contains an experimental iOS app (`Coder-Desktop-iOS` + `VPN-iOS`
targets) that provides Coder Connect on iPhone/iPad: a packet-tunnel VPN that
makes workspaces reachable at `*.coder` hostnames, like the macOS app.

## Why the architecture differs from macOS

On macOS, Coder Connect downloads the deployment's signed `coder-darwin-*`
binary at runtime and spawns it from a privileged LaunchDaemon, guaranteeing
the tunnel always matches the server version. None of that is possible on iOS:

- **No downloaded code.** App Store Guideline 2.5.2 forbids downloading,
  installing, or executing code, and iOS library validation only loads
  libraries embedded in the app bundle. The Go tunnel (`vpn` + `tailnet`
  from [coder/coder]) is therefore **statically compiled into the network
  extension at build time** (`libtunnel/` → `CoderVPN.xcframework`), the same
  pattern used by WireGuard, Tailscale, and Nebula on iOS. Client/server
  version skew is handled by the existing `vpn.proto` handshake plus a
  minimum-server-version check, instead of exact version matching.
- **No XPC, no subprocesses, no LaunchDaemons.** The macOS Helper's manager
  loop runs *inside* the extension (`VPN-iOS/TunnelManager.swift`), talking to
  the Go tunnel over in-process pipes with the same `Speaker` protobuf
  protocol. The app talks to the extension via
  `NETunnelProviderSession.sendProviderMessage`.
- **~50 MiB memory cap.** iOS jetsam kills packet-tunnel extensions that
  exceed ~50 MiB resident memory. `libtunnel` sets `GOMAXPROCS(1)`,
  `debug.SetGCPercent(10)`, and `debug.SetMemoryLimit(32 MiB)` (Tailscale's
  playbook), and the app enables on-demand rules so the system restarts the
  tunnel if it's ever killed.
- **App extension, not system extension.** There's no
  `OSSystemExtensionRequest` flow; saving the `NETunnelProviderManager`
  configuration prompts the user to allow the VPN.

`*.coder` DNS needs no platform-specific work: the tunnel pushes
`NEDNSSettings` (servers + `matchDomains`) over the existing protocol, and the
conversion in `VPNLib/VPNConvert.swift` behaves identically on iOS.

## Building

Requires macOS with Xcode and Go (see `libtunnel/go.mod` for the version).

```sh
make ios   # builds CoderVPN.xcframework, generates the project, builds the app
```

The Go tunnel can be rebuilt alone with `make Coder-Desktop/CoderVPN.xcframework`,
which runs `scripts/build-libcodervpn.sh`. The coder/coder version is pinned
in `libtunnel/go.mod`; its `replace` directives must mirror coder/coder's.

## Testing

The iOS Simulator cannot run network extensions, so the tunnel can only be
verified on a physical device with a development team that has the Network
Extension capability:

1. Build & run the `Coder-Desktop-iOS` scheme on a device.
2. Sign in with a deployment URL and session token, then enable the
   "Coder Connect" toggle and accept the VPN configuration prompt.
3. Confirm a workspace loads in Safari at `http://<workspace>.coder:<port>`,
   and that the workspaces list populates.
4. Watch memory: profile the `VPN-iOS` process in Instruments while moving
   traffic; it must stay well under 50 MiB or jetsam will kill it.

App Store distribution additionally requires an organization-enrolled
developer account (App Review Guideline 5.4 for apps offering VPN services).
TestFlight works for packet-tunnel providers.

## CI

> [!NOTE]
> This job couldn't be pushed from the automated session (workflow files
> require elevated permissions); add it to `.github/workflows/ci.yml`:

```yaml
  build-ios:
    name: build-ios
    runs-on: ${{ github.repository_owner == 'coder' && 'depot-macos-26' || 'macos-26'}}
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 0
          fetch-tags: true
          persist-credentials: false

      - name: Switch XCode Version
        uses: maxim-lobanov/setup-xcode@ed7a3b1fda3918c0306d1b724322adc0b8cc0a90 # v1.7.0
        with:
          xcode-version: "26.5.0"

      - name: Setup Nix
        uses: ./.github/actions/nix-devshell

      - name: Setup Go
        uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5 # v5.5.0
        with:
          go-version-file: libtunnel/go.mod
          cache-dependency-path: libtunnel/go.sum

      - run: make ios
```

## Status & remaining work

Implemented: Go c-archive build, shared `VPNLib`/`CoderSDK` iOS framework
targets, the in-process tunnel manager, and a minimal SwiftUI app (login,
connect toggle, workspaces list, on-demand restart). The app currently polls
peer state every 5s while connected; the extension already posts a Darwin
notification (`CoderIPC.peerUpdateNotification`) on changes for a future
push-based refresh.

Not yet done:

- First build/run on a physical device (utun fd handover, split DNS, and the
  memory budget all need on-device validation).
- Upstreaming `libtunnel` into coder/coder as a maintained build target
  (it resurrects the `OpenTunnel` entry point removed in coder/coder#22592).
- Memory profiling under load and tuning of the Go memory limit.
- TestFlight/release lane, app icon, URL handling, and Apple organization
  account provisioning.

[coder/coder]: https://github.com/coder/coder
