import SwiftUI
@main struct XinxinGardenApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene { WindowGroup { GardenRoot().environmentObject(store) } }
}
struct GardenRoot: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        TabView(selection: $store.tab) {
            NavigationView { CatalogView() }.navigationViewStyle(.stack).tabItem { Label("小花园", systemImage: "books.vertical") }.tag(0)
            NavigationView { SearchView() }.navigationViewStyle(.stack).tabItem { Label("找资料", systemImage: "magnifyingglass") }.tag(1)
            NavigationView { NotesView() }.navigationViewStyle(.stack).tabItem { Label("小重点", systemImage: "highlighter") }.tag(2)
            NavigationView { ScheduleView() }.navigationViewStyle(.stack).tabItem { Label("课表", systemImage: "calendar") }.tag(3)
            NavigationView { SettingsView() }.navigationViewStyle(.stack).tabItem { Label("我的", systemImage: "heart.circle") }.tag(4)
        }.tint(GardenTheme.rose)
        .alert("小花园提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("收好啦 🌷", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("好", role: .cancel) { store.notice = nil } } message: { Text(store.notice ?? "") }
    }
}
