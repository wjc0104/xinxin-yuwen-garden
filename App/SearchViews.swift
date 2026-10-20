import SwiftUI
import GardenCore
import SafariServices

struct BrowserLink: Identifiable { let id = UUID(); let url: URL }
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct SourceSearchPanel: View {
    let query: String
    @State private var browser: BrowserLink?
    var body: some View {
        GardenCard {
            Text("去找一份好灵感").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SearchSource.allCases) { source in
                    Button { if let url = SearchEngine.webURL(source: source, query: query) { browser = BrowserLink(url: url) } } label: { Text(source.label + " ↗").font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 11).background(GardenTheme.rose.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12)) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Caption(text: "打开对应平台的搜索页；智慧教育使用站内限定的网页搜索。优先核对作者、课文版本和课堂环节，付费信息以原站为准。")
        }.sheet(item: $browser) { SafariSheet(url: $0.url) }
    }
}
struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var purpose = "教资"
    var results: [Lesson] { SearchEngine.matches(query, lessons: store.lessons, resources: store.data.resources, marks: store.data.marks) }
    var body: some View {
        GardenPage {
            GardenCard {
                Text("课文、作者、小重点，都能找").font(.headline)
                TextField("试试：春、鲁迅、板书……", text: $query).textFieldStyle(.roundedBorder).submitLabel(.search).accessibilityIdentifier("search-input")
                Picker("备课方向", selection: $purpose) { Text("教资").tag("教资"); Text("教招").tag("教招") }.pickerStyle(.segmented)
            }
            SourceSearchPanel(query: (query.isEmpty ? "初中语文" : query) + " " + purpose + " 十分钟 试讲 教案 重点")
            HStack { Text("本机资料").font(.headline); Spacer(); Text("\(results.count) 篇").font(.caption).foregroundColor(.secondary) }
            ForEach(results) { lesson in NavigationLink(destination: LessonView(lesson: lesson)) { GardenCard { Text(lesson.title).font(.headline).foregroundColor(.primary); Caption(text: lesson.author + " · " + (store.catalog?.books.first { book in book.units.contains { unit in unit.lessons.contains { $0.id == lesson.id } } }?.title ?? "")) } }.buttonStyle(.plain) }
            if results.isEmpty { GardenEmpty(title: "还没有找到", detail: "换一个词试试，也可以打开上方平台继续搜索。") }
        }.navigationTitle("找资料")
    }
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
                Section(header: Text("种下一份资料")) {
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
