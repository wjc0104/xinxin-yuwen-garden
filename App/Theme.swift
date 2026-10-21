import SwiftUI
enum GardenTheme {
    /// Only Bilibili's known image CDN receives its resizing syntax; other origins stay intact.
    static func thumbnailURL(_ value: String?) -> URL? {
        guard let value = value, let url = URL(string: value) else { return nil }
        guard let host = url.host?.lowercased(), ["i0.hdslb.com", "i1.hdslb.com", "i2.hdslb.com"].contains(host),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let original = String(parts.path.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard ["jpg", "jpeg", "png", "webp"].contains((original as NSString).pathExtension.lowercased()) else { return url }
        parts.scheme = "https"
        parts.path = original + "@320w_220h_1c.webp"
        return parts.url ?? url
    }
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
    var body: some View { ScrollView { LazyVStack(alignment: .leading, spacing: 16) { content }.padding(20).padding(.bottom, 24) }.background(GardenTheme.background.ignoresSafeArea()) }
}
struct GardenEmpty: View {
    let title: String; let detail: String
    var body: some View { GardenCard { Image(systemName: "doc.text.magnifyingglass").font(.title).foregroundColor(GardenTheme.mint); Text(title).font(.headline); Text(detail).font(.subheadline).foregroundColor(.secondary) } }
}
struct Caption: View { let text: String; var body: some View { Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) } }

/// iOS 15 NavigationLink can otherwise construct every destination while rendering its list.
struct LazyDestination<Content: View>: View {
    let build: () -> Content
    init(@ViewBuilder _ build: @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}
