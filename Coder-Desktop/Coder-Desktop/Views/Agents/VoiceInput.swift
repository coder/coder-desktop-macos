import AVFoundation
import os
import Speech
import SwiftUI

/// On-device speech-to-text for the composer's mic button, using the system Speech framework
/// (no audio leaves the machine when on-device recognition is available). Live partial
/// results are streamed back via the `onText` callback so the draft updates as you speak.
@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var isRecording = false
    /// User-facing reason the last attempt failed (shown as a popover on the mic button) —
    /// without it a failure reads as the button silently flipping back to idle.
    @Published var failureMessage: String?

    /// Whether on-device speech recognition is usable (a recognizer exists for the locale AND it
    /// can run on-device). We require on-device so dictated audio never leaves the machine.
    var isSupported: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "voice-input")
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?
    // Bumped on stop() so a stale authorization callback can't start a session we cancelled.
    private var generation = 0

    func toggle(onText: @escaping (String) -> Void) {
        if isRecording { stop() } else { start(onText: onText) }
    }

    private func start(onText: @escaping (String) -> Void) {
        self.onText = onText
        failureMessage = nil
        // Flip synchronously so a quick second tap routes to stop() instead of starting a
        // second engine/tap (installing a second tap on the bus would crash).
        isRecording = true
        let gen = generation
        // @Sendable so the closure does NOT inherit this method's MainActor isolation: TCC
        // invokes it on a background queue, and an isolated closure traps at entry (runtime
        // isolation assert) before the Task hop below can run.
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in
                guard gen == self.generation else { return } // stopped while authorizing
                guard status == .authorized else {
                    self.logger.error("speech authorization not granted: \(status.rawValue)")
                    self.isRecording = false
                    return
                }
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        guard !engine.isRunning, let recognizer, recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { isRecording = false; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // never send dictated audio to Apple's cloud
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Capture the request value, not self: the tap block runs on the realtime audio
        // thread, so it must not touch MainActor-isolated state.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            logger.error("audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            cleanup()
            return
        }
        // Same trap as the authorization callback: Speech delivers results on its own queue, so
        // the handler must be @Sendable (nonisolated). Extract the Sendable pieces before the
        // hop — SFSpeechRecognitionResult itself can't cross into the MainActor task.
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failure = error.map { "\($0)" }
            // kLSRErrorDomain 201: on-device assets exist only when Siri or Dictation is on.
            let dictationOff = (error as NSError?).map { $0.domain == "kLSRErrorDomain" && $0.code == 201 } ?? false
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.onText?(text) }
                if let failure {
                    self.logger.error("recognition failed: \(failure, privacy: .public)")
                    self.failureMessage = dictationOff
                        ? "Voice input needs Dictation: System Settings → Keyboard → Dictation."
                        : "Voice input failed. Check microphone access in System Settings → Privacy."
                }
                if failure != nil || isFinal { self.stop() }
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        request?.endAudio()
        cleanup()
    }

    private func cleanup() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
    }
}

/// The composer's mic toggle. Captures the current draft as a base, then live-appends the
/// transcription as the user speaks.
struct VoiceInputButton: View {
    @Binding var draft: String
    @StateObject private var voice = VoiceInput()
    @State private var base = ""

    var body: some View {
        Button {
            if !voice.isRecording { base = draft }
            voice.toggle { transcript in
                draft = base.isEmpty ? transcript : base + " " + transcript
            }
        } label: {
            Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(voice.isRecording ? Color.red : .secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!voice.isSupported)
        .help(voice.isSupported
            ? (voice.isRecording ? "Stop voice input" : "Voice input")
            : "On-device dictation isn't available on this Mac")
        .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Start voice input")
        .popover(isPresented: Binding(
            get: { voice.failureMessage != nil },
            set: { if !$0 { voice.failureMessage = nil } }
        ), arrowEdge: .top) {
            Text(voice.failureMessage ?? "")
                .font(.caption)
                .padding(10)
                .frame(maxWidth: 280)
        }
        // Deterministically stop if the composer goes away mid-recording so the mic indicator
        // doesn't linger until the @StateObject is eventually deallocated.
        .onDisappear { voice.stop() }
    }
}
