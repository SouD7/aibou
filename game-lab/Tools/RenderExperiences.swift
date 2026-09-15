import AppKit
import SwiftUI

/// Render the production experience shell and apparatus with isolated stores.
/// No production application, visible window, live monitor, or user progress is opened.
@main
struct RenderExperiences {
    struct Capture: Codable {
        var name: String
        var gameID: String
        var stage: Int
        var phase: String
        var complete: Bool
        var metrics: [ExperienceMetric]
    }
    struct PersistenceCheck: Codable {
        var gameID: String
        var passed: Bool
        var checks: [String]
        var error: String?
    }
    struct Manifest: Codable {
        var method: String
        var width = 1600
        var height = 900
        var captures: [Capture]
        var persistence: [PersistenceCheck]
        var contactSheets: [String]
        var limitations: String
    }
    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    @MainActor static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let destination = args.first, !destination.hasPrefix("--") else {
            throw Failure("Usage: RenderExperiences <output-directory> [--games comma-separated-ids] [--stages 1,2,3,4,5] [--skip-persistence] [--only-representative] [--layout-probes] [--image-renderer]")
        }
        func argument(_ name: String) -> String? { args.firstIndex(of:name).flatMap { $0 + 1 < args.count ? args[$0+1] : nil } }
        let requested = argument("--games").map { Set($0.components(separatedBy:",")) }
        let stages = argument("--stages").map { $0.components(separatedBy:",").compactMap(Int.init) } ?? Array(1...5)
        guard !stages.isEmpty, stages.allSatisfy({(1...5).contains($0)}) else { throw Failure("Stages must be 1...5") }
        let checkPersistence = !args.contains("--skip-persistence")
        let useImageRenderer = args.contains("--image-renderer")
        let onlyRepresentative = args.contains("--only-representative")
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath:destination,isDirectory:true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-experience-render-stores-" + UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:scratch) }
        guard LessonArtwork.images.count == 3 else { throw Failure("Production guide artwork is missing") }
        var captures: [Capture] = []
        var verification: [PersistenceCheck] = []
        var failures: [String] = []
        var processedIDs: [String] = []

        func require(_ condition: Bool, _ explanation: String) throws { if !condition { throw Failure(explanation) } }
        func capture<M: ExperienceModel,V: View>(_ store: ExperienceStore<M>, _ prefix: String, _ phase: String, size: NSSize = NSSize(width:1600,height:900), _ apparatus: @escaping (M,@escaping (M.Action)->Void)->V) throws {
            let name = "\(prefix)-stage\(store.model.stage)-\(phase)"
            let view = ExperienceScreen(store:store,onExit:{},content:apparatus)
                .environment(\.colorScheme,.light)
                .environment(\.scenePhase,.active)
                .frame(width:size.width,height:size.height)
            let image: NSImage?
            if useImageRenderer {
                let renderer = ImageRenderer(content:view)
                renderer.scale = 1
                renderer.proposedSize = ProposedViewSize(width:size.width,height:size.height)
                image = renderer.nsImage
            } else { image = try hostingImage(view,size:size) }
            try writeImage(image,to:output.appendingPathComponent(name + ".png"),expected:size)
            captures.append(Capture(name:name,gameID:M.gameID,stage:store.model.stage,phase:phase,complete:store.model.isComplete,metrics:store.model.metrics))
        }

        func run<M: ExperienceModel,V: View>(_ number: Int, _ initial: M, mutation: M.Action, solve: (ExperienceStore<M>)->Void, apparatus: @escaping (M,@escaping (M.Action)->Void)->V) {
            guard !onlyRepresentative else { return }
            guard requested == nil || requested!.contains(M.gameID) else { return }
            processedIDs.append(M.gameID)
            let prefix = String(format:"%02d-",number) + M.gameID
            do {
                for stage in stages {
                    try autoreleasepool {
                        let model = M(stage:stage)
                        try require(model.isValid,"\(M.gameID) initial stage \(stage) is invalid")
                        let store = ExperienceStore(model,inMemory:true)
                        try capture(store,prefix,"initial",apparatus)
                    }
                }
                if checkPersistence {
                    try autoreleasepool {
                        let url = scratch.appendingPathComponent(M.gameID + ".json")
                        let store = ExperienceStore(initial,saveURL:url)
                        try require(!store.model.isComplete,"\(M.gameID) stage 1 must begin incomplete")
                        store.predict("QA: 課題1の手順で成功条件を満たす",reason:"仕様に定義されたモデル操作を順に行う")
                        solve(store)
                        try require(store.model.isComplete,"\(M.gameID) stage 1 solution did not complete: \(store.model.guide)")
                        try require(store.model.isValid && store.saveError.isEmpty,"\(M.gameID) current state/save invalid")
                        store.rememberComparison()
                        store.recordDiscovery("QA: 課題1の成功状態を保存した")
                        try require(store.saveArtifact(),"\(M.gameID) artifact was not saved")
                        try require(store.artifacts.count == 1 && store.completedStages == [1],"\(M.gameID) completion record mismatch")
                        let snapshot = store.model
                        let artifact = store.artifacts[0]
                        try capture(store,prefix,"complete",apparatus)
                        let reopened = ExperienceStore(M(stage:1),saveURL:url)
                        try require(!reopened.blockedSave && reopened.saveError.isEmpty,"\(M.gameID) persisted record was rejected")
                        try require(reopened.model == snapshot && reopened.artifacts == store.artifacts && reopened.comparisons == store.comparisons && reopened.reflections == store.reflections && reopened.completedStages == [1],"\(M.gameID) reloaded record differs")
                        try capture(reopened,prefix,"resumed",apparatus)
                        var replay = artifact.model
                        replay.send(mutation)
                        try require(replay != artifact.model,"\(M.gameID) replay mutation did not exercise a change")
                        try require(replay.isValid && reopened.artifacts[0] == artifact && reopened.model == snapshot,"\(M.gameID) replay changed the original record")
                        reopened.selectStage(2)
                        try require(reopened.artifacts == [artifact],"\(M.gameID) changing stage changed the saved work")
                        let afterEdit = ExperienceStore(M(stage:1),saveURL:url)
                        try require(afterEdit.model.stage == 2 && afterEdit.artifacts == [artifact] && afterEdit.comparisons == store.comparisons && afterEdit.reflections == store.reflections,"\(M.gameID) second reload changed a saved snapshot")
                        verification.append(PersistenceCheck(gameID:M.gameID,passed:true,checks:["stage 1 starts incomplete","model actions reach success","real ExperienceStore saves artifact, comparison, prediction and discovery","new store restores equal model, artifacts, comparison, reflection and completion","replay actions change only the copied model","working-stage edits preserve immutable artifact across another reload"],error:nil))
                    }
                }
                print("Rendered \(prefix): \(stages.count) initial stages\(checkPersistence ? ", success/save/resume passed" : "")")
                fflush(stdout)
            } catch {
                let message = "\(M.gameID): \(error)"
                failures.append(message)
                verification.append(PersistenceCheck(gameID:M.gameID,passed:false,checks:[],error:message))
                print("FAILED \(message)"); fflush(stdout)
            }
        }

        run(1,LogicBitArtModel(stage:1),mutation:.toggle(0),solve:{ s in s.send(.record);s.send(.toggle(0));s.send(.record) }) { LogicBitArtApparatus(model:$0,send:$1) }
        run(2,CircuitExperienceModel(stage:1),mutation:.toggleInput(.a),solve:{ $0.send(.begin) }) { CircuitExperienceApparatus(model:$0,send:$1) }
        run(3,LogicMemorySwitchModel(stage:1),mutation:.toggle(0),solve:{ s in s.send(.record);s.send(.toggle(0));s.send(.record) }) { LogicMemorySwitchApparatus(model:$0,send:$1) }
        run(4,LogicTinySwitchModel(stage:1),mutation:.toggle(0),solve:{ s in s.send(.place(0));s.send(.connect(0));s.send(.test) }) { LogicTinySwitchApparatus(model:$0,send:$1) }
        run(5,LogicInstructionModel(stage:1),mutation:.rewind,solve:{ s in s.send(.append(.read));s.send(.append(.output));s.send(.step);s.send(.step) }) { LogicInstructionApparatus(model:$0,send:$1) }
        run(6,LogicWorkDispatchModel(stage:1),mutation:.rewind,solve:{ s in s.send(.admit(0));for _ in 0..<3 { s.send(.step) } }) { LogicWorkDispatchApparatus(model:$0,send:$1) }
        run(7,ParallelFactoryModel(stage:1),mutation:.reset,solve:{ s in
            for _ in 0..<8 { s.send(.step) };s.send(.workers(2));s.send(.assign(1,1));s.send(.assign(3,1));for _ in 0..<4 { s.send(.step) }
        }) { ParallelFactoryApparatus(model:$0,send:$1) }
        run(8,ParallelPixelModel(stage:1),mutation:.reset,solve:{ s in
            for _ in 0..<4 { s.send(.step) };s.send(.device(true));for _ in 0..<4 { s.send(.step) }
        }) { ParallelPixelApparatus(model:$0,send:$1) }
        run(9,MemoryDockModel(stage:1),mutation:.observe,solve:{ s in s.send(.open);s.send(.edit);s.send(.observe);s.send(.save) }) { MemoryDockApparatus(model:$0,send:$1) }
        run(10,MemoryCacheModel(stage:1),mutation:.restart,solve:{ s in
            for _ in 0..<100 { if s.model.finished { break };if s.model.pending != nil { s.send(.replace(s.model.cache.first)) } else { s.send(.step) } }
        }) { MemoryCacheApparatus(model:$0,send:$1) }
        run(11,MemoryRescueModel(stage:1),mutation:.restart,solve:{ s in for _ in 0..<4 { s.send(.step) } }) { MemoryRescueApparatus(model:$0,send:$1) }
        run(12,MemoryStorageModel(stage:1),mutation:.restart,solve:{ s in s.send(.capacity(16));for _ in 0..<40 { if s.model.finished { break };s.send(.step) } }) { MemoryStorageApparatus(model:$0,send:$1) }
        run(13,ParallelDisplayModel(stage:1),mutation:.reset,solve:{ s in
            for _ in 0..<60 { s.send(.step) };s.send(.fps(30));for _ in 0..<60 { s.send(.step) }
        }) { ParallelDisplayApparatus(model:$0,send:$1) }
        run(14,ParallelPacketModel(stage:1),mutation:.reset,solve:{ s in s.send(.connection(true));for _ in 0..<5 { s.send(.step) } }) { ParallelPacketApparatus(model:$0,send:$1) }
        run(15,ParallelBoardModel(stage:1),mutation:.reset,solve:{ s in s.send(.connect(true));for _ in 0..<6 { s.send(.step) } }) { ParallelBoardApparatus(model:$0,send:$1) }
        run(16,ParallelConnectionModel(stage:1),mutation:.disconnect(0),solve:{ s in s.send(.connect(0));s.send(.inspect) }) { ParallelConnectionApparatus(model:$0,send:$1) }
        run(17,MemoryPCDayModel(stage:1),mutation:.clear,solve:{ s in s.send(.append(.open));s.send(.append(.display));for _ in 0..<20 { if s.model.current == nil { break };s.send(.step) } }) { MemoryPCDayApparatus(model:$0,send:$1) }
        run(18,MemoryBatteryModel(stage:1),mutation:.restart,solve:{ s in for _ in 0..<6 { s.send(.step) } }) { MemoryBatteryApparatus(model:$0,send:$1) }
        run(19,CoolingModel(stage:1),mutation:.retry,solve:{ s in for _ in 0..<4 { s.send(.step) };s.send(.fast(true));for _ in 0..<4 { s.send(.step) } }) { CoolingApparatus(model:$0,send:$1) }
        run(20,BottleneckModel(stage:1),mutation:.retry,solve:{ s in for _ in 0..<8 { s.send(.step) };s.send(.inspect(2)) }) { BottleneckApparatus(model:$0,send:$1) }

        func representative<M: ExperienceModel,V: View>(_ number: Int, _ model: @autoclosure ()->M, apparatus: @escaping (M,@escaping (M.Action)->Void)->V) {
            guard requested == nil || requested!.contains(M.gameID) else { return }
            if !processedIDs.contains(M.gameID) { processedIDs.append(M.gameID) }
            do {
                try autoreleasepool {
                    let value = model()
                    try require(value.isValid,"\(M.gameID) representative state is invalid")
                    try capture(ExperienceStore(value,inMemory:true),String(format:"%02d-",number)+M.gameID,"representative",apparatus)
                }
                print("Rendered representative \(M.gameID)");fflush(stdout)
            } catch { failures.append("\(M.gameID) representative: \(error)") }
        }
        representative(1,LogicRepresentative.bitArt()) { LogicBitArtApparatus(model:$0,send:$1) }
        representative(2,LogicRepresentative.circuit()) { CircuitExperienceApparatus(model:$0,send:$1) }
        representative(3,LogicRepresentative.memorySwitch()) { LogicMemorySwitchApparatus(model:$0,send:$1) }
        representative(4,LogicRepresentative.tinySwitch()) { LogicTinySwitchApparatus(model:$0,send:$1) }
        representative(5,LogicRepresentative.instruction()) { LogicInstructionApparatus(model:$0,send:$1) }
        representative(6,LogicRepresentative.dispatch()) { LogicWorkDispatchApparatus(model:$0,send:$1) }
        representative(7,ParallelRepresentative.factory()) { ParallelFactoryApparatus(model:$0,send:$1) }
        representative(8,ParallelRepresentative.pixel()) { ParallelPixelApparatus(model:$0,send:$1) }
        representative(9,MemoryRepresentative.dock()) { MemoryDockApparatus(model:$0,send:$1) }
        representative(10,MemoryRepresentative.cache()) { MemoryCacheApparatus(model:$0,send:$1) }
        representative(11,MemoryRepresentative.rescue()) { MemoryRescueApparatus(model:$0,send:$1) }
        representative(12,MemoryRepresentative.storage()) { MemoryStorageApparatus(model:$0,send:$1) }
        representative(13,ParallelRepresentative.display()) { ParallelDisplayApparatus(model:$0,send:$1) }
        representative(14,ParallelRepresentative.packet()) { ParallelPacketApparatus(model:$0,send:$1) }
        representative(15,ParallelRepresentative.board()) { ParallelBoardApparatus(model:$0,send:$1) }
        representative(16,ParallelRepresentative.connection()) { ParallelConnectionApparatus(model:$0,send:$1) }
        representative(17,MemoryRepresentative.pcDay()) { MemoryPCDayApparatus(model:$0,send:$1) }
        representative(18,MemoryRepresentative.battery()) { MemoryBatteryApparatus(model:$0,send:$1) }
        representative(19,ThermalRepresentative.cooling()) { CoolingApparatus(model:$0,send:$1) }
        representative(20,ThermalRepresentative.bottleneck()) { BottleneckApparatus(model:$0,send:$1) }

        // UI stress states for the final mechanical-layout changes. Pure model actions;
        // no production progress or extra success assertions are written by these captures.
        if args.contains("--layout-probes") {
            do {
                try capture(ExperienceStore(LogicInstructionModel(stage:5),inMemory:true),"05-instruction-atelier","layout-initial") { LogicInstructionApparatus(model:$0,send:$1) }
                var instruction = LogicInstructionModel(stage:5)
                for op in [LogicInstructionModel.Instruction.read,.addOne,.output,.jump1] { instruction.send(.append(op)) }
                for _ in 0..<11 { instruction.send(.step) }
                try require(instruction.output == [1,3,5],"Instruction layout fixture must show three output cards")
                try capture(ExperienceStore(instruction,inMemory:true),"05-instruction-atelier","layout-output-three") { LogicInstructionApparatus(model:$0,send:$1) }
                try capture(ExperienceStore(LogicWorkDispatchModel(stage:4),inMemory:true),"06-work-dispatch","layout-initial") { LogicWorkDispatchApparatus(model:$0,send:$1) }
                var dispatch = LogicWorkDispatchModel(stage:4)
                dispatch.send(.admit(0));dispatch.send(.admit(1));dispatch.send(.select(0));dispatch.send(.step);dispatch.send(.select(1))
                try require(dispatch.jobs[0].ioRemaining == 2 && dispatch.selected == 1,"Dispatch layout fixture must show waiting and selected CPU work")
                try capture(ExperienceStore(dispatch,inMemory:true),"06-work-dispatch","layout-io-wait") { LogicWorkDispatchApparatus(model:$0,send:$1) }
                var factory = ParallelFactoryModel(stage:2)
                factory.send(.inspect(5))
                try capture(ExperienceStore(factory,inMemory:true),"07-parallel-factory","layout-dependencies") { ParallelFactoryApparatus(model:$0,send:$1) }
                factory = ParallelFactoryModel(stage:3);factory.send(.workers(4))
                try capture(ExperienceStore(factory,inMemory:true),"07-parallel-factory","layout-four-workers") { ParallelFactoryApparatus(model:$0,send:$1) }
                try capture(ExperienceStore(factory,inMemory:true),"07-parallel-factory","layout-small-window",size:NSSize(width:1100,height:690)) { ParallelFactoryApparatus(model:$0,send:$1) }
                try capture(ExperienceStore(CoolingModel(stage:5),inMemory:true),"19-cooling-workshop","layout-controls") { CoolingApparatus(model:$0,send:$1) }
                var pipeline = BottleneckModel(stage:1)
                for _ in 0..<3 { pipeline.send(.step) }
                try capture(ExperienceStore(pipeline,inMemory:true),"20-bottleneck-detective","layout-long-queue") { BottleneckApparatus(model:$0,send:$1) }
            } catch { failures.append("Layout probes: \(error)") }
        }

        if let requested { let missing = requested.subtracting(processedIDs);if !missing.isEmpty { failures.append("Unknown requested games: \(missing.sorted().joined(separator:","))") } }
        var sheets: [String] = []
        for stage in stages {
            let selected = captures.filter { $0.stage == stage && $0.phase == "initial" }
            if !selected.isEmpty { let name = "contact-stage\(stage).png";try contactSheet(selected,output:output,name:name,columns:4);sheets.append(name) }
        }
        let initialCaptures = captures.filter { $0.phase == "initial" }
        if !initialCaptures.isEmpty { try contactSheet(initialCaptures,output:output,name:"contact-all-initial.png",columns:5);sheets.append("contact-all-initial.png") }
        let completed = captures.filter { $0.phase == "complete" }
        if !completed.isEmpty { try contactSheet(completed,output:output,name:"contact-complete.png",columns:4);sheets.append("contact-complete.png") }
        let representativeCaptures = captures.filter { $0.phase == "representative" }
        if !representativeCaptures.isEmpty { try contactSheet(representativeCaptures,output:output,name:"contact-representative.png",columns:4);sheets.append("contact-representative.png") }
        let manifest = Manifest(method:"\(useImageRenderer ? "SwiftUI ImageRenderer (drag/drop representables may show unsupported placeholders)" : "NSHostingView offscreen native bitmap in an unshown window (supports macOS drag/drop representables)") of production ExperienceScreen and \(processedIDs.count) actual apparatus views; 3 production girl poses; in-memory initial stores and disposable real-file persistence stores",captures:captures,persistence:verification,contactSheets:sheets,limitations:"Offline 1600×900 layout and model/store evidence. Does not exercise physical mouse/keyboard input, native popovers, voice output, app routing, frame pacing, or user progress. Persistence uses actual ExperienceStore and deletes only this run's temporary directory. Source hashes are recorded in source-snapshot.sha256.")
        let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(manifest).write(to:output.appendingPathComponent("manifest.json"),options:.atomic)
        print("Saved \(captures.count) production-view PNGs, \(sheets.count) contact sheets; \(verification.filter(\.passed).count) save/reopen checks passed. Output: \(output.path)")
        if !failures.isEmpty { throw Failure(failures.joined(separator:"\n")) }
    }

    @MainActor static func hostingImage<V: View>(_ view: V, size: NSSize = NSSize(width:1600,height:900)) throws -> NSImage {
        let bounds = NSRect(origin:.zero,size:size)
        let host = NSHostingView(rootView:view)
        let window = NSWindow(contentRect:bounds,styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = bounds
        defer { window.contentView = nil;window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Flush pending native representable layout without opening a window or
        // generating events. Playback buttons remain in their stopped state.
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.025))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:Int(size.width)*4,bitsPerPixel:32) else { throw Failure("Cannot allocate native rendering bitmap") }
        bitmap.size = bounds.size
        host.cacheDisplay(in:bounds,to:bitmap)
        let image = NSImage(size:bounds.size);image.addRepresentation(bitmap)
        return image
    }

    @MainActor static func writeImage(_ image: NSImage?, to url: URL, expected: NSSize? = nil) throws {
        guard let image,let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data:tiff),let png = bitmap.representation(using:.png,properties:[:]) else { throw Failure("Could not render \(url.lastPathComponent)") }
        if let expected, bitmap.pixelsWide != Int(expected.width) || bitmap.pixelsHigh != Int(expected.height) { throw Failure("Unexpected image size: \(url.lastPathComponent)") }
        try png.write(to:url,options:.atomic)
    }
    @MainActor static func contactSheet(_ captures: [Capture], output: URL, name: String, columns: Int) throws {
        let thumbWidth = 1600 / columns
        let thumbHeight = thumbWidth * 9 / 16
        let sheet = VStack(spacing:0) {
            ForEach(0..<((captures.count + columns - 1) / columns),id:\.self) { row in
                HStack(spacing:0) {
                    ForEach(0..<columns,id:\.self) { col in
                        let i = row * columns + col
                        if i < captures.count,let image = NSImage(contentsOf:output.appendingPathComponent(captures[i].name + ".png")) {
                            VStack(spacing:0) {
                                Text(captures[i].name).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(.white).frame(width:CGFloat(thumbWidth),height:24)
                                Image(nsImage:image).resizable().frame(width:CGFloat(thumbWidth),height:CGFloat(thumbHeight))
                            }
                        } else { Color.clear.frame(width:CGFloat(thumbWidth),height:CGFloat(thumbHeight+24)) }
                    }
                }
            }
        }.background(Color.black)
        let renderer = ImageRenderer(content:sheet);renderer.scale = 1
        try writeImage(renderer.nsImage,to:output.appendingPathComponent(name))
    }
}
