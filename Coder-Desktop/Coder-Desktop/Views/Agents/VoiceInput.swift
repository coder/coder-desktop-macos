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
    /// Smoothed input loudness (0–1) while recording, driving the mic button's pulse.
    @Published private(set) var level: Double = 0
    /// User-facing reason the last attempt failed (shown as a popover on the mic button) —
    /// without it a failure reads as the button silently flipping back to idle.
    @Published var failureMessage: String?
    /// Deep link to the System Settings pane that fixes the failure, when one applies.
    @Published var failureSettingsURL: URL?

    /// Whether on-device speech recognition is usable (a recognizer exists for the locale AND it
    /// can run on-device). We require on-device so dictated audio never leaves the machine.
    var isSupported: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "voice-input")
    // Lazy: the composer's `@State VoiceInput()` initializer runs on every parent body eval
    // (several/sec during runs) and the throwaways must not each build an audio engine and a
    // speech recognizer. Only the retained instance ever touches these.
    private lazy var recognizer = SFSpeechRecognizer()
    private lazy var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var onText: ((String) -> Void)?
    // On-device recognition restarts its transcript after each silence (utterance boundary),
    // so finished utterances are folded in here — otherwise sentence 2 REPLACES sentence 1.
    private var committed = ""
    // Bumped on stop() so a stale authorization callback can't start a session we cancelled,
    // and a recognition result already in flight can't repopulate a just-cleared draft.
    private var generation = 0

    func toggle(onText: @escaping (String) -> Void) {
        if isRecording { stop() } else { start(onText: onText) }
    }

    private func start(onText: @escaping (String) -> Void) {
        self.onText = onText
        failureMessage = nil
        failureSettingsURL = nil
        committed = ""
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
                    self.fail(
                        "Speech recognition permission was denied.",
                        settingsPane: "com.apple.preference.security?Privacy_SpeechRecognition"
                    )
                    return
                }
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        guard !engine.isRunning, isSupported else {
            fail("Speech recognition is unavailable right now.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // never send dictated audio to Apple's cloud
        self.request = request

        installTap(feeding: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            logger.error("audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            cleanup()
            fail(
                "Couldn't start the microphone.",
                settingsPane: "com.apple.preference.security?Privacy_Microphone"
            )
            return
        }
        // Same trap as the authorization callback: Speech delivers results on its own queue, so
        // the handler must be @Sendable (nonisolated). Extract the Sendable pieces before the
        // hop — SFSpeechRecognitionResult itself can't cross into the MainActor task.
        let gen = generation
        task = recognizer?.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failure = error.map { "\($0)" }
            // kLSRErrorDomain 201: on-device assets exist only when Siri or Dictation is on.
            let dictationOff = (error as NSError?).map { $0.domain == "kLSRErrorDomain" && $0.code == 201 } ?? false
            // Non-nil metadata marks an utterance boundary — the next partial starts a FRESH
            // transcript, so the finished text must be committed or it would be overwritten.
            let utteranceEnded = result?.speechRecognitionMetadata != nil
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                if let text, !text.isEmpty {
                    let combined = self.committed.isEmpty ? text : self.committed + " " + text
                    self.onText?(combined)
                    if utteranceEnded { self.committed = combined }
                }
                if let failure {
                    self.logger.error("recognition failed: \(failure, privacy: .public)")
                    self.fail(
                        dictationOff
                            ? "Voice input needs Dictation, which is turned off."
                            : "Voice input failed. Check the app's microphone access.",
                        settingsPane: dictationOff
                            ? "com.apple.Keyboard-Settings.extension?Dictation"
                            : "com.apple.preference.security?Privacy_Microphone"
                    )
                }
                if failure != nil || isFinal { self.stop() }
            }
        }
    }

    /// Feeds mic buffers to the recognition request and derives the loudness level.
    private func installTap(feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // @Sendable so the tap doesn't inherit this method's MainActor isolation — AVAudio
        // invokes it on its realtime messenger queue and an isolated closure traps at entry
        // (the third such trap in this file; every SDK callback here is queue-agnostic).
        // `append(from:)` is the documented audio-thread usage for the request.
        nonisolated(unsafe) let tapRequest = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            tapRequest.append(buffer)
            // RMS loudness for the button's pulse; ~47 buffers/sec, computed off-main.
            guard let self, let channel = buffer.floatChannelData?.pointee else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0 ..< frames { sum += channel[i] * channel[i] }
            // ×6 maps typical speech RMS (~0.05–0.15) onto the halo's mid-range.
            let loudness = min(1.0, Double((sum / Float(frames)).squareRoot()) * 6)
            Task { @MainActor in
                // Fast attack, slow decay, so the pulse tracks speech without flickering.
                self.level = loudness > self.level ? loudness : self.level * 0.7 + loudness * 0.3
            }
        }
        tapInstalled = true
    }

    func stop() {
        generation += 1
        task?.cancel()
        request?.endAudio()
        cleanup()
    }

    /// Every failure surfaces through the popover — a silent flip back to idle reads as a
    /// dead button (and did, repeatedly, before this existed).
    private func fail(_ message: String, settingsPane: String? = nil) {
        failureMessage = message
        failureSettingsURL = settingsPane.flatMap { URL(string: "x-apple.systempreferences:\($0)") }
        isRecording = false
    }

    private func cleanup() {
        // Gate on the tap: `engine.inputNode` can raise (uncatchable from Swift) on a Mac with
        // no input device, and stop() runs unconditionally from onDisappear.
        if tapInstalled {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request = nil
        task = nil
        onText = nil
        isRecording = false
        level = 0
    }
}

/// The composer's mic toggle. Captures the current draft as a base, then live-appends the
/// transcription as the user speaks. The `VoiceInput` is owned by the composer (not here) so
/// the send path can stop dictation synchronously before clearing the draft.
struct VoiceInputButton: View {
    @Binding var draft: String
    @ObservedObject var voice: VoiceInput
    @State private var base = ""

    var body: some View {
        Button {
            if !voice.isRecording { base = draft }
            voice.toggle { transcript in
                draft = base.isEmpty ? transcript : base + " " + transcript
            }
        } label: {
            ZStack {
                if voice.isRecording {
                    // Loudness-driven halo: scales with the live mic level so it visibly
                    // pulses while you speak (scaleEffect doesn't affect layout).
                    Circle()
                        .fill(Color.red.opacity(0.2 + voice.level * 0.2))
                        .frame(width: 22, height: 22)
                        .scaleEffect(1 + voice.level * 1.2)
                        .animation(.easeOut(duration: 0.12), value: voice.level)
                }
                Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(voice.isRecording ? Color.red : .secondary)
            }
            .frame(width: 24, height: 24)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(voice.failureMessage ?? "")
                    .font(.caption)
                    // A fixed width (not maxWidth) forces wrapping — popover sizing otherwise
                    // collapses the text to one truncated line.
                    .fixedSize(horizontal: false, vertical: true)
                if let url = voice.failureSettingsURL {
                    Button("Open Settings…") {
                        NSWorkspace.shared.open(url)
                        voice.failureMessage = nil
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(width: 240)
        }
        // Manually clearing the draft while dictating stops listening (the send path stops
        // synchronously via its owned VoiceInput; this covers select-all-delete).
        .onChange(of: draft) { _, new in
            if new.isEmpty, voice.isRecording { voice.stop() }
        }
        // Deterministically stop if the composer goes away mid-recording so the mic indicator
        // doesn't linger until the owner is eventually deallocated.
        .onDisappear { voice.stop() }
    }
}
