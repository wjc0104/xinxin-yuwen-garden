import SwiftUI
import GardenCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var importBackup = false
    @State private var share: ShareFile?
    @State private var cleanCalendar = false
    var body: some View {
        GardenPage {
            GardenCard { Text("欣语").font(.title2.bold()); Text("给欣欣的语文备课手记").foregroundColor(.secondary); Caption(text: "版本 " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) }
            GardenCard {
                NavigationLink(destination: NotesView()) { Label("我的笔记与收藏", systemImage: "bookmark") }
                Divider()
                NavigationLink(destination: TermSettingsView()) { Label("学期设置", systemImage: "calendar") }
                Divider()
                NavigationLink(destination: BarkView()) { Label("上课提醒", systemImage: "bell") }
            }
            GardenCard {
                Text("备份").font(.headline)
                Button { if let url = store.exportBackup() { share = ShareFile(url: url) } } label: { Label("导出资料和笔记", systemImage: "square.and.arrow.up") }
                Button { importBackup = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
                Caption(text: "换手机或重新安装前，先保存一份备份。")
            }
            if store.calendar.hasBinding {
                GardenCard {
                    Text("旧版日历提醒").font(.headline)
                    Caption(text: "改用 Bark 前，可移除旧版由欣语写入的课程，避免重复提醒。其他日程保留。")
                    Button("移除旧版课程提醒", role: .destructive) { cleanCalendar = true }
                }
            }
            NavigationLink(destination: AboutResourcesView()) { Label("资料来源与隐私", systemImage: "info.circle") }
        }.navigationTitle("我的")
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .fileImporter(isPresented: $importBackup, allowedContentTypes: [.json]) { result in switch result { case .success(let url): store.restore(url); case .failure(let error): store.error = error.localizedDescription } }
        .alert("移除旧版课程提醒？", isPresented: $cleanCalendar) {
            Button("移除旧版课程", role: .destructive) { Task { do { try await store.calendar.requestAccess(); let count = try store.calendar.removeLegacyEvents(); store.notice = "已移除 \(count) 条旧版课程提醒。请在 iPhone 16 确认旧提醒已消失。" } catch { store.error = error.localizedDescription } } }
            Button("取消", role: .cancel) {}
        } message: { Text("仅处理旧版欣语专用日历中带有本应用标记的课程。") }
    }
}
struct TermSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var start = Date()
    @State private var end = Date()
    @State private var minutes = 60
    @State private var confirmed = false
    var body: some View {
        Form {
            Section(header: Text("本学期")) {
                DatePicker("开学日期", selection: $start, displayedComponents: .date)
                DatePicker("结束日期", selection: $end, displayedComponents: .date)
                Toggle("日期已核对", isOn: $confirmed)
            }
            Section(header: Text("上课提醒")) {
                Picker("提前多久", selection: $minutes) { Text("1小时").tag(60); Text("30分钟").tag(30); Text("15分钟").tag(15); Text("10分钟").tag(10) }
                Text("连堂作文在第一节前提醒一次，中间保留休息。").font(.caption).foregroundColor(.secondary)
            }
            Button("保存设置") {
                let begin = GardenDate.string(start), finish = GardenDate.string(end)
                let days = GardenDate.calendar.dateComponents([.day], from: start, to: end).day ?? -1
                guard begin <= finish, days <= 240 else { store.error = "结束日期要晚于开学日期，学期不超过240天。"; return }
                if store.update({ $0.termStart = begin; $0.termEnd = finish; $0.reminderMinutes = minutes; $0.termConfirmed = confirmed }) { store.notice = "学期设置已保存。" }
            }
        }.navigationTitle("学期设置").navigationBarTitleDisplayMode(.inline)
        .onAppear { start = GardenDate.parse(store.data.termStart) ?? Date(); end = GardenDate.parse(store.data.termEnd) ?? Date(); minutes = store.data.reminderMinutes; confirmed = store.data.termConfirmed }
    }
}
struct AboutResourcesView: View {
    var body: some View {
        GardenPage {
            GardenCard { Text("资料来源").font(.headline); Text("按七至九年级课文整理具体视频和原创备课提纲。视频保留作者与分集信息，在原平台播放器中观看；平台可能要求登录。").font(.subheadline); Text("原创提纲和试讲练习不是官方真题。面试要求以当次公告为准。").font(.subheadline); Link("查看人教社教材", destination: URL(string: "https://jc.pep.com.cn/")!) }
            GardenCard { Text("隐私与权限").font(.headline); Text("笔记、收藏和导入的文件保存在本机。没有广告和统计追踪。视频与网页由对应平台提供。").font(.subheadline); Text("Bark：启用时，将课程时间、班级和接收设备密钥交给你配置的定时服务。笔记不上传。接收手机需要允许 Bark 通知。").font(.subheadline); Text("日历：仅清除旧版课程提醒时请求。文件：只读取你选择的文件。不索要通讯录、定位、相机或麦克风权限。").font(.subheadline) }
        }.navigationTitle("来源与隐私").navigationBarTitleDisplayMode(.inline)
    }
}
struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
