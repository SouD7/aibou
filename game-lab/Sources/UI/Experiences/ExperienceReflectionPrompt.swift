import Foundation

enum ExperienceReflectionPrompt {
    static func text(_ id: String) -> String {
        switch id {
        case "bit-art": return "同じ絵で、1画素に使うビットを増やすと、使える色とデータ量はどう変わるかな？"
        case "circuit-atelier": return "Aを準備完了、Bを開始の許可に置き換えてみよう。準備だけできていたらランプは光るかな？"
        case "memory-switch": return "入力を変えても、記録の合図を出さなければ何が残るかな？電源を切った場合と比べてみよう。"
        case "tiny-switch-workshop": return "信号を出す道と、スイッチを動かす合図。片方だけ変えると、どこまで届くかな？"
        case "instruction-atelier": return "同じ入力でも、命令の順番を入れ替えたら同じ出力になるかな？手元と保存先を追いかけよう。"
        case "work-dispatch": return "長い仕事の途中に、短い操作が届いたら？完了までの時間と、最初の応答はどう変わるかな？"
        case "parallel-factory": return "人を増やしても、前の答えを待つ工程が長かったら？同時にできる部分を予想してみよう。"
        case "pixel-factory": return "小さな仕事や、前の画素の結果が必要な仕事も、GPUの方が速いかな？準備と受け渡しも数えよう。"
        case "memory-dock": return "RAMの空きが1枠で、次の仕事は3枠。保存しただけで入るかな？何を変えれば入るか、試す前に書いてみよう。"
        case "cache-delivery": return "はじめてのGのあとに、もう一度Gが届いたら？残しておく場合と、残さない場合の待ち時間を予想しよう。"
        case "memory-rescue": return "使用6/6でも次の要求がRAM内にある場合と、使用5/6で外から2枠必要な場合。待ちが出るのはどちらかな？"
        case "storage-warehouse": return "読取は一件のまま、容量だけ倍にしたら？速さや準備時間はそのままで比べよう。"
        case "display-studio": return "絵を作る速さだけ増やしたら、全部のコマが画面に現れるかな？生成したコマと表示したコマを比べよう。"
        case "packet-express": return "道幅だけを倍にしたら、最初の荷物も半分の時間で届くかな？先頭と全部の到着を分けて予想しよう。"
        case "board-town": return "部品を一つのSoCの中にまとめたら、計算・記憶・表示の役割や必要なデータの道はなくなるかな？"
        case "connection-lab": return "端子の形が同じなら、映像も給電も必ず届くかな？経路の途中に一つだけ能力の違う部品を入れたら？"
        case "pc-day": return "写真の表示と保存。どちらが電源を切ったあとも残る状態を変えるかな？版の番号を追って確かめよう。"
        case "battery-voyage": return "18Wの給電で12Wを使う10分間。電池には何Wh増えるかな？満充電のときも同じかな？"
        case "cooling-workshop": return "短い依頼でうまくいった冷却でも、長く動かしたら？完成数・熱・音を分けて予想しよう。"
        default: return "仕事が変わっても、同じ部品の改善が効くかな？一か所だけ変え、待ち列と完成時間を比べよう。"
        }
    }
}
