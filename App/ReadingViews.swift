import SwiftUI
import UIKit
import PDFKit
import AVKit
import GardenCore

private struct NoteDraft: Identifiable { let id = UUID(); var quote = ""; var regions: [PDFRegion] = []; var seconds: Int? }
struct ReadingView: View {
    @EnvironmentObject var store: AppStore
    let resource: StudyResource
    var initialSeconds: Int?
    @State private var draft: NoteDraft?
    @State private var browser: BrowserLink?
    @State private var player: AVPlayer?
    @State private var showDelete = false
    @StateObject private var web = WebStudyController()
    @State private var textHeight: CGFloat = 400
    var marks: [StudyMark] { store.data.marks.filter { $0.resourceID == resource.id } }
    var localURL: URL? { guard !resource.localFile.isEmpty else { return nil }; return try? store.disk?.attachmentURL(resource.localFile) }
    var body: some View {
        VStack(spacing: 0) {
            if resource.kind == .pdf, let url = localURL {
                PDFReader(url: url, marks: marks) { text, regions in draft = NoteDraft(quote: text, regions: regions) }
            } else if resource.kind == .localVideo, let player = player {
                VideoPlayer(player: player).frame(minHeight: 230, maxHeight: 320)
                ScrollView { VStack(alignment: .leading, spacing: 14) { Text(resource.title).font(.headline); Caption(text: "点下方“标记当前时间”记重点；点击已有时间点可跳转。"); markList }.padding(20) }
            } else if resource.kind == .video, let url = StudyVideoURL.player(resource.url, seconds: initialSeconds) {
                EmbeddedResource(url: url, controller: web).frame(height: 240)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(resource.title).font(.headline)
                        Caption(text: resource.source + (resource.durationSeconds.map { " · " + TimeLabel.video($0) } ?? ""))
                        if let summary = resource.summary { Text(summary).font(.subheadline).foregroundColor(.secondary) }
                        HStack { Label("边看边记", systemImage: "highlighter").foregroundColor(GardenTheme.mint); Spacer(); Button("打开原视频") { if let url = SearchEngine.validatedURL(resource.url) { browser = BrowserLink(url: url) } } }.font(.subheadline)
                        if web.failed { Text("播放器暂时未加载，可打开原视频继续学习。").font(.caption).foregroundColor(.secondary) }
                        Caption(text: "视频由原平台播放，登录与清晰度按平台规定。")
                        markList
                    }.padding(16)
                }
            } else if resource.body.isEmpty, let url = SearchEngine.validatedURL(resource.url) {
                EmbeddedResource(url: url, controller: web)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(resource.title).font(.title2.bold()); Caption(text: resource.source)
                        if resource.isPaid { Text("可能需要积分或付费，请先看原页面说明。").font(.caption).foregroundColor(.orange) }
                        if !resource.url.isEmpty { Button { if let url = SearchEngine.validatedURL(resource.url) { browser = BrowserLink(url: url) } } label: { Label(resource.kind == .video ? "打开原平台视频" : "查看原资料", systemImage: "arrow.up.right.square") }; Caption(text: "外部视频在原平台播放；返回这里可手动记录时间点与重点。") }
                        if !resource.body.isEmpty {
                            Text("长按选中文字 → 划重点").font(.caption).foregroundColor(GardenTheme.mint)
                            HighlightText(text: resource.body, quotes: marks.map(\.quote), height: $textHeight) { draft = NoteDraft(quote: $0) }.frame(height: textHeight)
                        }
                        markList
                    }.padding(20)
                }
            }
            Divider()
            Button {
                if resource.kind == .video { web.currentSeconds { seconds in draft = NoteDraft(seconds: seconds) }; return }
                var seconds: Int?
                if let time = player?.currentTime().seconds, time.isFinite, time >= 0, time <= 86400 { seconds = Int(time) }
                draft = NoteDraft(seconds: seconds)
            } label: { Label(resource.kind == .localVideo || resource.kind == .video ? "标记时间 · 写笔记" : "写笔记", systemImage: "highlighter").font(.headline).frame(maxWidth: .infinity).padding(15) }.background(GardenTheme.card).accessibilityIdentifier("study-note")
        }.background(GardenTheme.background).navigationTitle(resource.kind.label).navigationBarTitleDisplayMode(.inline)
        .toolbar { if !resource.id.hasPrefix("curated-") && resource.checkedAt == nil { Button { showDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("移除资料") } }
        .sheet(item: $draft) { value in NoteEditor(lessonID: resource.lessonID, resourceID: resource.id, regions: value.regions, quote: value.quote, timestamp: value.seconds.map(TimeLabel.video) ?? "") }
        .sheet(item: $browser) { SafariSheet(url: $0.url) }
        .onAppear { store.remember(resource); if resource.kind == .localVideo, player == nil, let url = localURL { let value = AVPlayer(url: url); if let seconds = initialSeconds { value.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600)) }; player = value } }
        .onDisappear { player?.pause() }
        .alert("从资料库移除？", isPresented: $showDelete) { Button("移除", role: .destructive) { remove() }; Button("取消", role: .cancel) {} } message: { Text("笔记会保留。已导入的文件保留在本机，不会删除外部原资料。") }
    }
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder private var markList: some View {
        if !marks.isEmpty { Text("学习笔记").font(.headline) }
        ForEach(marks) { mark in
            if let seconds = mark.seconds, player != nil { Button("跳到 " + TimeLabel.video(seconds)) { player?.seek(to: CMTime(seconds: Double(seconds), preferredTimescale: 600)) } }
            MarkCard(mark: mark)
        }
    }
    private func remove() { if store.update({ $0.resources.removeAll { $0.id == resource.id } }) { dismiss() } }
}

final class MarkableTextView: UITextView {
    var onHeight: ((CGFloat) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); if bounds.width > 0 { onHeight?(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height) } }
    var onMark: ((String) -> Void)?
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(markSelection) { return selectedRange.length > 0 }
        return super.canPerformAction(action, withSender: sender)
    }
    override func becomeFirstResponder() -> Bool {
        UIMenuController.shared.menuItems = [UIMenuItem(title: "划重点", action: #selector(markSelection))]
        return super.becomeFirstResponder()
    }
    @objc func markSelection() {
        guard selectedRange.length > 0, NSMaxRange(selectedRange) <= (text as NSString).length else { return }
        onMark?((text as NSString).substring(with: selectedRange))
    }
}
struct HighlightText: UIViewRepresentable {
    let text: String; let quotes: [String]; @Binding var height: CGFloat; let onMark: (String) -> Void
    func makeUIView(context: Context) -> MarkableTextView {
        let view = MarkableTextView(); view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: MarkableTextView, context: Context) {
        view.onMark = onMark
        view.onHeight = { value in if value.isFinite && abs(height - value) > 1 { DispatchQueue.main.async { height = max(120, value) } } }
        let value = NSMutableAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label])
        let source = text as NSString
        for quote in quotes where !quote.isEmpty {
            var range = NSRange(location: 0, length: source.length)
            while range.length > 0 {
                let found = source.range(of: quote, options: [], range: range)
                if found.location == NSNotFound { break }
                value.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: found)
                range = NSRange(location: NSMaxRange(found), length: source.length - NSMaxRange(found))
            }
        }
        if view.attributedText != value { view.attributedText = value }
    }
}
final class MarkablePDFView: PDFView {
    var onMark: ((String, [PDFRegion]) -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(markSelection) { return !(currentSelection?.string ?? "").isEmpty }
        return super.canPerformAction(action, withSender: sender)
    }
    override func becomeFirstResponder() -> Bool {
        UIMenuController.shared.menuItems = [UIMenuItem(title: "划重点", action: #selector(markSelection))]
        return super.becomeFirstResponder()
    }
    @objc func markSelection() {
        guard let selection = currentSelection, let document = document else { return }
        var regions: [PDFRegion] = []
        for line in selection.selectionsByLine() { for page in line.pages { let rect = line.bounds(for: page); regions.append(PDFRegion(page: document.index(for: page), x: Double(rect.origin.x), y: Double(rect.origin.y), width: Double(rect.width), height: Double(rect.height))) } }
        onMark?(selection.string ?? "", regions)
    }
}
final class PDFReadingHost: UIView {
    let pdf = MarkablePDFView()
    let status = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        let select = UIButton(type: .system); select.setTitle("选择本页文字", for: .normal)
        select.addAction(UIAction { [weak self] _ in
            guard let self = self, let page = self.pdf.currentPage, let selection = page.selection(for: page.bounds(for: .mediaBox)), !(selection.string ?? "").isEmpty else { self?.status.text = "当前页没有可选文字，可手动记备注"; return }
            self.pdf.setCurrentSelection(selection, animate: true)
        }, for: .touchUpInside)
        let mark = UIButton(type: .system); mark.setTitle("高亮选区", for: .normal)
        mark.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            guard !(self.pdf.currentSelection?.string ?? "").isEmpty else { self.status.text = "先长按选中文字，或选择本页文字"; return }
            self.pdf.markSelection()
        }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [select,mark]); row.axis = .horizontal; row.distribution = .fillEqually
        status.font = .preferredFont(forTextStyle: .caption1); status.textAlignment = .center; status.numberOfLines = 2
        let top = UIStackView(arrangedSubviews: [row,status]); top.axis = .vertical; top.spacing = 5
        top.translatesAutoresizingMaskIntoConstraints = false; pdf.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top); addSubview(pdf)
        NSLayoutConstraint.activate([top.topAnchor.constraint(equalTo: topAnchor, constant: 8),top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),pdf.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),pdf.leadingAnchor.constraint(equalTo: leadingAnchor),pdf.trailingAnchor.constraint(equalTo: trailingAnchor),pdf.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
}
struct PDFReader: UIViewRepresentable {
    let url: URL; let marks: [StudyMark]; let onMark: (String, [PDFRegion]) -> Void
    func makeUIView(context: Context) -> PDFReadingHost { let host = PDFReadingHost(); let view = host.pdf; view.autoScales = true; view.displayDirection = .vertical; view.displayMode = .singlePageContinuous; view.document = PDFDocument(url: url); return host }
    func updateUIView(_ host: PDFReadingHost, context: Context) {
        let view = host.pdf
        view.onMark = onMark
        guard let document = view.document else { return }
        for n in 0..<document.pageCount { if let page = document.page(at: n) { for annotation in page.annotations where annotation.contents == "XinxinHighlight" { page.removeAnnotation(annotation) } } }
        for mark in marks { for region in mark.regions { guard region.page >= 0, let page = document.page(at: region.page) else { continue }; let annotation = PDFAnnotation(bounds: CGRect(x: region.x, y: region.y, width: region.width, height: region.height), forType: .highlight, withProperties: nil); annotation.color = UIColor.systemYellow.withAlphaComponent(0.4); annotation.contents = "XinxinHighlight"; page.addAnnotation(annotation) } }
        let count = (0..<document.pageCount).reduce(0) { total, page in total + (document.page(at: page)?.annotations.filter { $0.contents == "XinxinHighlight" }.count ?? 0) }
        host.status.text = "已保存 \(count) 处高亮"
    }
}
