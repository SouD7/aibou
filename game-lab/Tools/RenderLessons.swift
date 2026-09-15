import AppKit
import SwiftUI

/// Offline production-view layout verification. No window or input events are
/// created. A disposable LessonStore supplies data; real progress is never read.
/// Compile with Core/UI and the avatar files, excluding Sources/App/App.swift.
/// Run inside a .app whose Resources contains the production lesson art.
@main
struct RenderLessons {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 2 || args.count == 3 else { fatalError("Usage: RenderLessons <output-directory> [comma-separated-capture-names]") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: args[1], isDirectory: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-render-lessons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard LessonArtwork.images.count == 3 else { fatalError("Expected all three production LessonArt poses") }
        var names: [String] = []
        let requestedNames: Set<String>? = args.count == 3 ? Set(args[2].components(separatedBy: ",")) : nil

        func store(_ key: String) -> LessonStore {
            LessonStore(saveURL: scratch.appendingPathComponent("\(key).json"))
        }
        func capture(_ store: LessonStore, _ name: String) throws {
            if let requestedNames, !requestedNames.contains(name) { return }
            let view = LessonExperienceView(store: store, close: {}, openExhibit: { _ in })
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: 1600, height: 900)
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render \(name)") }
            guard bitmap.pixelsWide == 1600 && bitmap.pixelsHigh == 900 else { fatalError("Unexpected size for \(name)") }
            try png.write(to: output.appendingPathComponent("\(name).png"))
            names.append(name)
        }

        for area in ExhibitionCatalog.areas {
            let library = store("library-\(area.id.rawValue)")
            library.area = area.id
            try capture(library, "library-\(area.id.rawValue)")
        }
        for lesson in LessonCatalog.lessons {
            try autoreleasepool {
                let lessonStore = store(lesson.id)
                lessonStore.open(lesson.id)
                try capture(lessonStore, "\(lesson.id)-1-introduction")
                lessonStore.advance()
                try capture(lessonStore, "\(lesson.id)-2-experiment")
                lessonStore.explore()
                lessonStore.advance()
                try capture(lessonStore, "\(lesson.id)-3-question")
                lessonStore.answer((lesson.challenge.correctIndex + 1) % lesson.challenge.options.count)
                try capture(lessonStore, "\(lesson.id)-3-question-incorrect")
                lessonStore.answer(lesson.challenge.correctIndex)
                try capture(lessonStore, "\(lesson.id)-3-question-correct")
                lessonStore.advance()
                try capture(lessonStore, "\(lesson.id)-4-reflection")
            }
        }

        // Overview sheets support full coverage of visual geometry, while the
        // original-size pages remain available for reading long text closely.
        for suffix in requestedNames == nil ? ["library", "1-introduction", "2-experiment", "3-question", "3-question-incorrect", "3-question-correct", "4-reflection"] : [] {
            let selected = names.filter { suffix == "library" ? $0.hasPrefix("library-") : $0.hasSuffix("-\(suffix)") }
            let sheet = VStack(spacing: 0) {
                ForEach(0..<((selected.count + 3) / 4), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { column in
                            let index = row * 4 + column
                            if index < selected.count, let image = NSImage(contentsOf: output.appendingPathComponent("\(selected[index]).png")) {
                                VStack(spacing: 0) {
                                    Text(selected[index]).font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.white).frame(width: 400, height: 25)
                                    Image(nsImage: image).resizable().frame(width: 400, height: 225)
                                }
                            } else { Color.clear.frame(width: 400, height: 250) }
                        }
                    }
                }
            }.background(Color.black)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render contact sheet") }
            try png.write(to: output.appendingPathComponent("contact-\(suffix).png"))
        }

        struct Manifest: Codable {
            let method: String
            let logicalWidth: Int
            let logicalHeight: Int
            let captures: [String]
            let limitation: String
        }
        let manifest = Manifest(method: "SwiftUI ImageRenderer of production LessonExperienceView with disposable LessonStore", logicalWidth: 1600, logicalHeight: 900, captures: names,
                                limitation: "Offline visual layout evidence. Does not exercise clicks, keyboard focus, native popovers, voice playback, or real user progress.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: output.appendingPathComponent(requestedNames == nil ? "manifest.json" : "manifest-latest.json"))
        print("Rendered \(names.count) production lesson pages at 1600 × 900 with all three guide poses. Disposable progress removed.")
    }
}
