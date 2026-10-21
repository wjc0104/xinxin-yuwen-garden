import SwiftUI
import AVKit
import GardenCore

struct VideoStudyView: View {
    @EnvironmentObject var store: AppStore
    let resource: StudyResource
    let initialSeconds: Int?
    @StateObject private var video = NativeStudyPlayer()
    @State private var composing = false
    @AppStorage private var note: String
    @AppStorage private var stamp: String
    @State private var problem: String?
    @State private var browser: BrowserLink?
    @FocusState private var focused: Bool
    init(resource: StudyResource, initialSeconds: Int?) {
        self.resource = resource
        self.initialSeconds = initialSeconds
        _note = AppStorage(wrappedValue: "", "video-note-draft." + resource.id + ".text")
        _stamp = AppStorage(wrappedValue: "", "video-note-draft." + resource.id + ".time")
    }
    var marks: [StudyMark] { store.data.marks.filter { $0.resourceID == resource.id }.sorted { $0.createdAt > $1.createdAt } }
    var localURL: URL? { guard !resource.localFile.isEmpty else { return nil }; return try? store.disk?.attachmentURL(resource.localFile) }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player = video.player { VideoPlayer(player: player).accessibilityIdentifier("native-video-player") }
                if video.loading { ProgressView("正在连接视频…").foregroundColor(.white).padding().background(Color.black.opacity(0.65)).cornerRadius(12) }
                if let error = video.problem { VStack(spacing: 10) { Text(error).foregroundColor(.white).multilineTextAlignment(.center); Button("重试播放") { Task { await video.load(resource, localURL: localURL, at: video.currentSeconds() ?? initialSeconds, force: true) } } }.padding(20) }
            }.frame(height: focused ? 160 : 230)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(resource.title).font(.headline)
                        HStack {
                            Text(video.qualityLabel).font(.caption).foregroundColor(GardenTheme.mint).accessibilityIdentifier("video-quality")
                            Spacer()
                            Text(video.currentSeconds().map(TimeLabel.video) ?? "--:--").font(.caption.monospacedDigit()).foregroundColor(.secondary).accessibilityIdentifier("video-position")
                            Button(video.playing ? "暂停" : "播放") { video.playPause() }.disabled(!video.ready).accessibilityIdentifier("video-play-pause")
                        }
                        if video.lowQuality { Text("原站当前只提供这一档画质，文字可能不清晰。可以换看本课其他视频。").font(.caption).foregroundColor(.orange) }
                        Caption(text: resource.source)
                        HStack { Button { beginNote() } label: { Label("边看边记", systemImage: "square.and.pencil") }; Spacer(); if let url = SearchEngine.validatedURL(resource.url) { Button("原视频") { browser = BrowserLink(url: url) } } }.font(.subheadline)
                        if composing {
                            GardenCard {
                                HStack { Text("学习笔记").font(.headline); Spacer(); Button("收起") { focused = false; composing = false } }
                                TextEditor(text: $note).frame(height: 90).focused($focused).accessibilityIdentifier("video-note-input")
                                HStack { Text("时间点").font(.subheadline); TextField("分:秒 或 时:分:秒", text: $stamp).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder); Button("取当前时间") { stamp = video.currentSeconds().map(TimeLabel.video) ?? "" }.disabled(!video.ready) }
                                if let problem = problem { Text(problem).font(.caption).foregroundColor(.red) }
                                Button("保存笔记") { saveNote() }.accessibilityIdentifier("video-save-note")
                            }.id("video-composer")
                        }
                        if !marks.isEmpty { Text("学习笔记").font(.headline) }
                        ForEach(marks) { mark in
                            if let seconds = mark.seconds { Button { focused = false; video.seek(seconds) } label: { Label("回看 " + TimeLabel.video(seconds), systemImage: "play.circle") }.disabled(!video.ready).accessibilityIdentifier("seek-" + mark.id) }
                            MarkCard(mark: mark)
                        }
                    }.padding(16)
                }
                .onChange(of: composing) { value in if value { DispatchQueue.main.async { withAnimation { proxy.scrollTo("video-composer", anchor: .top) } } } }
            }
            Divider()
            Button { beginNote() } label: { Label("标记时间 · 写笔记", systemImage: "square.and.pencil").font(.headline).frame(maxWidth: .infinity).padding(15) }.background(GardenTheme.card).accessibilityIdentifier("study-note")
        }
        .task(id: resource.id) { await video.load(resource, localURL: localURL, at: initialSeconds) }
        .onDisappear { video.pause() }
        .sheet(item: $browser) { SafariSheet(url: $0.url) }
    }
    private func beginNote() {
        if !composing && note.isEmpty && stamp.isEmpty { stamp = video.currentSeconds().map(TimeLabel.video) ?? "" }
        problem = nil; composing = true
    }
    private func saveNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { problem = "先写下一句重点。"; return }
        let time = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard time.isEmpty || TimeLabel.seconds(time) != nil else { problem = "时间点可以填写 03:25。"; return }
        let mark = StudyMark(lessonID: resource.lessonID, resourceID: resource.id, quote: "", note: text, seconds: time.isEmpty ? nil : TimeLabel.seconds(time))
        if store.update({ $0.marks.append(mark) }) { focused = false; note = ""; stamp = ""; problem = nil; composing = false }
    }
}
