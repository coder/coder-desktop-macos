import AppKit
import CoderSDK
import UniformTypeIdentifiers

/// Why a transcript attachment shows a failure tile instead of content.
enum ChatAttachmentFailure: Equatable {
    /// 404: every referencing chat let go of the file and it aged past retention.
    case expired
    case failed(String)
}

// Transcript `file` attachments: fetched once via the authenticated files endpoint
// (like the web — the signed download-url flow is CLI-only), decoded for thumbnails,
// and materialized as temp files for Quick Look / Save As.
extension CoderAgentsService {
    func attachmentImage(_ fileID: UUID) -> NSImage? {
        attachmentImages[fileID]
    }

    func attachmentFailure(_ fileID: UUID) -> ChatAttachmentFailure? {
        attachmentFailures[fileID]
    }

    /// Fetches an attachment's bytes once. Inline (base64 `data`) parts are decoded by the
    /// view directly and never reach here.
    func loadAttachment(_ part: ChatMessagePart) {
        guard part.type == .file, part.inlineAttachmentData == nil,
              let id = part.file_id,
              attachmentImages[id] == nil, attachmentFailures[id] == nil,
              attachmentData[id] == nil, !attachmentLoads.contains(id)
        else { return }
        attachmentLoads.insert(id)
        let isImage = part.isImageAttachment
        Task {
            await fetchAttachment(id, isImage: isImage)
            attachmentLoads.remove(id)
        }
    }

    private func fetchAttachment(_ id: UUID, isImage: Bool) async {
        guard let client else { return }
        do {
            let data = try await client.chatFileData(id)
            attachmentData[id] = data
            if isImage {
                if let image = NSImage(data: data) {
                    attachmentImages[id] = image
                } else {
                    attachmentFailures[id] = .failed("Unreadable image data")
                }
            }
        } catch {
            if case let .api(apiError) = error, apiError.statusCode == 404 {
                attachmentFailures[id] = .expired
            } else {
                attachmentFailures[id] = .failed(error.localizedDescription)
            }
        }
    }

    /// Materializes an attachment as a temp file (named for Quick Look's title and renderer),
    /// fetching the bytes first if needed. Nil when the fetch fails (the failure state is
    /// recorded for the tile to show).
    func attachmentFileURL(_ part: ChatMessagePart) async -> URL? {
        let bytes: Data
        if let inline = part.inlineAttachmentData {
            bytes = inline
        } else if let id = part.file_id {
            if attachmentData[id] == nil {
                await fetchAttachment(id, isImage: part.isImageAttachment)
            }
            guard let cached = attachmentData[id] else { return nil }
            bytes = cached
        } else {
            return nil
        }
        // A per-file directory keeps the user-facing filename while avoiding collisions.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coder-chat-attachments", isDirectory: true)
            .appendingPathComponent(part.file_id?.uuidString ?? UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(Self.attachmentFilename(part))
            try bytes.write(to: url)
            return url
        } catch {
            logger.error("failed to stage attachment: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Prompts for a location and copies the attachment there.
    func saveAttachment(_ part: ChatMessagePart) async {
        guard let staged = await attachmentFileURL(part) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = staged.lastPathComponent
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: staged, to: dest)
        } catch {
            logger.error("failed to save attachment: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sanitized filename with an extension inferred from the MIME type — but only when the
    /// name has none (a name whose extension disagrees with the type is kept as-is, like web).
    nonisolated static func attachmentFilename(_ part: ChatMessagePart) -> String {
        var name = part.attachmentDisplayName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "attachment" }
        if (name as NSString).pathExtension.isEmpty,
           let mime = part.media_type,
           let ext = UTType(mimeType: mime)?.preferredFilenameExtension
        {
            name += ".\(ext)"
        }
        return name
    }
}
