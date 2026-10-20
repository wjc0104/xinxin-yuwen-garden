import SwiftUI
import GardenCore
import UniformTypeIdentifiers

struct CatalogView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        GardenPage {
            GardenCard {
                Text("给欣欣的语文备课手记").font(.title2.bold())
                Text("按课文找资料，随手记下自己的思考。").foregroundColor(.secondary)
                HStack { Label("六册目录", systemImage: "book.closed"); Spacer(); Text("教资 · 教招").foregroundColor(GardenTheme.mint) }.font(.caption)
            }
            Text("沿着课文，一页页出发").font(.headline)
            ForEach(store.catalog?.books ?? []) { book in
                NavigationLink(destination: BookView(book: book)) {
                    GardenCard {
                        HStack(alignment: .top) {
                            Text(book.id.hasSuffix("u") ? "🌱" : "🌼").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 6) { Text(book.title).font(.title3.bold()).foregroundColor(.primary); Caption(text: book.edition); Text("\(book.units.flatMap(\.lessons).count) 个课文与诵读条目").font(.caption).foregroundColor(GardenTheme.mint) }
                            Spacer(); Image(systemName: "chevron.right").foregroundColor(GardenTheme.rose)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("book-" + book.id)
            }
            Caption(text: "安徽备课参考 · 目录核对于 2026-10-21。学校实际用书以萧县／黄口当地安排为准；九下新修订版待更新。")
        }.navigationTitle("欣语")
    }
}
struct BookView: View {
    @EnvironmentObject var store: AppStore
    let book: Textbook
    var body: some View {
        GardenPage {
            GardenCard { Text(book.edition).font(.headline); Caption(text: book.verification); if let url = URL(string: book.source) { Link("查看人教社原目录 ↗", destination: url).font(.subheadline) } }
            ForEach(book.units) { unit in
                Text(unit.title).font(.headline).padding(.top, 8)
                GardenCard {
                    ForEach(unit.lessons) { lesson in
                        NavigationLink(destination: LessonView(lesson: lesson)) {
                            HStack(alignment: .top, spacing: 12) {
                                Text(lesson.number == 0 ? "诗" : String(lesson.number)).font(.caption.bold()).foregroundColor(GardenTheme.rose).frame(width: 27, height: 27).background(GardenTheme.rose.opacity(0.08)).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 5) { Text(lesson.title).foregroundColor(.primary); Caption(text: lesson.author); if !lesson.focus.isEmpty { Caption(text: lesson.focus.joined(separator: " · ")) } }
                                Spacer(minLength: 0)
                                Image(systemName: store.data.favorites.contains(lesson.id) ? "heart.fill" : "chevron.right").font(.caption).foregroundColor(GardenTheme.rose)
                            }.padding(.vertical, 4)
                        }.accessibilityIdentifier("lesson-" + lesson.id)
                        if lesson.id != unit.lessons.last?.id { Divider() }
                    }
                }
            }
        }.navigationTitle(book.title)
    }
}
struct LessonView: View {
    @EnvironmentObject var store: AppStore
    let lesson: Lesson
    @State private var addNote = false
    @State private var addResource = false
    @State private var importFile = false
    var body: some View {
        GardenPage {
            GardenCard {
                Text(lesson.title).font(.title2.bold()); Caption(text: lesson.author)
                if !lesson.focus.isEmpty { Text(lesson.focus.joined(separator: " · ")).font(.subheadline) }
                Button { store.update { if !$0.favorites.insert(lesson.id).inserted { $0.favorites.remove(lesson.id) } } } label: { Label(store.data.favorites.contains(lesson.id) ? "已种进收藏" : "种进收藏", systemImage: store.data.favorites.contains(lesson.id) ? "heart.fill" : "heart") }
            }
            SourceSearchPanel(query: lesson.title + " 初中语文 十分钟 试讲 教案")
            HStack { Text("这一课的资料").font(.headline); Spacer(); Button { addResource = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("添加资料") }
            ForEach(store.resources(lesson.id)) { resource in NavigationLink(destination: ReadingView(resource: resource)) { ResourceRow(resource: resource) }.buttonStyle(.plain).accessibilityIdentifier("resource-" + resource.id) }
            if store.resources(lesson.id).isEmpty { GardenEmpty(title: "等一份好资料发芽", detail: "目录已收录。这一课暂未精选成套教案，可以先搜视频、保存原链接，或导入自己的资料。") }
            Button { importFile = true } label: { Label("导入 PDF、文字或本地视频", systemImage: "square.and.arrow.down") }.font(.subheadline)
            GardenCard { Text("十分钟练习怎么准备").font(.headline); Text("1 分钟导入 → 1 分钟整体感知 → 4 分钟核心问题 → 2 分钟迁移与评价 → 2 分钟小结、作业和板书。").font(.subheadline); Caption(text: "自编时间框架，按实际题目调整。优先讲透一个有文本依据的重点；并非真题或高频考点统计。教招时补足当地公告要求的环节。") }
            HStack { Text("我的小重点").font(.headline); Spacer(); Button { addNote = true } label: { Label("记一笔", systemImage: "square.and.pencil") }.accessibilityIdentifier("new-note") }
            ForEach(store.marks(lesson.id)) { mark in MarkCard(mark: mark) }
        }.navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addNote) { NoteEditor(lessonID: lesson.id) }
        .sheet(isPresented: $addResource) { ResourceEditor(lessonID: lesson.id) }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.pdf,.plainText,.movie,UTType(filenameExtension: "md") ?? .plainText]) { result in switch result { case .success(let url): store.importResource(url, lessonID: lesson.id); case .failure(let error): store.error = error.localizedDescription } }
    }
}
struct ResourceRow: View {
    let resource: StudyResource
    var body: some View { GardenCard { HStack { Label(resource.kind.label, systemImage: resource.kind == .video || resource.kind == .localVideo ? "play.rectangle" : "doc.text").font(.caption).foregroundColor(GardenTheme.mint); Spacer(); if resource.isPaid { Text("可能付费").font(.caption).foregroundColor(.orange) } }; Text(resource.title).font(.headline).foregroundColor(.primary); Caption(text: resource.source) } }
}
