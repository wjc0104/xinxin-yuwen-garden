import SwiftUI
import GardenCore
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedTab: Int
    var today: [Occurrence] { store.courses(on: Date()) }
    var body: some View {
        GardenPage {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("欣语").font(.largeTitle.bold()); Text("备课，从这一课开始").foregroundColor(.secondary) }; Spacer(); Image(systemName: "book.closed.fill").font(.largeTitle).foregroundColor(GardenTheme.rose) }
            Button { selectedTab = 1 } label: { HStack { Image(systemName: "magnifyingglass"); Text("搜索课文、视频、试讲稿"); Spacer(); Image(systemName: "chevron.right") }.padding(16).background(GardenTheme.card).clipShape(RoundedRectangle(cornerRadius: 14)) }.accessibilityIdentifier("home-search")
            if let resource = store.data.resources.first(where: { $0.id == store.recentResourceID }) {
                Text("继续学习").font(.headline)
                NavigationLink(destination: ReadingView(resource: resource)) { ResourceRow(resource: resource) }.buttonStyle(.plain)
            }
            HStack { Text("今天的课").font(.headline); Spacer(); Button("查看课表") { selectedTab = 3 } }
            GardenCard {
                if today.isEmpty { Label("今天没有课程安排", systemImage: "calendar").foregroundColor(.secondary) }
                ForEach(today) { item in HStack { Text(TimeLabel.clock(item.startMinute)).font(.headline.monospacedDigit()).foregroundColor(GardenTheme.rose); Text("\(item.subject) · \(item.classNumber)班"); Spacer(); Text("第\(item.period)节").font(.caption).foregroundColor(.secondary) } }
            }
            HStack { Text("按教材学习").font(.headline); Spacer(); Text("七至九年级").font(.caption).foregroundColor(.secondary) }
            BookGrid()
            if !store.data.favorites.isEmpty {
                Text("收藏的课文").font(.headline)
                ForEach(store.lessons.filter { store.data.favorites.contains($0.id) }.prefix(6)) { lesson in NavigationLink(destination: LessonView(lesson: lesson)) { GardenCard { HStack { Text(lesson.title); Spacer(); Image(systemName: "chevron.right") } } }.buttonStyle(.plain) }
            }
        }.navigationTitle("主页").navigationBarTitleDisplayMode(.inline)
    }
}
struct BookGrid: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(store.catalog?.books ?? []) { book in
                NavigationLink(destination: BookView(book: book)) {
                    GardenCard {
                        Image(systemName: "book.closed").font(.title2).foregroundColor(GardenTheme.rose)
                        Text(book.title).font(.headline).foregroundColor(.primary)
                        Text("\(book.units.flatMap(\.lessons).count) 篇课文与诵读").font(.caption).foregroundColor(.secondary)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("book-" + book.id)
            }
        }
    }
}
struct CatalogView: View { var body: some View { GardenPage { BookGrid() }.navigationTitle("教材目录") } }
struct BookView: View {
    @EnvironmentObject var store: AppStore
    let book: Textbook
    var body: some View {
        GardenPage {
            Text(book.edition).font(.caption).foregroundColor(.secondary)
            ForEach(book.units) { unit in
                Text(unit.title).font(.headline).padding(.top, 4)
                GardenCard {
                    ForEach(unit.lessons) { lesson in
                        NavigationLink(destination: LessonView(lesson: lesson)) {
                            HStack(spacing: 12) {
                                Text(lesson.number == 0 ? "诗" : String(lesson.number)).font(.caption.bold()).foregroundColor(GardenTheme.rose).frame(width: 28, height: 28).background(GardenTheme.rose.opacity(0.08)).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) { Text(lesson.title).foregroundColor(.primary); Text("\(store.resources(lesson.id).filter { $0.kind == .video }.count) 个视频 · \(store.resources(lesson.id).filter { $0.kind != .video }.count) 份资料").font(.caption).foregroundColor(.secondary) }
                                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }.padding(.vertical, 5)
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
    @State private var filter = "全部"
    @State private var addNote = false
    @State private var addResource = false
    @State private var importFile = false
    @StateObject private var refresh = LessonRefresh()
    var resources: [StudyResource] { store.resources(lesson.id).filter {
        if filter == "全部" { return true }
        if filter == "视频" { return $0.kind == .video || $0.kind == .localVideo }
        if filter == "试讲稿" { return $0.kind == .script }
        return $0.category == filter || (filter == "备课提纲" && $0.kind == .guide)
    } }
    var body: some View {
        GardenPage {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) { Text(lesson.title).font(.title2.bold()); Text(lesson.author).font(.subheadline).foregroundColor(.secondary); Text(store.bookTitle(lesson.id)).font(.caption).foregroundColor(.secondary) }
                Spacer()
                Button { store.update { if !$0.favorites.insert(lesson.id).inserted { $0.favorites.remove(lesson.id) } } } label: { Image(systemName: store.data.favorites.contains(lesson.id) ? "heart.fill" : "heart").font(.title2) }.accessibilityLabel("收藏课文")
            }
            GardenCard {
                Button { Task { await refresh.refresh(lesson, store: store) } } label: {
                    HStack { if refresh.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") }; Text(refresh.busy ? "正在联网查找本课资料…" : "联网查找本课资料").font(.headline); Spacer() }.padding(.vertical, 6)
                }.disabled(refresh.busy).accessibilityIdentifier("refresh-lesson")
                Text("查找本课视频、原作者公开试讲稿、教学设计与课文解读。原文在站内页面阅读，未逐篇审定。").font(.caption).foregroundColor(.secondary)
                if let message = refresh.message { Text(message).font(.caption).foregroundColor(refresh.hasFailure ? .orange : GardenTheme.mint).accessibilityIdentifier("refresh-status") }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(["全部","视频","试讲稿","教学设计","课文解读","备课提纲"], id: \.self) { category in Button { filter = category } label: { Text(category).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8).background(filter == category ? GardenTheme.rose.opacity(0.15) : GardenTheme.card).cornerRadius(12) } } }
            }.accessibilityIdentifier("lesson-category-picker")
            ForEach(resources) { resource in NavigationLink(destination: ReadingView(resource: resource)) { VStack(alignment: .leading, spacing: 4) { if refresh.newIDs.contains(resource.id) { Text("本次新增").font(.caption.bold()).foregroundColor(GardenTheme.mint) }; ResourceRow(resource: resource) } }.buttonStyle(.plain).accessibilityIdentifier("resource-" + resource.id) }
            if resources.isEmpty { GardenEmpty(title: "此分类暂未收录", detail: "可以切换“全部”查看这篇课文已有的学习资料。") }
            if !store.marks(lesson.id).isEmpty {
                Text("学习笔记").font(.headline)
                ForEach(store.marks(lesson.id)) { mark in MarkCard(mark: mark) }
            }
        }.refreshable { await refresh.refresh(lesson, store: store) }.navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu { Button("添加自己的资料") { addResource = true }; Button("导入文件") { importFile = true }; Button("写课文笔记") { addNote = true } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("更多") }
        .sheet(isPresented: $addNote) { NoteEditor(lessonID: lesson.id) }
        .sheet(isPresented: $addResource) { ResourceEditor(lessonID: lesson.id) }
        .fileImporter(isPresented: $importFile, allowedContentTypes: [.pdf,.plainText,.movie,UTType(filenameExtension: "md") ?? .plainText]) { result in switch result { case .success(let url): store.importResource(url, lessonID: lesson.id); case .failure(let error): store.error = error.localizedDescription } }
    }
}
struct ResourceRow: View {
    let resource: StudyResource
    var body: some View {
        GardenCard {
            HStack(alignment: .top, spacing: 12) {
                if resource.kind == .video {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: GardenTheme.thumbnailURL(resource.thumbnail)) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(GardenTheme.rose.opacity(0.10)).overlay(Image(systemName: "play.fill").foregroundColor(GardenTheme.rose)) }.frame(width: 110, height: 74).clipped().cornerRadius(10)
                        if let duration = resource.durationSeconds { Text(TimeLabel.video(duration)).font(.caption2.monospacedDigit()).foregroundColor(.white).padding(3).background(Color.black.opacity(0.7)).cornerRadius(4).padding(4) }
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(resource.category ?? resource.kind.label).font(.caption).foregroundColor(GardenTheme.mint)
                    Text(resource.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(3)
                    Text(resource.source).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
                if resource.kind != .video { Spacer(minLength: 0); Image(systemName: "doc.text").font(.title2).foregroundColor(GardenTheme.rose) }
            }
            if resource.isPaid { Text("原站可能需要付费").font(.caption).foregroundColor(.orange) }
        }
    }
}
