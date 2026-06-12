import Foundation

/// Constants shared between the iOS app and its Network Extension.
///
/// iOS app extensions can't use XPC, so the extension is driven via
/// `NETunnelProviderSession.sendProviderMessage`, and signals the app via
/// Darwin notifications.
public enum CoderIPC {
    /// Darwin notification posted by the Network Extension whenever
    /// workspaces/agents change, prompting the app to fetch fresh peer state.
    public static let peerUpdateNotification = "com.coder.Coder-Desktop-iOS.peerUpdate"

    /// Provider message requesting the current `Vpn_PeerUpdate` state,
    /// serialized as protobuf bytes.
    public static let getPeerStateMessage = "getPeerState"
}
