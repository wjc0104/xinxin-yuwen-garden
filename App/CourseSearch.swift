import SwiftUI
import GardenCore

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var filter = "全部"
    @State private var limit = 24
    var results: [StudyResource] {
        StudyLibrary.search(query, resources: store.data.resources, lessons: store.lessons).filter {
            filter == "全部" || (filter == "视频" ? $0.kind == .video || $0.kind == .localVideo : $0.kind != .video && $0.kind != .localVideo)
        }
    }
    var body: some View {
        GardenPage {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索课文、作者或教学重点", text: $query).submitLabel(.search).accessibilityIdentifier("search-input")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.accessibilityLabel("清空搜索") }
            }.padding(14).background(GardenTheme.card).clipShape(RoundedRectangle(cornerRadius: 12))
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("按课文顺序学习").font(.headline)
                BookGrid()
                Text("从这里开始").font(.headline)
                ForEach(store.lessons.filter { ["7u-01","7u-02","9u-11","9d-01"].contains($0.id) }) { lesson in
                    NavigationLink(destination: LessonView(lesson: lesson)) { GardenCard { HStack { VStack(alignment: .leading, spacing: 4) { Text(lesson.title).font(.headline); Caption(text: store.bookTitle(lesson.id)) }; Spacer(); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
                }
            } else {
                let found = results
                Picker("资料类型", selection: $filter) { ForEach(["全部","视频","教案与试讲"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                Text("找到 \(found.count) 份资料").font(.subheadline).foregroundColor(.secondary).accessibilityIdentifier("result-count")
                ForEach(Array(found.prefix(limit))) { resource in
                    NavigationLink(destination: ReadingView(resource: resource)) { ResourceRow(resource: resource) }.buttonStyle(.plain).accessibilityIdentifier("search-" + resource.id)
                }
                if found.count > limit { Button("显示更多资料") { limit += 24 }.frame(maxWidth: .infinity).padding() }
                if found.isEmpty { GardenEmpty(title: "没有匹配的资料", detail: "试试课文名或作者，例如“济南的冬天”“老舍”。") }
            }
        }.navigationTitle("课程")
        .onChange(of: query) { _ in limit = 24 }
        .onChange(of: filter) { _ in limit = 24 }
    }
}
