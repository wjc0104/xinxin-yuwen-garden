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
    /// Content sites place an app-install prompt, a QR code and an "expand to read" link inside the
    /// article; tapping expand replaces the page with an app wall. Remove those entry points so the
    /// article that is already on the page can be read directly.
    private static let cleanupScript = """
    (function () {
      var style = document.createElement('style');
      style.textContent = [
        'a[href*="app/Default"], a[href*="itunes.apple.com"], a[href*="//app/"] { display: none !important; }',
        'a[href^="javascript:fanyiShow"], a[href^="javascript:shangxiShow"] { display: none !important; }'
      ].join('');
      (document.head || document.documentElement).appendChild(style);
      var nodes = document.body ? document.body.querySelectorAll('*') : [];
      for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i];
        if (node.children.length) { continue; }
        if (/^\\s*(展开阅读全文|扫码下载APP|下载古文岛App|下载APP|打开APP)\\s*$/.test(node.textContent || '')) {
          node.style.display = 'none';
        }
      }
    })();
    """
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.addUserScript(WKUserScript(source: EmbeddedResource.cleanupScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        // Present as Mobile Safari. Several content sites replace the whole page with an "open our
        // app" wall when the user agent looks like a bare in-app web view.
        let system = UIDevice.current.systemVersion
        let token = system.replacingOccurrences(of: ".", with: "_")
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(token) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(system) Mobile/15E148 Safari/604.1"
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
        init(_ controller: WebStudyController) { self.controller = controller }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { controller.failed = false }
        // Run once more after load: some pages insert the prompt block from script.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webView.evaluateJavaScript(EmbeddedResource.cleanupScript, completionHandler: nil) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(["https","http","about"].contains(scheme) ? .allow : .cancel)
        }
    }
}
