import Foundation

/// User-visible symptoms and their possible internal causes are separate identities.
struct DiagnosticSymptom: Identifiable {
    let id: String
    let title: String
    let category: String
    let examples: [String]
    let causeIDs: [String]
}

struct DiagnosticCause: Identifiable {
    let id: String
    let title: String
    let context: DiagnosticCase
    /// Only an observable condition has a rule; its possible physical explanations do not.
    let rule: DiagnosticRule
    var isAutomatic: Bool { rule != .manual }
    var contextLabel: String { "確認の対象: \(context.title)" }
    var accessibilityLabel: String {
        isAutomatic ? "原因候補: \(title)" : "原因候補: \(title)。\(contextLabel)"
    }
}

enum DiagnosticFilter: String, CaseIterable, Identifiable {
    case all = "すべて", current = "今の候補", selected = "選択した症状"
    case automatic = "自動判定", manual = "手動判定"
    var id: String { rawValue }
    var showsCauses: Bool { self == .automatic || self == .manual }
}

/// nil override follows the observation; both true and false are intentional manual choices.
struct DiagnosticCauseSelection {
    private(set) var overrides: [String: Bool] = [:]
    var isEmpty: Bool { overrides.isEmpty }
    func manualValue(for cause: DiagnosticCause) -> Bool? { overrides[cause.id] }
    func isChecked(_ cause: DiagnosticCause, results: [String: DiagnosticResult]) -> Bool {
        overrides[cause.id] ?? (cause.isAutomatic && results[cause.context.id]?.state == .matched)
    }
    mutating func set(_ checked: Bool, for cause: DiagnosticCause) {
        if !cause.isAutomatic && !checked { overrides.removeValue(forKey: cause.id) }
        else { overrides[cause.id] = checked }
    }
    mutating func followObservation(for cause: DiagnosticCause) { overrides.removeValue(forKey: cause.id) }
    mutating func reset() { overrides.removeAll() }
}

/// Shared by the UI and tests so tabs use the same effective checkbox state.
struct DiagnosticPresentation {
    let results: [String: DiagnosticResult]
    let selection: DiagnosticCauseSelection
    let selectedSymptoms: Set<String>

    var checkedCauseIDs: Set<String> {
        Set(DiagnosticCatalog.causes.filter { selection.isChecked($0, results: results) }.map(\.id))
    }
    func symptoms(in filter: DiagnosticFilter, search: String = "", category: String? = nil) -> [DiagnosticSymptom] {
        guard !filter.showsCauses else { return [] }
        let checked = checkedCauseIDs
        return DiagnosticCatalog.symptoms.filter { symptom in
            let inTab = filter == .all || (filter == .selected && selectedSymptoms.contains(symptom.id)) ||
                (filter == .current && symptom.causeIDs.contains { checked.contains($0) })
            let causes = symptom.causeIDs.compactMap { DiagnosticCatalog.causesByID[$0] }
            let text = ([symptom.title, symptom.category] + symptom.examples + causes.flatMap { [$0.title] + $0.context.actions }).joined(separator: " ")
            return inTab && (category == nil || category == symptom.category) &&
                (search.isEmpty || text.localizedCaseInsensitiveContains(search))
        }
    }
    func causes(in filter: DiagnosticFilter, search: String = "", category: String? = nil) -> [DiagnosticCause] {
        guard filter.showsCauses else { return [] }
        return DiagnosticCatalog.causes.filter { cause in
            let related = DiagnosticCatalog.symptomsByCauseID[cause.id] ?? []
            let symptomText = related.flatMap { [$0.title] + $0.examples }
            let text = ([cause.title, cause.context.category, cause.context.title] + cause.context.actions + cause.context.symptoms + symptomText).joined(separator: " ")
            return cause.isAutomatic == (filter == .automatic) &&
                (category == nil || category == cause.context.category) &&
                (search.isEmpty || text.localizedCaseInsensitiveContains(search))
        }
    }
}

extension DiagnosticCatalog {
    static let causes: [DiagnosticCause] = cases.flatMap { entry -> [DiagnosticCause] in
        var values: [DiagnosticCause] = []
        if entry.rule != .manual {
            values.append(DiagnosticCause(id: entry.id, title: entry.title, context: entry, rule: entry.rule))
        }
        for (index, title) in entry.causes.enumerated() {
            // This sentence is a limitation, not a checkable causal hypothesis.
            if title == "メモリ部品の異常はこの値だけでは判断不可" { continue }
            values.append(DiagnosticCause(id: "\(entry.id).cause.\(index)", title: title, context: entry, rule: .manual))
        }
        return values
    }
    static let causesByID = Dictionary(uniqueKeysWithValues: causes.map { ($0.id, $0) })
    /// Build once from the explicit symptom catalog, not from the legacy case wording.
    static let symptomsByCauseID: [String: [DiagnosticSymptom]] = symptoms.reduce(into: [:]) { index, symptom in
        for causeID in symptom.causeIDs { index[causeID, default: []].append(symptom) }
    }

    // An explicit symptom catalog: never promote a cause/measurement entry into a symptom.
    // Cause IDs and symptom IDs belong to disjoint namespaces.
    static let symptoms: [DiagnosticSymptom] = [
        symptom("general-slowness", "CPU・性能", "Mac全体の操作が遅い", ["アプリの起動や切替に時間がかかる"],
                ["general-slowness", "cpu-sustained-busy", "thermal-pressure", "swap-allocated", "storage-low", "memory-pressure"]),
        symptom("single-task-slow", "CPU・性能", "一部のアプリや処理だけ遅い", ["特定の操作だけ反応が鈍い"], ["single-core-busy"]),
        symptom("beachball", "CPU・性能", "虹色の待機カーソルが長く続く", ["操作を受け付けず待たされる"], ["beachball", "cpu-sustained-busy", "swap-allocated", "storage-low"]),
        symptom("unexpected-restart", "CPU・性能", "操作中に突然再起動する", ["問題が起きた旨のメッセージが表示される"], ["unexpected-restart"]),
        symptom("freeze", "CPU・性能", "画面や入力が固まる", ["ポインタやキー入力に反応しない"], ["freeze"]),
        symptom("performance-on-battery", "CPU・性能", "電源を外すと動作が遅くなる", ["電源接続時より処理に時間がかかる"], ["performance-on-battery"]),
        symptom("benchmark-drop", "CPU・性能", "長時間使うと処理が遅くなる", ["開始直後より同じ処理に時間がかかる"], ["benchmark-drop", "thermal-pressure", "cpu-sustained-busy"]),
        symptom("hot-body", "温度・冷却", "本体が異常に熱くなる", ["特定箇所だけ触れにくいほど熱い", "置く場所によって熱さが変わる"], ["localized-hotspot", "blocked-vent", "thermal-pressure"]),
        symptom("fan-always-fast", "温度・冷却", "ファンの音がずっと大きい", ["操作していないときも冷却音が続く"], ["fan-always-fast", "thermal-pressure", "cpu-sustained-busy"]),
        symptom("fan-not-spinning", "温度・冷却", "本体が熱いのにファンの音がしない", ["負荷をかけても冷却音が変わらない"], ["fan-not-spinning", "thermal-pressure"]),
        symptom("sudden-shutdown", "バッテリー・電源", "使っている途中で電源が落ちる", ["作業中に突然終了する", "残量があるのに電源が切れる"], ["thermal-shutdown", "battery-sudden-drop", "battery-critical"]),
        symptom("cold-environment", "温度・冷却", "寒い場所で起動しない・動作が不安定になる", ["室温では使えるのに寒い場所で問題が起こる"], ["cold-environment"]),
        symptom("many-apps-slow", "メモリ", "アプリやタブを増やすと切替が遅くなる", ["別のアプリに戻るたびに待たされる"], ["memory-pressure", "swap-allocated"]),
        symptom("app-memory-errors", "メモリ", "複数のアプリが不規則に終了する", ["異なるアプリでクラッシュが続く"], ["app-memory-errors"]),
        symptom("boot-memory-beeps", "メモリ", "起動時にビープ音やエラーが出る", ["起動せず音や記号が表示される"], ["boot-memory-beeps"]),
        symptom("memory-after-upgrade", "メモリ", "メモリ交換後から起動や動作が不安定になる", ["増設後に起動失敗やクラッシュが起きる"], ["memory-after-upgrade"]),
        symptom("save-update-failure", "ストレージ", "ファイルを保存できない・更新に失敗する", ["保存やmacOS・アプリの更新が完了しない"], ["storage-low", "storage-read-write-error"]),
        symptom("file-open-failure", "ストレージ", "ファイルやフォルダを開けない・コピーに失敗する", ["読み書き中にエラーが出る", "コピーが途中で止まる"], ["storage-read-write-error", "filesystem-errors"]),
        symptom("storage-not-mounted", "ストレージ", "接続したディスクがFinderに出てこない", ["ボリュームが表示されず使用できない"], ["storage-not-mounted"]),
        symptom("storage-slow", "ストレージ", "保存やファイルの読み込みが遅い", ["保存や起動に時間がかかる"], ["storage-slow", "storage-low", "swap-allocated"]),
        symptom("disk-warning", "ストレージ", "ディスクの警告や検証エラーが表示される", ["ディスクユーティリティに致命的エラーが出る", "ディスクの検証に失敗する"], ["smart-warning", "filesystem-errors"]),
        symptom("external-drive-disconnect", "ストレージ", "外付けドライブが使用中に切断される", ["操作していないのに取り外し通知が出る"], ["external-drive-disconnect"]),
        symptom("storage-noise", "ストレージ", "ドライブから異音がする", ["クリック音や擦れる音が続く"], ["storage-noise"]),
        symptom("battery-runtime-short", "バッテリー・電源", "バッテリーの減りが早い・残量警告が出る", ["満充電から短時間で残量が減る", "電源への接続を促される"], ["battery-runtime-short", "battery-low", "battery-critical", "cpu-sustained-busy", "thermal-pressure"]),
        symptom("charging-failure", "バッテリー・電源", "電源につないでも充電が進まない", ["非充電と表示される", "つないでも外部電源として認識されない"], ["charging-paused", "adapter-not-recognized"]),
        symptom("battery-service", "バッテリー・電源", "バッテリーに修理サービス推奨と表示される", ["システム設定にバッテリー状態の警告が出る"], ["battery-service"]),
        symptom("power-on-failure", "バッテリー・電源", "電源が入らない", ["電源ボタンを押しても反応がない"], ["power-on-failure"]),
        symptom("wifi-no-network", "ネットワーク", "Wi-Fiネットワークが見つからない", ["ほかの端末には見えるネットワークが表示されない"], ["wifi-no-network"]),
        symptom("wifi-frequent-drop", "ネットワーク", "Wi-Fiが頻繁に切れる", ["接続と切断を繰り返す"], ["wifi-frequent-drop"]),
        symptom("wifi-slow", "ネットワーク", "Wi-Fiの通信が遅い", ["転送やページの読み込みに時間がかかる"], ["wifi-slow"]),
        symptom("ethernet-no-link", "ネットワーク", "有線LANをつないでも未接続になる", ["ケーブルを接続しても通信できない"], ["ethernet-no-link"]),
        symptom("bluetooth-unavailable", "ネットワーク", "Bluetoothをオンにできない・機器が見つからない", ["Bluetooth機器を検出できない"], ["bluetooth-unavailable"]),
        symptom("bluetooth-drop", "ネットワーク", "Bluetoothの音声や入力が途切れる", ["接続機器が断続的に反応しなくなる"], ["bluetooth-drop"]),
        symptom("network-only-this-mac", "ネットワーク", "このMacだけインターネットにつながらない", ["同じ回線のほかの端末は通信できる"], ["network-only-this-mac"]),
        symptom("display-black", "画面・GPU", "内蔵画面が真っ暗になる", ["動作音はあるのに画面が映らない"], ["display-black"]),
        symptom("display-flicker", "画面・GPU", "画面がちらつく", ["明るさや表示が不安定に揺れる"], ["display-flicker"]),
        symptom("display-lines", "画面・GPU", "画面に線・色むら・表示欠けが出る", ["一部が正しく表示されない"], ["display-lines"]),
        symptom("external-display-not-detected", "画面・GPU", "外部ディスプレイをつないでも映らない", ["接続した画面が検出されない"], ["external-display-not-detected"]),
        symptom("external-display-artifacts", "画面・GPU", "外部画面にノイズが出る・一瞬消える", ["表示が乱れたり瞬断したりする"], ["external-display-artifacts"]),
        symptom("gpu-heavy-lag", "画面・GPU", "動画や描画がカクつく", ["描画を伴う操作が著しく遅い"], ["gpu-heavy-lag", "thermal-pressure", "cpu-sustained-busy"]),
        symptom("camera-no-image", "画面・GPU", "内蔵カメラが映らない", ["カメラを使うアプリに映像が出ない"], ["camera-no-image"]),
        symptom("keyboard-keys", "入力・周辺機器", "キーが反応しない・勝手に連打される", ["入力が抜けたり同じ文字が続いたりする"], ["keyboard-keys"]),
        symptom("trackpad-failure", "入力・周辺機器", "トラックパッドが反応しない", ["ポインタ移動やクリックができない"], ["trackpad-failure"]),
        symptom("usb-not-recognized", "入力・周辺機器", "USB機器をつないでも使えない", ["接続した機器が認識されない"], ["usb-not-recognized"]),
        symptom("usb-overcurrent", "入力・周辺機器", "USBの電力消費に関する警告が出る", ["USB機器の使用が停止される"], ["usb-overcurrent"]),
        symptom("port-intermittent", "入力・周辺機器", "ポートの接続が途切れる", ["接続した機器が不安定に切断される"], ["port-intermittent"]),
        symptom("audio-output-failure", "入力・周辺機器", "音が出ない・音が割れる", ["スピーカーや音声出力が正常に使えない"], ["audio-output-failure"]),
        symptom("microphone-failure", "入力・周辺機器", "マイクの音が入らない・途切れる", ["音声入力が正常に使えない"], ["microphone-failure"]),
        symptom("startup-question-mark", "起動・スリープ", "疑問符フォルダが出て起動しない", ["点滅する疑問符フォルダが表示される"], ["startup-question-mark"]),
        symptom("startup-prohibited", "起動・スリープ", "禁止マークが出て起動しない", ["丸に斜線の記号が表示される"], ["startup-prohibited"]),
        symptom("startup-loop", "起動・スリープ", "起動時に再起動を繰り返す", ["ログイン前後で何度も再起動する"], ["startup-loop"]),
        symptom("sleep-wake-failure", "起動・スリープ", "スリープから復帰しない", ["画面や入力が戻らない"], ["sleep-wake-failure"]),
        symptom("unexpected-wake", "起動・スリープ", "勝手にスリープから復帰する", ["閉じた状態や夜間に起動する"], ["unexpected-wake"]),
        symptom("unexpected-sleep", "起動・スリープ", "使っている途中でスリープする", ["操作中に画面が消えて休止する"], ["unexpected-sleep", "battery-low", "battery-critical"]),
        symptom("lid-sensor", "起動・スリープ", "ふたを閉じてもスリープしない", ["ふたの開閉に応じた動作をしない"], ["lid-sensor"]),
        symptom("liquid-exposure", "外観・物理損傷", "濡れた後から入力・充電・画面が不安定になった", ["液体に触れた後から不具合が続く"], ["liquid-exposure"]),
        symptom("impact-damage", "外観・物理損傷", "落下後から画面・起動・接続が不安定になった", ["衝撃を受けた後から不具合が続く"], ["impact-damage"]),
        symptom("hinge-damage", "外観・物理損傷", "画面の開閉時に異音がする・角度を保てない", ["開閉時に擦れる", "画面がぐらつく"], ["hinge-damage"]),
        symptom("enclosure-deformation", "外観・物理損傷", "本体に変形や隙間がある", ["底面やトラックパッドが浮く", "平らな面でがたつく"], ["enclosure-deformation", "battery-swelling"]),
        symptom("burning-smell", "外観・物理損傷", "焦げ臭い・煙や火花が出る", ["焦げた臭い、煙、火花、異常音がある"], ["burning-smell"])
    ]

    private static func symptom(_ id: String, _ category: String, _ title: String,
                                _ examples: [String], _ caseIDs: [String]) -> DiagnosticSymptom {
        let contexts = Set(caseIDs)
        let linked = causes.filter { contexts.contains($0.context.id) }.map(\.id)
        return DiagnosticSymptom(id: "symptom.\(id)", title: title, category: category,
                                 examples: examples, causeIDs: linked)
    }
}
