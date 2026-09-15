import SwiftUI

struct ExperienceRouterView: View {
    var gameID: String
    var onExit: () -> Void
    var body: some View {
        Group {
            switch gameID {
            case "circuit-atelier": CircuitExperienceView(onExit: onExit)
            case "bit-art": LogicBitArtView(onExit: onExit)
            case "memory-switch": LogicMemorySwitchView(onExit: onExit)
            case "tiny-switch-workshop": LogicTinySwitchView(onExit: onExit)
            case "instruction-atelier": LogicInstructionView(onExit: onExit)
            case "work-dispatch": LogicWorkDispatchView(onExit: onExit)
            case "parallel-factory": ParallelFactoryExperienceView(onExit: onExit)
            case "pixel-factory": ParallelPixelExperienceView(onExit: onExit)
            case "memory-dock": MemoryDockExperienceView(onExit: onExit)
            case "cache-delivery": MemoryCacheExperienceView(onExit: onExit)
            case "memory-rescue": MemoryRescueExperienceView(onExit: onExit)
            case "storage-warehouse": MemoryStorageExperienceView(onExit: onExit)
            case "display-studio": ParallelDisplayExperienceView(onExit: onExit)
            case "packet-express": ParallelPacketExperienceView(onExit: onExit)
            case "board-town": ParallelBoardExperienceView(onExit: onExit)
            case "connection-lab": ParallelConnectionExperienceView(onExit: onExit)
            case "pc-day": MemoryPCDayExperienceView(onExit: onExit)
            case "battery-voyage": MemoryBatteryExperienceView(onExit: onExit)
            case "cooling-workshop": CoolingExperienceView(onExit: onExit)
            case "bottleneck-detective": BottleneckExperienceView(onExit: onExit)
            default: VStack { Text("この体験を開けませんでした"); Button("展示室へ", action: onExit) }
            }
        }.id(gameID)
    }
}
