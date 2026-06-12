import Foundation

/// The minimum Coder deployment version supported by this client.
///
/// On macOS the deployment also serves the tunnel binary, which is separately
/// validated against the server version. On iOS the tunnel is compiled into
/// the app, so this check (plus the protocol version handshake) is the only
/// client/server compatibility check.
public enum CoderVersion {
    public static let minimum = "2.24.3"
}
