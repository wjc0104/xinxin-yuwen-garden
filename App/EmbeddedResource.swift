import SwiftUI
import UIKit
import WebKit
import GardenCore

final class WebStudyController: ObservableObject {
    @Published var failed = false
    @Published private(set) var canReturnToOriginal = false
    private(set) weak var webView: WKWebView?
    private(set) var originalURL: URL?
    func attach(_ webView: WKWebView, originalURL: URL) {
        self.webView = webView
        self.originalURL = originalURL
    }
    func selectedText(_ completion: @escaping (String) -> Void) {
        // Read only the user's current selection; respect original site's selection restrictions.
        guard let webView = webView else { completion(""); return }
        webView.evaluateJavaScript("window.getSelection().toString()") { value, _ in
            completion(String((value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)))
        }
    }
    /// User-driven navigation only. Login and the original resource share this WKWebView's cookies.
    func openLogin() {
        guard let originalURL = originalURL,
              SearchEngine.validatedURL(originalURL.absoluteString) != nil,
              EmbeddedResource.isPoetrySite(originalURL.host ?? ""),
              let webView = webView, let url = URL(string: "https://www.guwendao.net/user/wode.aspx") else { return }
        canReturnToOriginal = true
        webView.load(URLRequest(url: url))
    }
    func returnToOriginal() {
        guard canReturnToOriginal, let originalURL = originalURL, let webView = webView else { return }
        webView.load(URLRequest(url: originalURL))
        canReturnToOriginal = false
    }
}
struct EmbeddedResource: UIViewRepresentable {
    let url: URL
    @ObservedObject var controller: WebStudyController
    /// These presentation changes only run on the supported poetry sites (including after navigation).
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
    /// Keep the public desktop document, but reflow only recognized article structures.
    private static let fitScript = """
    function fitPoetryArticle(node) {
      if (document.documentElement.classList.contains('garden-poetry-reader')) { return; }
      var article = '.sons .contson, .sons .contyishang';
      if (node.nodeType === 1 && (node.matches(article) || node.querySelector(article))) {
        document.documentElement.classList.add('garden-poetry-reader');
        var viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) {
          viewport = document.createElement('meta');
          viewport.setAttribute('name', 'viewport');
          (document.head || document.documentElement).appendChild(viewport);
        }
        viewport.setAttribute('content', 'width=device-width, initial-scale=1');
      }
    }
    (function () {
      var style = document.createElement('style');
      style.id = 'garden-poetry-layout';
      style.textContent = [
        '{ -webkit-text-size-adjust: 100% !important; }',
        'body { width: auto !important; min-width: 0 !important; margin: 0 !important; }',
        '.maintopbc { display: none !important; }',
        '.main3, .main3 > .left, .main4 { box-sizing: border-box !important; width: auto !important; min-width: 0 !important; max-width: 100% !important; float: none !important; margin-left: 0 !important; margin-right: 0 !important; }',
        '.main3 > .right { display: none !important; }',
        '.main3 .left .sons { box-sizing: border-box !important; width: auto !important; min-width: 0 !important; max-width: 100% !important; float: none !important; margin: 12px 0 !important; }',
        '.sons > .cont, .sons > .contyishang { width: auto !important; min-width: 0 !important; margin-left: 16px !important; margin-right: 16px !important; }',
        '.sons .contson, .sons .contyishang { font-size: 18px !important; line-height: 1.8 !important; overflow-wrap: anywhere !important; }',
        '.sons .contson { width: auto !important; min-width: 0 !important; max-width: 100% !important; padding: 0 !important; }',
        '.sons .contson p, .sons .contson span, .sons .contson a, .sons .contyishang p, .sons .contyishang span, .sons .contyishang a { font-size: inherit !important; line-height: inherit !important; }',
        '.sons [style*="width:860px"], .sons [style*="width: 860px"] { max-width: 100% !important; }',
        '.sons img { max-width: 100% !important; height: auto !important; }',
        '.main4 { overflow-wrap: anywhere !important; }'
      ].map(function (rule) {
        var brace = rule.indexOf('{');
        return rule.slice(0, brace).split(',').map(function (selector) {
          return 'html.garden-poetry-reader' + (selector.trim() ? ' ' + selector.trim() : '');
        }).join(',') + rule.slice(brace);
      }).join('');
      (document.head || document.documentElement).appendChild(style);
    })();
    """
    /// Reveal only article text already delivered in the public document. Some full containers are
    /// empty placeholders; keep their original previews and controls until actual paragraphs arrive.
    private static let publicTextScript = """
    (function () {
      if (window.__gardenPublicPoetry) { return; }
      window.__gardenPublicPoetry = true;
      var selector = '[id^="fanyiquan"], [id^="shangxiquan"]';
      function show(full) {
        var match = /^(fanyi|shangxi)quan([0-9]+)$/.exec(full.id);
        if (!match) { return; }
        var paragraphs = full.querySelectorAll('.contyishang p');
        var hasText = Array.prototype.some.call(paragraphs, function (p) {
          return (p.textContent || '').trim().length > 0;
        });
        if (!hasText) { return; }
        function set(node, property, value) {
          if (node.style.getPropertyValue(property) !== value || node.style.getPropertyPriority(property) !== 'important') {
            node.style.setProperty(property, value, 'important');
          }
        }
        function reveal(node) {
          if (node.hidden) { node.hidden = false; }
          set(node, 'display', 'block');
          set(node, 'height', 'auto');
          set(node, 'max-height', 'none');
          set(node, 'overflow', 'visible');
        }
        reveal(full);
        Array.prototype.forEach.call(full.querySelectorAll('.contyishang'), reveal);
        var preview = document.getElementById(match[1] + match[2]);
        if (preview) { set(preview, 'display', 'none'); }
      }
      function related(node) {
        var element = node.nodeType === 1 ? node : node.parentElement;
        var pair = element && element.closest('[id^="fanyi"], [id^="shangxi"]');
        var match = pair && /^(fanyi|shangxi)(?:quan)?([0-9]+)$/.exec(pair.id);
        var full = match && document.getElementById(match[1] + 'quan' + match[2]);
        if (full) { show(full); }
      }
      function added(node) {
        fitPoetryArticle(node);
        related(node);
        if (!node.querySelectorAll) { return; }
        Array.prototype.forEach.call(node.querySelectorAll(selector), show);
      }
      added(document.documentElement);
      // Observe only changed pairs/subtrees, never rescan the whole page on every mutation.
      var observer = new MutationObserver(function (records) {
        records.forEach(function (record) {
          related(record.target);
          Array.prototype.forEach.call(record.addedNodes || [], added);
        });
      });
      observer.observe(document.documentElement, {
        childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['style', 'hidden']
      });
      var timeout = setTimeout(function () { observer.disconnect(); }, 15000);
      window.addEventListener('pagehide', function () { observer.disconnect(); clearTimeout(timeout); }, { once: true });
    })();
    """
    // Check the current document as well as the resource URL: manual links/login can navigate away.
    static let poetryScript = """
    (function () {
      var host = location.hostname.toLowerCase();
      if (!['gushiwen.cn', 'guwendao.net'].some(function (domain) {
        return host === domain || host.endsWith('.' + domain);
      })) { return; }
      if (window.__gardenPublicPoetry) { return; }
    """ + cleanupScript + fitScript + publicTextScript + "\n})();"
    static func isPoetrySite(_ host: String) -> Bool {
        let name = host.lowercased()
        return ["gushiwen.cn", "guwendao.net"].contains { name == $0 || name.hasSuffix("." + $0) }
    }
    private var desktop: Bool { EmbeddedResource.isPoetrySite(url.host ?? "") }
    private var injection: String { desktop ? EmbeddedResource.poetryScript : "" }
    func makeCoordinator() -> Coordinator { Coordinator(controller, desktop: desktop) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-poetry-layout") {
            config.setURLSchemeHandler(PoetryLayoutFixtureHandler(), forURLScheme: "study-fixture")
        }
        #endif
        config.userContentController.addUserScript(WKUserScript(source: injection, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        if desktop {
            // Request the desktop document, which delivers public text and optional web account access.
            web.customUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
        } else {
            // Present as Mobile Safari; several content sites wall off a bare in-app web view.
            let system = UIDevice.current.systemVersion
            let token = system.replacingOccurrences(of: ".", with: "_")
            web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(token) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(system) Mobile/15E148 Safari/604.1"
        }
        controller.attach(web, originalURL: url)
        web.navigationDelegate = context.coordinator
        web.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-poetry-layout") {
            web.load(URLRequest(url: URL(string: "study-fixture://www.guwendao.net/article")!))
        } else { web.load(URLRequest(url: url)) }
        #else
        web.load(URLRequest(url: url))
        #endif
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading(); uiView.loadHTMLString("", baseURL: nil) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: WebStudyController
        let desktop: Bool
        init(_ controller: WebStudyController, desktop: Bool) { self.controller = controller; self.desktop = desktop }
        var injection: String { desktop ? EmbeddedResource.poetryScript : "" }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { controller.failed = true }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { controller.failed = false }
        // Run once more after load: some pages insert the prompt block from script.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webView.evaluateJavaScript(injection, completionHandler: nil) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-poetry-layout"), navigationAction.request.url?.scheme == "study-fixture" {
                decisionHandler(.allow); return
            }
            // Exercise reader actions in UI tests without contacting an original site's login service.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-offline-reader") { decisionHandler(.cancel); return }
            #endif
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

#if DEBUG
/// Authored text with the public site's desktop container geometry; never a stored external article.
extension EmbeddedResource {
    static let poetryLayoutFixture = """
    <style>
    body{margin:0;font-size:12px;line-height:22px;background:#E1E0C7}
    .maintopbc{width:100%;height:45px}.main3{width:1200px;margin:auto;overflow:hidden}
    .main3 .left{width:870px;float:left}.main3 .right{width:300px;float:right}
    .main3 .left .sons{margin-top:20px;overflow:hidden;background:#F0EFE2}
    .main3 .left .sons .cont,.main3 .left .sons .contyishang{margin:15px 20px;font-size:16px;line-height:200%}
    .main3 .left .sons .contson{overflow:hidden}.main3 .left .sons .contyishang p{line-height:200%}
    .main4{width:1000px;margin:20px auto;overflow:hidden}
    </style>
    <div class="maintopbc"><div class="main3"><div style="width:300px;margin-left:720px">站点导航</div></div></div>
    <div class="main3"><div class="left"><div class="sons"><div class="cont"><h1>响应式阅读测试</h1>
    <p class="source">测试作者 · 合成资料</p><div class="contson"><p id="fixture-prose">这是用于检验手机阅读布局的合成正文。旋转屏幕后，正文应铺满可用宽度，保持清晰字号，选中的句子也应保留。</p></div></div></div>
    <div class="sons" id="fanyi17"><div class="contyishang"><p>简短预览</p></div></div>
    <div class="sons" id="fanyiquan17" style="display:none"><div class="contyishang"><h2>译文及注释</h2><p id="fixture-translation">这段合成译文用于检验原来没有调整字号的译赏容器。每一段文字都应随手机横竖屏变化重新换行，保留作者、来源和摘录功能。</p><p>继续阅读合成注释。这些文字不来自外部文章，只用于界面验证。</p><a href="/author">测试作者署名</a></div></div>
    </div><div class="right">桌面侧栏</div></div>
    <div class="main4">合成来源页脚 <a href="/source">https://example.test/abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz</a></div>
    """
}

private final class PoetryLayoutFixtureHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let html = "<!doctype html><html><head><meta charset='utf-8'></head><body>\(EmbeddedResource.poetryLayoutFixture)</body></html>"
        task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: -1, textEncodingName: "utf-8"))
        task.didReceive(Data(html.utf8)); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
#endif
