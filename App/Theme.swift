import SwiftUI
enum GardenTheme {
    static let rose = Color(red: 0.67, green: 0.24, blue: 0.36)
    static let mint = Color(red: 0.22, green: 0.48, blue: 0.40)
    static let background = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1) : UIColor(red: 0.99, green: 0.97, blue: 0.94, alpha: 1) })
    static let card = Color(UIColor.secondarySystemGroupedBackground)
}
struct GardenCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 12) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(GardenTheme.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20).stroke(GardenTheme.rose.opacity(0.08), lineWidth: 1)) }
}
struct GardenPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { content }.padding(20).padding(.bottom, 24) }.background(GardenTheme.background.ignoresSafeArea()) }
}
struct GardenEmpty: View {
    let title: String; let detail: String
    var body: some View { GardenCard { Image(systemName: "leaf").font(.title).foregroundColor(GardenTheme.mint); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundColor(.secondary) } }
}
struct Caption: View { let text: String; var body: some View { Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) } }
