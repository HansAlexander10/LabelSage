import AVFoundation
import Speech

/// The composer's mic: speech to text on the iPhone only (`requiresOnDeviceRecognition`), so what the
/// person says never leaves it. Listening stops after a short pause or a second tap, and the words go
/// straight to LabelSage (product owner, 2026-10-27).
@Observable
final class VoiceInput {
    private(set) var isListening = false
    /// The words so far, shown live in the composer.
    private(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var pause: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?

    /// A pause this long ends the message.
    static let pauseLength: Duration = .seconds(1.6)

    /// Starts listening. `onFinish` gets the words after a pause or `stop()`; nothing when nothing was
    /// heard. Returns a line to show when voice can't start.
    func start(onFinish: @escaping (String) -> Void) async -> String? {
        guard !isListening else { return nil }
        guard await Self.authorized() else {
            return "Turn on Microphone and Speech Recognition for \(Brand.app) in Settings."
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            return "Voice isn’t ready on this iPhone. Type your question instead."
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Log.chat.failure("Voice: audio session failed", error)
            return "I can’t use the microphone right now."
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return "No microphone found." }
        // shortcut: iOS 27 deprecates this for installAudioTap, whose read-only buffers the speech request can't append yet.
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.chat.failure("Voice: audio engine failed", error)
            return "I can’t use the microphone right now."
        }
        self.request = request
        self.onFinish = onFinish
        transcript = ""
        isListening = true
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results(for: self))
        armPause()
        return nil
    }

    /// The second tap on the mic: ends listening and sends what was heard.
    func stop() { finish() }

    /// Leaving the screen: ends listening and drops the words.
    func cancel() {
        onFinish = nil
        finish()
    }

    // MARK: private

    private func heard(_ text: String?, isFinal: Bool) {
        guard isListening else { return }
        if let text { transcript = text }
        if isFinal { finish() } else { armPause() }
    }

    private func armPause() {
        pause?.cancel()
        pause = Task { [weak self] in
            try? await Task.sleep(for: Self.pauseLength)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false
        pause?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = onFinish
        onFinish = nil
        if !words.isEmpty { done?(words) }
    }

    /// The audio tap runs on an audio thread: built outside the main actor so it isn't isolated to it.
    private nonisolated static func tap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Recognition results arrive on a background queue; they hop to the main actor.
    private nonisolated static func results(for input: VoiceInput) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak input] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in input?.heard(text, isFinal: isFinal) }
        }
    }

    /// Speech recognition and the microphone, asked for on the first tap.
    private nonisolated static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
