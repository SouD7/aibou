import Foundation

@main
struct DiagnosticSearchProbe {
    static func main() {
        let presentation = DiagnosticPresentation(results: [:], selection: DiagnosticCauseSelection(), selectedSymptoms: [])
        for query in ["Mac全体の操作が遅い", "ファイルを保存できない・更新に失敗する", "本体が異常に熱くなる"] {
            let linked = Set(DiagnosticCatalog.symptoms.filter { $0.title == query }.flatMap(\.causeIDs))
            let found = presentation.causes(in: .manual, search: query) + presentation.causes(in: .automatic, search: query)
            print("\(query): linked=\(linked.count) search=\(found.count)")
        }
    }
}
