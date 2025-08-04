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
                // We estimate the duration of the last 35%
                // so it doesn't appear stuck
                .autoComplete(threshold: 0.65, duration: 8)
                // We estimate the duration of the first 25% (spawning Helper)
                // so it doesn't appear stuck
                .autoStart(until: 0.25, duration: 2)
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
                return 0.15
            }
            // 35MB if the server doesn't give us the expected size
            let totalBytes = downloadProgress.totalBytesToWrite ?? 35_000_000
            let downloadPercent = min(1.0, Float(downloadProgress.totalBytesWritten) / Float(totalBytes))
            return 0.25 + (0.35 * downloadPercent)
        case .validating:
            return 0.63
        case .startingTunnel:
            return 0.65
        }
    }
}
