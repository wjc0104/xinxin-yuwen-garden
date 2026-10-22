import SwiftUI
import GardenCore

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var filter = StudyResourceFilter.all
    @State private var limit = 24
    @State private var results: [LessonSearchResult] = []

    private func updateResults() {
        results = store.search(query, filter: filter)
        limit = 24
    }
    var body: some View {
        GardenPage {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索课文、作者或教学重点", text: $query).submitLabel(.search).accessibilityIdentifier("search-input")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.accessibilityLabel("清空搜索") }
            }.padding(14).background(GardenTheme.card).clipShape(RoundedRectangle(cornerRadius: 12))
            Text("这里搜索本机课程和已有资料；进入课文后，可联网查找新的视频和文字资料。")
                .font(.caption).foregroundColor(.secondary).accessibilityIdentifier("local-search-hint")
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("按课文顺序学习").font(.headline)
                BookGrid()
                Text("从这里开始").font(.headline)
                ForEach(store.lessons.filter { ["7u-01","7u-02","9u-11","9d-01"].contains($0.id) }) { lesson in
                    NavigationLink(destination: LazyDestination { LessonView(lesson: lesson) }) { lessonCard(lesson, resources: store.resources(lesson.id)) }.buttonStyle(.plain)
                }
            } else {
                Picker("资料类型", selection: $filter) { ForEach(StudyResourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Text("找到 \(results.count) 篇课文 · \(results.reduce(0) { $0 + $1.resources.count }) 份匹配资料").font(.subheadline).foregroundColor(.secondary).accessibilityIdentifier("result-count")
                ForEach(Array(results.prefix(limit))) { result in
                    NavigationLink(destination: LazyDestination { LessonView(lesson: result.lesson) }) {
                        lessonCard(result.lesson, resources: result.resources)
                    }.buttonStyle(.plain)
                        .id("search-lesson-" + result.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("search-lesson-" + result.id)
                }
                if results.count > limit { Button("显示更多课文") { limit += 24 }.frame(maxWidth: .infinity).padding() }
                if results.isEmpty { GardenEmpty(title: "没有匹配的课文", detail: "试试课文名、作者或教学重点，例如“济南的冬天”“老舍 温晴”。") }
            }
        }.navigationTitle("课程")
        .onAppear { updateResults() }
        .onChange(of: query) { _ in updateResults() }
        .onChange(of: filter) { _ in updateResults() }
        .onChange(of: store.libraryRevision) { _ in updateResults() }
    }

    private func lessonCard(_ lesson: Lesson, resources: [StudyResource]) -> some View {
        let videoCount = resources.filter { StudyResourceFilter.video.includes($0) }.count
        return GardenCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.title).font(.headline).foregroundColor(.primary)
                    if !lesson.author.isEmpty { Text(lesson.author).font(.subheadline).foregroundColor(.secondary) }
                    Caption(text: store.bookTitle(lesson.id))
                    Caption(text: "\(videoCount) 个视频 · \(resources.count - videoCount) 份文字资料")
                }
                Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
        }
    }
}
