import AppKit
import AVFoundation
import Combine

/// Local, optional narration. The caller decides when a lesson has started and
/// whether narration is enabled; nothing is spoken automatically at launch.
@MainActor
final class GuideVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var unavailableReason: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var observations: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        // Narration should never continue over another app or a hidden window.
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification,
                     NSWindow.didMiniaturizeNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            })
        }
    }

    func speak(_ text: String) {
        stop()
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
        // Prefer an installed Japanese female voice, keeping all narration local.
        let voice = voices.sorted {
            if ($0.gender == .female) != ($1.gender == .female) { return $0.gender == .female }
            if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
            return $0.identifier < $1.identifier
        }.first
        guard let voice else {
            unavailableReason = "このMacでは日本語の音声を利用できません。字幕でそのまま遊べます。"
            return
        }
        unavailableReason = nil
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.04
        utterance.volume = 0.8
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        // A callback from an interrupted line must not stop its replacement.
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        isSpeaking = false
    }

    deinit {
        synthesizer.stopSpeaking(at: .immediate)
        observations.forEach(NotificationCenter.default.removeObserver)
    }
}
