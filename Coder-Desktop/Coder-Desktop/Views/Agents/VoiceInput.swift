import AVFoundation
import Speech
import SwiftUI

/// On-device speech-to-text for the composer's mic button, using the system Speech framework
/// (no audio leaves the machine when on-device recognition is available). Live partial
/// results are streamed back via the `onText` callback so the draft updates as you speak.
@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var isRecording = false

    /// Whether speech recognition is usable at all (a recognizer exists for the locale).
    var isSupported: Bool { recognizer?.isAvailable ?? false }

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
        // Flip synchronously so a quick second tap routes to stop() instead of starting a
        // second engine/tap (installing a second tap on the bus would crash).
        isRecording = true
        let gen = generation
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard gen == self.generation else { return } // stopped while authorizing
                guard status == .authorized else { self.isRecording = false; return }
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        guard !engine.isRunning, let recognizer, recognizer.isAvailable else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
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
            cleanup()
            return
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.onText?(result.bestTranscription.formattedString) }
                if error != nil || (result?.isFinal ?? false) { self.stop() }
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
        .help(voice.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Start voice input")
    }
}
