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
    @State private var showDelete = false
    @State private var webSelectionMessage: String?
    @StateObject private var web = WebStudyController()
    @StateObject private var selection = TextSelectionController()
    @State private var textHeight: CGFloat = 400
    var marks: [StudyMark] { store.data.marks.filter { $0.resourceID == resource.id } }
    var localURL: URL? { guard !resource.localFile.isEmpty else { return nil }; return try? store.disk?.attachmentURL(resource.localFile) }
    var isVideo: Bool { resource.kind == .video || resource.kind == .localVideo }
    var isWebText: Bool { !isVideo && resource.kind != .pdf && resource.body.isEmpty && SearchEngine.validatedURL(resource.url) != nil }
    var body: some View {
        VStack(spacing: 0) {
            if isVideo {
                VideoStudyView(resource: resource, initialSeconds: initialSeconds)
            } else if resource.kind == .pdf, let url = localURL {
                PDFReader(url: url, marks: marks) { text, regions in draft = NoteDraft(quote: text, regions: regions) }
            } else if resource.body.isEmpty, let url = SearchEngine.validatedURL(resource.url) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(resource.source).font(.caption).lineLimit(1)
                        Spacer(minLength: 8)
                        Button { browser = BrowserLink(url: url) } label: { Label("浏览器打开", systemImage: "safari").font(.caption) }.accessibilityIdentifier("open-in-browser").fixedSize()
                    }
                    Text(web.failed ? "原站加载失败，可稍后重试、用浏览器打开或写笔记。" : "原作者公开文字 · 若原站要求启动 App 或限制阅读，可点上方“浏览器打开”。").font(.caption).foregroundColor(.secondary)
                    if let message = webSelectionMessage { Text(message).font(.caption).foregroundColor(GardenTheme.mint) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                EmbeddedResource(url: url, controller: web)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(resource.title).font(.title2.bold()); Caption(text: resource.source)
                        if resource.isPaid { Text("可能需要积分或付费，请先看原页面说明。").font(.caption).foregroundColor(.orange) }
                        if !resource.url.isEmpty { Button { if let url = SearchEngine.validatedURL(resource.url) { browser = BrowserLink(url: url) } } label: { Label("查看原资料", systemImage: "arrow.up.right.square") } }
                        if !resource.body.isEmpty {
                            Text("长按选中文字，再点下方“划重点”").font(.caption).foregroundColor(GardenTheme.mint)
                            let highlighted = marks.filter { !$0.quote.isEmpty }
                            if !highlighted.isEmpty { Text("已保存 \(highlighted.count) 处重点").font(.caption).foregroundColor(GardenTheme.mint) }
                            HighlightText(text: resource.body, quotes: highlighted.map(\.quote), height: $textHeight, selection: selection) { quote in
                                guard !marks.contains(where: { $0.quote == quote }) else { return }
                                store.update { $0.marks.append(StudyMark(lessonID: resource.lessonID, resourceID: resource.id, quote: quote, note: "")) }
                            }.frame(height: textHeight)
                        }
                        markList
                    }.padding(20)
                }
            }
            if !isVideo {
            Divider()
            HStack(spacing: 0) {
            if isWebText {
                Button { web.selectedText { quote in
                    if quote.isEmpty { webSelectionMessage = "请先长按选中文字；原站限制选区时可手动写笔记。" }
                    else { webSelectionMessage = nil; draft = NoteDraft(quote: quote) }
                } } label: { Label("摘录选中文字", systemImage: "highlighter").font(.headline).frame(maxWidth: .infinity).padding(15) }.accessibilityIdentifier("web-quote-selection")
                Divider().frame(height: 24)
            }
            if !resource.body.isEmpty && resource.kind != .pdf && resource.kind != .video && resource.kind != .localVideo {
                Button { selection.mark() } label: { Label("划重点", systemImage: "highlighter").font(.headline).frame(maxWidth: .infinity).padding(15) }.disabled(!selection.hasSelection).accessibilityIdentifier("highlight-selection")
                Divider().frame(height: 24)
            }
            Button {
                draft = NoteDraft()
            } label: { Label(resource.kind == .localVideo || resource.kind == .video ? "标记时间 · 写笔记" : "写笔记", systemImage: "square.and.pencil").font(.headline).frame(maxWidth: .infinity).padding(15) }.accessibilityIdentifier("study-note")
            }.background(GardenTheme.card)
            }
        }.background(GardenTheme.background).navigationTitle(resource.kind.label).navigationBarTitleDisplayMode(.inline)
        .toolbar { if !resource.id.hasPrefix("curated-") && resource.checkedAt == nil { Button { showDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("移除资料") } }
        .sheet(item: $draft) { value in NoteEditor(lessonID: resource.lessonID, resourceID: resource.id, regions: value.regions, quote: value.quote, timestamp: value.seconds.map(TimeLabel.video) ?? "") }
        .sheet(item: $browser) { SafariSheet(url: $0.url) }
        .onAppear { store.remember(resource) }
        .alert("从资料库移除？", isPresented: $showDelete) { Button("移除", role: .destructive) { remove() }; Button("取消", role: .cancel) {} } message: { Text("笔记会保留。已导入的文件保留在本机，不会删除外部原资料。") }
    }
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder private var markList: some View {
        if !marks.isEmpty { Text("学习笔记").font(.headline) }
        ForEach(marks) { mark in
            MarkCard(mark: mark)
        }
    }
    private func remove() { if store.update({ $0.resources.removeAll { $0.id == resource.id } }) { dismiss() } }
}

final class TextSelectionController: ObservableObject {
    weak var textView: MarkableTextView?
    @Published private(set) var hasSelection = false
    func changed(_ view: MarkableTextView) {
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self = self, let view = view, self.textView === view else { return }
            let selected = view.selectedRange.length > 0
            if self.hasSelection != selected { self.hasSelection = selected }
        }
    }
    func mark() { textView?.markSelection() }
}
final class MarkableTextView: UITextView {
    var renderedText: String?
    var renderedQuotes: [String] = []
    var renderedFont: UIFont?
    private var measuredWidth: CGFloat = 0
    var needsTextMeasurement = true
    var onHeight: ((CGFloat) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && (needsTextMeasurement || abs(bounds.width - measuredWidth) > 0.5) {
            measuredWidth = bounds.width; needsTextMeasurement = false
            onHeight?(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)
        }
    }
    var onMark: ((String) -> Void)?
    override var canBecomeFirstResponder: Bool { true }
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
        let quote = (text as NSString).substring(with: selectedRange)
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        selectedRange = NSRange(location: selectedRange.location, length: 0)
        resignFirstResponder()
        UIMenuController.shared.hideMenu()
        onMark?(quote)
    }
}
struct HighlightText: UIViewRepresentable {
    let text: String; let quotes: [String]; @Binding var height: CGFloat; let selection: TextSelectionController; let onMark: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selection: selection) }
    func makeUIView(context: Context) -> MarkableTextView {
        let view = MarkableTextView(); view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "study-text"
        view.delegate = context.coordinator; selection.textView = view
        return view
    }
    func updateUIView(_ view: MarkableTextView, context: Context) {
        view.onMark = onMark
        view.onHeight = { value in if value.isFinite && abs(height - value) > 1 { DispatchQueue.main.async { height = max(120, value) } } }
        let font = UIFont.preferredFont(forTextStyle: .body)
        guard view.renderedText != text || view.renderedQuotes != quotes || view.renderedFont != font else { return }
        let range = view.selectedRange
        let value = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
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
        view.renderedText = text; view.renderedQuotes = quotes; view.renderedFont = font
        view.attributedText = value
        if NSMaxRange(range) <= source.length { view.selectedRange = range }
        view.needsTextMeasurement = true; view.setNeedsLayout()
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        let selection: TextSelectionController
        init(selection: TextSelectionController) { self.selection = selection }
        func textViewDidChangeSelection(_ textView: UITextView) { if let view = textView as? MarkableTextView { selection.changed(view) } }
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
