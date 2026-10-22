import SwiftUI
import UIKit
import WebKit
import GardenCore

final class WebStudyController: ObservableObject {
    @Published var failed = false
    weak var webView: WKWebView?
    func selectedText(_ completion: @escaping (String) -> Void) {
        // Read only the user's current selection; respect original site's selection restrictions.
        guard let webView = webView else { completion(""); return }
        webView.evaluateJavaScript("window.getSelection().toString()") { value, _ in
            completion(String((value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)))
        }
    }
}
struct EmbeddedResource: UIViewRepresentable {
    let url: URL
    @ObservedObject var controller: WebStudyController
    /// Content sites place an app-install prompt and a QR code inside the article. Remove those entry
    /// points so the article can be read directly, but leave "read more" alone: on the desktop page it
    /// expands the text in place.
    private static let cleanupScript = """
    (function () {
      var style = document.createElement('style');
      style.textContent = 'a[href*="app/Default"], a[href*="itunes.apple.com"], a[href*="//app/"] { display: none !important; }';
      (document.head || document.documentElement).appendChild(style);
      var nodes = document.body ? document.body.querySelectorAll('*') : [];
      for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i];
        if (node.children.length) { continue; }
        if (/^\\s*(扫码下载APP|下载古文岛App|下载APP|打开APP|下载客户端)\\s*$/.test(node.textContent || '')) {
          node.style.display = 'none';
        }
      }
    })();
    """
    /// The poetry sites serve a fixed 860pt desktop page; the full text is already in the document and
    /// "read more" only toggles it, so all this has to do is make that page fit a phone.
    private static let fitScript = """
    (function () {
      var head = document.head || document.documentElement;
      var viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement('meta');
        viewport.setAttribute('name', 'viewport');
        head.appendChild(viewport);
      }
      viewport.setAttribute('content', 'width=device-width, initial-scale=1');
      var style = document.createElement('style');
      style.textContent = [
        'html { -webkit-text-size-adjust: 100% !important; }',
        'body { min-width: 0 !important; }',
        '.main3, .maintop, .cont, .left, .right, .sons, .contson { width: auto !important; min-width: 0 !important; max-width: 100% !important; float: none !important; margin-left: 0 !important; margin-right: 0 !important; }',
        '.right { display: none !important; }',
        '.contson { font-size: 17px !important; line-height: 1.9 !important; padding: 10px !important; }',
        '[style*="width:860px"], [style*="width: 860px"] { max-width: 100% !important; }',
        'img { max-width: 100% !important; height: auto !important; }'
      ].join('');
      head.appendChild(style);
      // The full text is already rendered into the document; "read more" only un-hides it. Trigger it
      // directly instead of relying on a link click, which a in-app browser may refuse to follow.
      var expand = function () {
        var links = document.querySelectorAll('a[href^="javascript:shangxiShow"], a[href^="javascript:fanyiShow"]');
        for (var i = 0; i < links.length; i++) { links[i].click(); }
      };
      setTimeout(expand, 300);
      setTimeout(expand, 1200);
    })();
    """
    static func isPoetrySite(_ host: String) -> Bool {
        let name = host.lowercased()
        return name.contains("gushiwen.cn") || name.contains("guwendao.net")
    }
    private var desktop: Bool { EmbeddedResource.isPoetrySite(url.host ?? "") }
    private var injection: String { desktop ? EmbeddedResource.cleanupScript + EmbeddedResource.fitScript : EmbeddedResource.cleanupScript }
    func makeCoordinator() -> Coordinator { Coordinator(controller, desktop: desktop) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.addUserScript(WKUserScript(source: injection, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        if desktop {
            // These sites only offer the full text to a desktop browser; their phone page links to the app.
            web.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
        } else {
            // Present as Mobile Safari; several content sites wall off a bare in-app web view.
            let system = UIDevice.current.systemVersion
            let token = system.replacingOccurrences(of: ".", with: "_")
            web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(token) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(system) Mobile/15E148 Safari/604.1"
        }
        controller.webView = web
        web.navigationDelegate = context.coordinator
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading(); uiView.loadHTMLString("", baseURL: nil) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: WebStudyController
        let desktop: Bool
        init(_ controller: WebStudyController, desktop: Bool) { self.controller = controller; self.desktop = desktop }
        var injection: String { desktop ? EmbeddedResource.cleanupScript + EmbeddedResource.fitScript : EmbeddedResource.cleanupScript }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { controller.failed = false }
        // Run once more after load: some pages insert the prompt block from script.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webView.evaluateJavaScript(injection, completionHandler: nil) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { decisionHandler(.cancel); return }
            let scheme = target.scheme?.lowercased() ?? ""
            guard ["https", "http", "about"].contains(scheme) else { decisionHandler(.cancel); return }
            // App-promotion pages replace the article with a download wall; keep the reader on the article.
            if Coordinator.isAppPromotion(target) { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        static func isAppPromotion(_ url: URL) -> Bool {
            let text = url.absoluteString.lowercased()
            if text.contains("itunes.apple.com") || text.contains("apps.apple.com") { return true }
            let path = url.path.lowercased()
            return path.contains("/app/") && (path.contains("default") || path.contains("appdown"))
        }
    }
}
