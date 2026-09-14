import SwiftUI

struct RoomComponentDetail: View {
    let component: RoomComponent
    var warning: ComponentWarning? = nil
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                Image(systemName: component.symbol)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color(red: 0.40, green: 0.90, blue: 0.94))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("詳細を閉じる").help("閉じる（Esc）")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(component.category.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Color(red: 0.50, green: 0.84, blue: 0.88))
                Text(component.title).font(.system(size: 23, weight: .semibold))
                Text(component.summary).font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(.white.opacity(0.10))
            if let warning {
                VStack(alignment: .leading, spacing: 8) {
                    Label("警告", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.yellow)
                    Text(warning.message.isEmpty ? "このコンポーネントに警告があります。" : warning.message)
                        .font(.system(size: 12)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("警告。\(warning.message)")
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("詳細データは準備中です", systemImage: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                Text("データが接続されると、この場所に状態や使用状況が表示されます。")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.52))
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20).frame(width: 292)
        .background(Color(red: 0.055, green: 0.08, blue: 0.10).opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        .accessibilityElement(children: .contain).accessibilityLabel("\(component.title)の詳細")
    }
}
