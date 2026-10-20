import SwiftUI
import GardenCore

struct NoteEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let lessonID: String
    var resourceID: String?
    var regions: [PDFRegion] = []
    var existing: StudyMark?
    @State var quote = ""
    @State var note = ""
    @State var timestamp = ""
    @State private var problem: String?
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("摘下这一句")) { TextEditor(text: $quote).frame(minHeight: 85).accessibilityIdentifier("quote-input") }
                Section(header: Text("我的理解与课堂灵感")) { TextEditor(text: $note).frame(minHeight: 180).accessibilityIdentifier("note-input") }
                Section(header: Text("视频时间点（可选）"), footer: Text("本地视频可自动带入；外部平台请手动记录播放器时间，例如 03:25。")) {
                    TextField("分:秒 或 时:分:秒", text: $timestamp).keyboardType(.numbersAndPunctuation)
                }
                if let problem = problem { Text(problem).foregroundColor(.red) }
            }.navigationTitle(existing == nil ? "记一朵小重点" : "整理小重点").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.accessibilityIdentifier("save-note") } }
            .onAppear { if let mark = existing { quote = mark.quote; note = mark.note; timestamp = mark.seconds.map(TimeLabel.video) ?? "" } }
        }.navigationViewStyle(.stack)
    }
    private func save() {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { problem = "写一句重点或想法再保存吧。"; return }
        let text = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty || TimeLabel.seconds(text) != nil else { problem = "时间格式不对，可以填写 03:25。"; return }
        var value = existing ?? StudyMark(lessonID: lessonID, resourceID: resourceID, quote: quote, note: note, regions: regions)
        value.quote = quote; value.note = note; value.seconds = text.isEmpty ? nil : TimeLabel.seconds(text)
        if store.update({ data in if let index = data.marks.firstIndex(where: { $0.id == value.id }) { data.marks[index] = value } else { data.marks.append(value) } }) { dismiss() }
    }
}
struct MarkCard: View {
    @EnvironmentObject var store: AppStore
    let mark: StudyMark
    @State private var edit = false
    @State private var remove = false
    var body: some View {
        GardenCard {
            HStack { Text(store.lesson(mark.lessonID)?.title ?? "我的课文").font(.caption.bold()).foregroundColor(GardenTheme.mint); Spacer(); if let seconds = mark.seconds { Label(TimeLabel.video(seconds), systemImage: "play.circle").font(.caption) } }
            if !mark.quote.isEmpty { Text(mark.quote).font(.subheadline).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 10)) }
            if !mark.note.isEmpty { Text(mark.note).font(.body) }
            HStack {
                Button("编辑") { edit = true }
                if let id = mark.resourceID, let resource = store.data.resources.first(where: { $0.id == id }) { NavigationLink("回到资料", destination: ReadingView(resource: resource, initialSeconds: mark.seconds)) }
                Spacer(); Button { remove = true } label: { Image(systemName: "trash") }.foregroundColor(.secondary).accessibilityLabel("删除重点")
            }.font(.caption)
        }.sheet(isPresented: $edit) { NoteEditor(lessonID: mark.lessonID, resourceID: mark.resourceID, existing: mark) }
        .alert("删除这条小重点？", isPresented: $remove) { Button("删除", role: .destructive) { store.update { $0.marks.removeAll { $0.id == mark.id } } }; Button("取消", role: .cancel) {} } message: { Text("建议先在“我的”导出备份。") }
    }
}
struct NotesView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var favorites = false
    var filtered: [StudyMark] { store.data.marks.filter { query.isEmpty || ($0.quote + $0.note + (store.lesson($0.lessonID)?.title ?? "")).localizedCaseInsensitiveContains(query) }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        GardenPage {
            GardenCard { Text("灵感很小，也值得收好 🌼").font(.headline); TextField("搜索笔记或课文", text: $query).textFieldStyle(.roundedBorder); Picker("查看", selection: $favorites) { Text("小重点").tag(false); Text("收藏课文").tag(true) }.pickerStyle(.segmented) }
            if favorites {
                ForEach(store.lessons.filter { store.data.favorites.contains($0.id) }) { lesson in NavigationLink(destination: LessonView(lesson: lesson)) { GardenCard { Label(lesson.title, systemImage: "heart.fill") } }.buttonStyle(.plain) }
                if store.data.favorites.isEmpty { GardenEmpty(title: "收藏还在等你", detail: "打开一篇课文，点“种进收藏”就能在这里找到。") }
            } else {
                ForEach(filtered) { mark in MarkCard(mark: mark) }
                if filtered.isEmpty { GardenEmpty(title: "这一页留给小灵感", detail: "在课文里记一笔，或在文字、PDF 中选中文字划重点；视频也能记录时间点。") }
            }
        }.navigationTitle("小重点")
    }
}
