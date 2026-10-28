import AVFoundation
import Speech

/// Live, on-device transcription of the microphone with SpeechAnalyzer.
@MainActor
final class SpeechInput {
    /// The language used when the user's own isn't supported.
    private static let fallbackLocale = Locale(identifier: "en-US")

    /// Pulls audio from the microphone.
    private let audioEngine = AVAudioEngine()
    /// The running analyzer, while listening.
    private var analyzer: SpeechAnalyzer?
    /// Feeds converted microphone buffers to the analyzer, while listening.
    private var audioInput: AsyncStream<AnalyzerInput>.Continuation?
    /// Reads the transcriber's results into `transcript`, while listening.
    private var reading: Task<Void, Error>?
    /// What has been heard since `start`.
    private var transcript = Transcript()

    /// Asks for the microphone, downloads the language's speech model if needed, then listens; `onText` hears the whole transcript each time it changes.
    func start(onStatus: @escaping (String) -> Void, onText: @escaping (String) -> Void) async throws {
        guard analyzer == nil else { return }
        try await Self.requireMicrophone()
        guard SpeechTranscriber.isAvailable else { throw VoiceError.speechUnavailable }
        let locale = try await Self.supportedLocale()
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        try await Self.installAssets(for: transcriber, locale: locale, onStatus: onStatus)
        let microphoneFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard microphoneFormat.channelCount > 0, microphoneFormat.sampleRate > 0 else { throw VoiceError.noMicrophone }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: microphoneFormat) else {
            throw VoiceError.audioFormatUnsupported
        }
        try Task.checkCancellation()
        try await listen(with: transcriber, from: microphoneFormat, to: analyzerFormat, onText: onText)
    }

    /// Stops listening and returns the final transcript, or nil if it wasn't listening.
    func stop() async -> String? {
        guard let analyzer else { return nil }
        stopAudio()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        try? await reading?.value
        reading = nil
        self.analyzer = nil
        return transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts the analyzer and the microphone tap, undoing both if either fails.
    private func listen(with transcriber: SpeechTranscriber, from microphoneFormat: AVAudioFormat, to analyzerFormat: AVAudioFormat, onText: @escaping (String) -> Void) async throws {
        let (stream, audioInput) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        transcript = Transcript()
        self.analyzer = analyzer
        self.audioInput = audioInput
        reading = Task {
            for try await result in transcriber.results {
                transcript.add(String(result.text.characters), isFinal: result.isFinal)
                onText(transcript.text)
            }
        }
        do {
            try await analyzer.start(inputSequence: stream)
            try Task.checkCancellation()
            let feed = try Self.feed(from: microphoneFormat, to: analyzerFormat, into: audioInput)
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat, block: feed)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopAudio()
            await analyzer.cancelAndFinishNow()
            reading?.cancel()
            reading = nil
            self.analyzer = nil
            throw error
        }
    }

    /// Turns the microphone off and ends the analyzer's input.
    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioInput?.finish()
        audioInput = nil
    }

    /// Asks for microphone access the first time; throws if the user turned it off.
    private static func requireMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined: if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default: break
        }
        throw VoiceError.microphoneDenied
    }

    /// The user's language if on-device transcription supports it, otherwise US English.
    private static func supportedLocale() async throws -> Locale {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) { return locale }
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: fallbackLocale) { return locale }
        throw VoiceError.languageUnsupported
    }

    /// Downloads the speech model for `locale` when it isn't on this Mac yet, reporting progress each second.
    private static func installAssets(for transcriber: SpeechTranscriber, locale: Locale, onStatus: @escaping (String) -> Void) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let language = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        let progress = request.progress
        let reporter = Task {
            while !Task.isCancelled {
                onStatus("Downloading speech recognition for \(language): \(Int(progress.fractionCompleted * 100))%")
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { reporter.cancel() }
        // Awaited through its own task so letting go of the key doesn't cancel the download.
        try await Task { try await request.downloadAndInstall() }.value
    }

    /// Builds the microphone tap, which converts each buffer to the analyzer's format; nonisolated because it runs on the audio thread.
    private nonisolated static func feed(from microphoneFormat: AVAudioFormat, to analyzerFormat: AVAudioFormat, into audioInput: AsyncStream<AnalyzerInput>.Continuation) throws -> AVAudioNodeTapBlock {
        guard let converter = AVAudioConverter(from: microphoneFormat, to: analyzerFormat) else { throw VoiceError.audioFormatUnsupported }
        let ratio = analyzerFormat.sampleRate / microphoneFormat.sampleRate
        return { buffer, _ in
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
            guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var isConsumed = false
            let status = converter.convert(to: converted, error: nil) { _, inputStatus in
                guard !isConsumed else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                isConsumed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, converted.frameLength > 0 else { return }
            audioInput.yield(AnalyzerInput(buffer: converted))
        }
    }
}
