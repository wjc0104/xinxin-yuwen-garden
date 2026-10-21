import SwiftUI
import GardenCore
import SafariServices

struct BrowserLink: Identifiable { let id = UUID(); let url: URL }
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct ResourceEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let lessonID: String
    @State private var title = ""
    @State private var kind = ResourceKind.link
    @State private var url = ""
    @State private var bodyText = ""
    @State private var paid = false
    @State private var problem: String?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("资料信息")) {
                    TextField("资料名称", text: $title)
                    Picker("类型", selection: $kind) { ForEach([ResourceKind.link,.video,.guide,.script], id: \.self) { Text($0.label).tag($0) } }
                    TextField("原页面链接（可选）", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                    Toggle("标记为可能付费", isOn: $paid)
                }
                Section(header: Text("自己的文字资料／说明")) { TextEditor(text: $bodyText).frame(minHeight: 230) }
                if let problem = problem { Text(problem).foregroundColor(.red) }
            }.navigationTitle("添加资料").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        }.navigationViewStyle(.stack)
    }
    private func save() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { problem = "给资料取个名字吧。"; return }
        guard link.isEmpty || SearchEngine.validatedURL(link) != nil else { problem = "请填写有效的 HTTP／HTTPS 原页面链接。"; return }
        guard !link.isEmpty || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { problem = "请添加链接或文字内容。"; return }
        let resource = StudyResource(lessonID: lessonID, title: title, kind: kind, body: bodyText, url: link, isPaid: paid)
        if store.update({ $0.resources.append(resource) }) { dismiss() }
    }
}
