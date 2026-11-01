import AVFoundation
import Observation

/// Whatever actually makes the sound; replaced in tests.
@MainActor
protocol SpeechEngine: AnyObject {
    /// Starts reading `text`. `finished` is called when this reading ends or is cut off, and not for an earlier one.
    func start(_ text: String, finished: @escaping @MainActor () -> Void)
    func stop()
}

/// Reads answers aloud. One thing is read at a time: starting another stops the first, and `speakingID` says which
/// button should show "Stop".
@MainActor
@Observable
final class Speaker {
    private(set) var speakingID: String?
    /// Called just before speech starts, so something else that is playing (a recorded moment) can stop.
    var willSpeak: (() -> Void)?
    private let engine: any SpeechEngine

    init(engine: (any SpeechEngine)? = nil) { self.engine = engine ?? SystemSpeech() }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }

    /// Reads `text` aloud, stopping whatever was being read. Text with nothing to say is ignored.
    func speak(_ text: String, id: String = "answer") {
        let prepared = SpeechText.prepare(text)
        guard !prepared.isEmpty else { return }
        engine.stop()
        willSpeak?()
        speakingID = id
        engine.start(prepared) { [weak self] in
            if self?.speakingID == id { self?.speakingID = nil }
        }
    }

    /// A read-aloud button: starts reading, or stops if this is already being read.
    func toggle(_ text: String, id: String = "answer") {
        if speakingID == id { stop() } else { speak(text, id: id) }
    }

    func stop() {
        engine.stop()
        speakingID = nil
    }
}

/// Apple's speech synthesizer. It keeps its own audio session, so reading aloud never disturbs recording or playback settings.
@MainActor
final class SystemSpeech: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?
    private var finished: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
    }

    func start(_ text: String, finished: @escaping @MainActor () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        current = ObjectIdentifier(utterance)
        self.finished = finished
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        finished = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func end(_ id: ObjectIdentifier) {
        guard id == current else { return }
        current = nil
        let done = finished
        finished = nil
        done?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.end(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.end(id) }
    }
}
