import SwiftUI
import GardenCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var termStart = Date()
    @State private var termEnd = Date()
    @State private var minutes = 10
    @State private var confirmTerm = false
    @State private var importBackup = false
    @State private var share: ShareFile?
    var body: some View {
        GardenPage {
            GardenCard { Text("欣欣的备课手记").font(.title2.bold()); Text("资料、重点和下一节课，都放在这里。").font(.subheadline).foregroundColor(.secondary); Caption(text: "欣语 · 0.0.1 · iPhone XR / iOS 15") }
            GardenCard {
                Text("这学期的小约定").font(.headline)
                DatePicker("开学日期", selection: $termStart, displayedComponents: .date)
                DatePicker("结束日期", selection: $termEnd, displayedComponents: .date)
                Stepper("提前 \(minutes) 分钟提醒", value: $minutes, in: 0...60, step: 5)
                Toggle("已核对本学期起止日期", isOn: $confirmTerm)
                Caption(text: "首次显示的日期是可编辑的占位范围，不代表学校校历。节假日请用单次停课调整。作文仍按两节课分别提醒。")
                Button("保存学期设置") { saveTerm() }
                NavigationLink("设置 iPhone 16 上课提醒", destination: CalendarSyncView())
            }
            GardenCard {
                Text("把小重点好好收着").font(.headline)
                Button { if let url = store.exportBackup() { share = ShareFile(url: url) } } label: { Label("导出资料与笔记备份", systemImage: "square.and.arrow.up") }
                Button { importBackup = true } label: { Label("导入备份并合并", systemImage: "square.and.arrow.down") }
                Caption(text: "备份包含笔记、链接、调课记录及使用中的附件。相同编号保留本机内容；不会恢复日历绑定或覆盖本机学期。单附件 40 MB，附件总量 60 MB。请将导出文件保存到“文件”。")
            }
            GardenCard {
                Text("权限由你决定").font(.headline)
                Text("日历：仅在主动同步时申请。\n文件：仅访问你在系统文件选择器中选定的资料。\n网络：只有打开原站或搜索平台时使用。").font(.subheadline)
                Caption(text: "不申请通讯录、定位、相机、麦克风、照片或应用推送权限。学习数据存在本机，无登录、广告或统计 SDK；外部网站遵循各自隐私政策。")
                Button("打开系统应用设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("解除已删除日历的失效绑定") { do { try store.calendar.forgetMissingBinding(); store.notice = "失效绑定已解除，可重新创建专用日历。" } catch { store.error = error.localizedDescription } }.font(.caption)
            }
            GardenCard {
                Text("资料从哪里来").font(.headline)
                Link("人教社电子教材目录 ↗", destination: URL(string: "https://jc.pep.com.cn/")!)
                Link("国家中小学智慧教育平台 ↗", destination: URL(string: "https://basic.smartedu.cn/")!)
                Link("中小学教师资格考试官方信息 ↗", destination: URL(string: "https://ntce.neea.edu.cn/")!)
                Caption(text: "六册统编六三学制目录；九下新修订版待更新。其他教材版本暂未内置。精选资源为少量入门链接，不是全部教案库；原创练习明确标记，不冒充官方真题、高频统计或当地招考通知。")
            }
        }.environment(\.timeZone, GardenDate.calendar.timeZone).navigationTitle("我的")
        .onAppear { termStart = GardenDate.parse(store.data.termStart) ?? Date(); termEnd = GardenDate.parse(store.data.termEnd) ?? Date(); minutes = store.data.reminderMinutes; confirmTerm = store.data.termConfirmed }
        .sheet(item: $share) { ActivitySheet(url: $0.url) }
        .fileImporter(isPresented: $importBackup, allowedContentTypes: [.json]) { result in switch result { case .success(let url): store.restore(url); case .failure(let error): store.error = error.localizedDescription } }
    }
    private func saveTerm() {
        let begin = GardenDate.string(termStart), end = GardenDate.string(termEnd)
        let span = GardenDate.calendar.dateComponents([.day], from: termStart, to: termEnd).day ?? -1
        guard begin <= end, span <= 240 else { store.error = "请设置起止顺序正确、最长 240 天的学期范围。"; return }
        if store.update({ $0.termStart = begin; $0.termEnd = end; $0.reminderMinutes = minutes; $0.termConfirmed = confirmTerm }) { store.notice = "设置已保存。课表变化后请重新同步日历。" }
    }
}
struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
