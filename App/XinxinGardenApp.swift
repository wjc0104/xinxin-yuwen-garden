import SwiftUI
import UIKit
import GardenCore
@main struct XinxinGardenApp: App {
    @StateObject private var store = AppStore()
    init() {
        _ = PlayerTransportTrace.shared
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"),
           arguments.contains("--ui-testing-poetry-layout"),
           arguments.contains("--ui-testing-reader-static-transitions") {
            // Controlled fixture experiment; not acceptance of release-state animations.
            UIView.setAnimationsEnabled(false)
            NSLog("[ReaderTransitionControl] synthetic reader transition experiment active")
        }
        #endif
    }
    var body: some Scene { WindowGroup { GardenRoot().environmentObject(store).environment(\.locale, Locale(identifier: "zh_CN")).environment(\.calendar, GardenDate.calendar).environment(\.timeZone, GardenDate.calendar.timeZone) } }
}
struct GardenRoot: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var phase
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView { HomeView(selectedTab: $selectedTab) }.navigationViewStyle(.stack).tabItem { Label("主页", systemImage: "house") }.tag(0)
            NavigationView { SearchView() }.navigationViewStyle(.stack).tabItem { Label("课程", systemImage: "books.vertical") }.tag(1)
            NavigationView { ScheduleView() }.navigationViewStyle(.stack).tabItem { Label("课表", systemImage: "calendar") }.tag(3)
            NavigationView { SettingsView() }.navigationViewStyle(.stack).tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }.tint(GardenTheme.rose)
        .onChange(of: phase) { if $0 == .active { BarkBridge.shared.changed(store.data) } }
        .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("已保存", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("好", role: .cancel) { store.notice = nil } } message: { Text(store.notice ?? "") }
    }
}
