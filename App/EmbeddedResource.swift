import SwiftUI
import WebKit
import GardenCore

final class WebStudyController: ObservableObject {
    weak var webView: WKWebView?
    @Published var failed = false
    func currentSeconds(_ completion: @escaping (Int?) -> Void) {
        guard let webView = webView else { completion(nil); return }
        webView.evaluateJavaScript("document.querySelector('video')?.currentTime ?? null") { value, _ in
            guard let seconds = value as? Double, seconds.isFinite, seconds >= 0, seconds <= 86400 else { completion(nil); return }
            completion(Int(seconds))
        }
    }
}
struct EmbeddedResource: UIViewRepresentable {
    let url: URL
    @ObservedObject var controller: WebStudyController
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.load(URLRequest(url: url))
        controller.webView = web
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading(); uiView.loadHTMLString("", baseURL: nil) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: WebStudyController
        init(_ controller: WebStudyController) { self.controller = controller }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(["https","http","about"].contains(scheme) ? .allow : .cancel)
        }
    }
}
enum StudyVideoURL {
    static func player(_ raw: String, seconds: Int? = nil) -> URL? {
        guard let url = SearchEngine.validatedURL(raw), url.host == "www.bilibili.com" || url.host == "bilibili.com",
              let bvid = url.pathComponents.first(where: { $0.hasPrefix("BV") }), bvid.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "p" }?.value ?? "1"
        var parts = URLComponents(string: "https://player.bilibili.com/player.html")!
        parts.queryItems = [URLQueryItem(name: "bvid", value: bvid), URLQueryItem(name: "page", value: page), URLQueryItem(name: "autoplay", value: "0"), URLQueryItem(name: "t", value: String(seconds ?? 0))]
        return parts.url
    }
}
