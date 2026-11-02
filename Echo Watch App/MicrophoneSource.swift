import AVFoundation
import Foundation

/// The watch's microphone as 16 kHz mono samples, delivered in whatever block sizes the system uses.
/// (In the simulator the recorded day stands in for it; this is what a real watch listens with.)
final class MicrophoneSource: @unchecked Sendable {
    enum Failure: Error { case denied, unavailable }

    private let engine = AVAudioEngine()
    private var running = false

    /// Starts listening. `onSamples` is called on the audio thread.
    func start(onSamples: @escaping @Sendable ([Int16]) -> Void) async throws {
        guard !running else { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.denied }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { throw Failure.unavailable }

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw Failure.unavailable }

        input.installTap(onBus: 0, bufferSize: 2_048, format: inFormat) { buffer, _ in
            let ratio = outFormat.sampleRate / buffer.format.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = out.int16ChannelData else { return }
            onSamples(Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength))))
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw Failure.unavailable
        }
        running = true
    }

    func stop() {
        guard running else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        running = false
    }
}
