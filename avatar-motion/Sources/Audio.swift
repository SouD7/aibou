import Foundation
import AVFoundation

struct AudioEnvelope: Equatable {
    let samplesPerSecond: Double
    let values: [Double]

    init(samplesPerSecond: Double = 60, values: [Double]) {
        self.samplesPerSecond = samplesPerSecond
        self.values = values
    }

    func amplitude(at time: TimeInterval) -> Double {
        guard !values.isEmpty, time.isFinite, time >= 0 else { return 0 }
        let position = time * samplesPerSecond
        let low = min(Int(position), values.count - 1)
        let high = min(low + 1, values.count - 1)
        let fraction = position - Double(low)
        return values[low] * (1 - fraction) + values[high] * fraction
    }

    static func load(url: URL, samplesPerSecond: Double = 60) throws -> AudioEnvelope {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0 else {
            return AudioEnvelope(samplesPerSecond: samplesPerSecond, values: [])
        }
        guard Double(file.length) / format.sampleRate <= 30 * 60 else {
            throw NSError(domain: "AIBOUAudio", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "30分以内の音声を選んでください。"])
        }
        let channelCount = Int(format.channelCount)
        let framesPerSample = max(1, Int(format.sampleRate / samplesPerSecond))
        var rmsValues: [Double] = []
        let chunkFrames: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "AIBOUAudio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "音声をPCMとして読み込めませんでした。"])
        }
        var sumSquares = 0.0
        var accumulatedFrames = 0
        while file.framePosition < file.length {
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                var perFrame = 0.0
                for channel in 0..<channelCount {
                    let sample = Double(channels[channel][frame])
                    perFrame += sample * sample
                }
                sumSquares += perFrame / Double(max(channelCount, 1))
                accumulatedFrames += 1
                if accumulatedFrames == framesPerSample {
                    let rms = sqrt(sumSquares / Double(accumulatedFrames))
                    rmsValues.append(MotionMath.clamp((rms - 0.008) * 8.5))
                    sumSquares = 0; accumulatedFrames = 0
                }
            }
        }
        if accumulatedFrames > 0 {
            let rms = sqrt(sumSquares / Double(accumulatedFrames))
            rmsValues.append(MotionMath.clamp((rms - 0.008) * 8.5))
        }
        return AudioEnvelope(samplesPerSecond: samplesPerSecond, values: rmsValues)
    }
}

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var amplitude = 0.0
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?
    private var envelope = AudioEnvelope(values: [])
    private var timer: Timer?

    func play(url: URL) {
        stop()
        do {
            envelope = try AudioEnvelope.load(url: url)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            audio.prepareToPlay()
            guard audio.play() else { throw NSError(domain: "AIBOUAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "再生を開始できませんでした。"])}
            player = audio; isPlaying = true; errorMessage = nil
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshAmplitude() }
            }
        } catch {
            errorMessage = "音声を再生できません: \(error.localizedDescription)"
            isPlaying = false; amplitude = 0
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        isPlaying = false; amplitude = 0
    }

    private func refreshAmplitude() {
        guard let player, player.isPlaying else { stop(); return }
        amplitude = envelope.amplitude(at: player.currentTime)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
