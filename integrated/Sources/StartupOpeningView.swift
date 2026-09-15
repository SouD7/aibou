import SwiftUI
import ImageIO

struct StartupOpeningView: View {
    let ready: Bool
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.92, green: 0.97, blue: 1)
            if let frame {
                Image(nsImage: frame).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("AIBOU オープニング")
            }
            Button("スキップ", action: finished)
                .keyboardShortcut(.cancelAction)
                .padding(24)
        }
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .task(id: ready) {
            do {
                guard let directory = Bundle.main.resourceURL?.appendingPathComponent("StartupMotion") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let sequence = try StartupSequence.load(from: directory)
                frame = try await loadFrame(directory.appendingPathComponent(sequence.frames[0]))
                guard ready else { return }
                if reduceMotion {
                    frame = try await loadFrame(directory.appendingPathComponent(sequence.frames[sequence.frames.count - 1]))
                    try await Task.sleep(nanoseconds: 800_000_000)
                } else {
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    var shown = 0
                    while !Task.isCancelled {
                        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                        guard elapsed < sequence.durationSeconds else { break }
                        let index = sequence.frameIndex(at: elapsed)
                        if index != shown {
                            frame = try await loadFrame(directory.appendingPathComponent(sequence.frames[index]))
                            shown = index
                        }
                        let next = min(Double(index + 1) / sequence.fps, sequence.durationSeconds)
                        let delay = max(0.001, next - (ProcessInfo.processInfo.systemUptime - startedAt))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
                try Task.checkCancellation()
                finished()
            } catch is CancellationError {
                // Skipping or closing the window cancels playback without a late completion.
            } catch {
                NSLog("AIBOU opening unavailable: %@", error.localizedDescription)
                if !Task.isCancelled { finished() }
            }
        }
    }

    private func loadFrame(_ url: URL) async throws -> NSImage {
        // Decode one frame off the main thread; do not retain all 54 full-resolution images.
        let image = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return image
        }.value
        try Task.checkCancellation()
        return NSImage(cgImage: image, size: .zero)
    }
}
