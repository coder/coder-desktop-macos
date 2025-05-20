import SwiftUI
import VPNLib

struct VPNProgress {
    let stage: ProgressStage
    let downloadProgress: DownloadProgress?
}

struct VPNProgressView: View {
    let state: VPNServiceState
    let progress: VPNProgress

    var body: some View {
        VStack {
            CircularProgressView(value: value)
                // We estimate that the last half takes 8 seconds
                // so it doesn't appear stuck
                .autoComplete(threshold: 0.5, duration: 8)
            Text(progressMessage)
                .multilineTextAlignment(.center)
        }
        .padding()
        .foregroundStyle(.secondary)
    }

    var progressMessage: String {
        "\(progress.stage.description ?? defaultMessage)\(downloadProgressMessage)"
    }

    var downloadProgressMessage: String {
        progress.downloadProgress.flatMap { "\n\($0.description)" } ?? ""
    }

    var defaultMessage: String {
        state == .connecting ? "Starting Coder Connect..." : "Stopping Coder Connect..."
    }

    var value: Float? {
        guard state == .connecting else {
            return nil
        }
        switch progress.stage {
        case .initial:
            return 0
        case .downloading:
            guard let downloadProgress = progress.downloadProgress else {
                // We can't make this illegal state unrepresentable because XPC
                // doesn't support enums with associated values.
                return 0.05
            }
            // 40MB if the server doesn't give us the expected size
            let totalBytes = downloadProgress.totalBytesToWrite ?? 40_000_000
            let downloadPercent = min(1.0, Float(downloadProgress.totalBytesWritten) / Float(totalBytes))
            return 0.4 * downloadPercent
        case .validating:
            return 0.43
        case .removingQuarantine:
            return 0.46
        case .startingTunnel:
            return 0.50
        }
    }
}
