import SwiftUI
import UniformTypeIdentifiers

func parallelAcceptDrop(_ providers: [NSItemProvider], action: @escaping (String) -> Void) -> Bool {
    guard let provider = providers.first else { return false }
    provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
        let value = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        if let value { DispatchQueue.main.async { action(value) } }
    }
    return true
}

struct ParallelTrialStrip: View {
    var trials: [ParallelTrial]
    var body: some View {
        HStack(spacing: 12) {
            Label("同じ条件の記録", systemImage: "book.closed").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            if trials.isEmpty { Text("最後まで動かすと、ここに記録が残るよ").font(.system(size: 14)).foregroundStyle(.white.opacity(0.5)) }
            ForEach(Array(trials.suffix(4))) { trial in
                HStack(spacing: 7) { Text(trial.label).lineLimit(1); Text("\(trial.ticks)手").bold() }
                    .font(.system(size: 14, design: .rounded)).padding(.horizontal,10).padding(.vertical,7)
                    .foregroundStyle(ExperienceStyle.ink).background(ExperienceStyle.paper,in:RoundedRectangle(cornerRadius:6))
            }
            Spacer(minLength:0)
        }.frame(height:35)
    }
}

struct ParallelPixelGrid: View {
    let values: [Int]
    var processed = 0
    var selected: Int?
    var select: ((Int) -> Void)?
    var body: some View {
        let columns = values.count > 4 ? 4 : 2
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:columns),spacing:3) {
            ForEach(values.indices,id:\.self) { i in
                Button { select?(i) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius:4).fill(i < processed ? Color(red:0.08 + Double(values[i])*0.20,green:0.35 + Double(values[i])*0.20,blue:0.40 + Double(values[i])*0.19) : Color(white:0.17 + Double(values[i])*0.21))
                        if selected == i { RoundedRectangle(cornerRadius:4).strokeBorder(.white,lineWidth:3) }
                    }.aspectRatio(1,contentMode:.fit)
                        .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(.black.opacity(0.65),lineWidth:2))
                }.buttonStyle(.plain).accessibilityLabel("画素\(i+1)、値\(values[i])、\(i < processed ? "加工済み" : "未加工")")
            }
        }.padding(5).background(ExperienceStyle.dark,in:RoundedRectangle(cornerRadius:7))
    }
}

struct ParallelDataCube: View {
    var label: String
    var color: Color = ExperienceStyle.cyan
    var done = false
    var body: some View {
        VStack(spacing:3) {
            ZStack { RoundedRectangle(cornerRadius:6).fill(LinearGradient(colors:[.white.opacity(0.8),color,color.opacity(0.6)],startPoint:.topLeading,endPoint:.bottomTrailing)); Image(systemName:done ? "checkmark" : "cube.fill").font(.system(size:22,weight:.semibold)).foregroundStyle(ExperienceStyle.ink.opacity(0.8)) }
                .frame(width:39,height:37).overlay(RoundedRectangle(cornerRadius:6).strokeBorder(color,lineWidth:2)).compositingGroup().shadow(color:color.opacity(0.25),radius:5)
            Text(label).font(.system(size:12,weight:.bold,design:.monospaced)).foregroundStyle(.white)
        }.accessibilityElement(children:.combine)
    }
}
