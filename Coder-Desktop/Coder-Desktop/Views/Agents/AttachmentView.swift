import CoderSDK
import SwiftUI

/// Transcript attachment actions, injected by the session detail so the non-generic message
/// part views can reach the (generic) agents service and the Quick Look host. The defaults
/// are inert, so previews/tests render without wiring.
struct ChatAttachmentActions {
    var image: (UUID) -> NSImage? = { _ in nil }
    var failure: (UUID) -> ChatAttachmentFailure? = { _ in nil }
    var load: (ChatMessagePart) -> Void = { _ in }
    var open: (ChatMessagePart) -> Void = { _ in }
    var save: (ChatMessagePart) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var chatAttachments = ChatAttachmentActions()
}

/// A user message's uploaded attachment: image thumbnail or file chip, opening in Quick Look.
/// Failure states mirror the web's expired/failed tiles.
struct AttachmentPartView: View {
    let part: ChatMessagePart
    @Environment(\.chatAttachments) private var attachments
    /// Small uploads arrive inline as base64 with no file id; decoded locally once.
    @State private var inlineImage: NSImage?

    private var thumbnail: NSImage? {
        part.file_id.flatMap(attachments.image) ?? inlineImage
    }

    var body: some View {
        if let failure = part.file_id.flatMap(attachments.failure) {
            failureTile(failure)
        } else if part.isImageAttachment {
            imageThumbnail
        } else {
            fileChip
        }
    }

    private var imageThumbnail: some View {
        Button { attachments.open(part) } label: {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius)
                    .strokeBorder(Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(part.attachmentDisplayName)")
        .contextMenu { saveButton }
        .task(id: part.file_id) {
            if inlineImage == nil, let data = part.inlineAttachmentData {
                inlineImage = NSImage(data: data)
            }
            attachments.load(part)
        }
    }

    private var fileChip: some View {
        Button { attachments.open(part) } label: {
            Label(part.attachmentDisplayName, systemImage: "doc")
                .font(.caption)
                .pillChrome(vertical: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(part.attachmentDisplayName)")
        .contextMenu { saveButton }
    }

    private var saveButton: some View {
        Button("Save As…") { attachments.save(part) }
    }

    private func failureTile(_ failure: ChatAttachmentFailure) -> some View {
        let noun = part.isImageAttachment ? "Image" : "Attachment"
        let (text, help) = switch failure {
        case .expired: (
                "\(noun) expired",
                "Attachments are kept while any chat references them. After all references are "
                    + "removed, they are deleted once they are older than this deployment's "
                    + "retention window."
            )
        case let .failed(message): ("\(noun) failed to load", message)
        }
        return Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .pillChrome(vertical: 4, tint: 0.1)
            .help(help)
    }
}
