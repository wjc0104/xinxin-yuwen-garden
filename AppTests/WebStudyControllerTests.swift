import XCTest
import WebKit
@testable import XinxinGarden

/// Records navigation requests without making any network request or handling credentials.
private final class RecordingStudyWebView: WKWebView {
    var requests: [URLRequest] = []
    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        return nil
    }
}

/// Synthetic HTML is served through an offline scheme, retaining a real document hostname in WebKit.
/// No request, cookie, or article text is obtained from an external service.
private final class PoetryFixtureHandler: NSObject, WKURLSchemeHandler {
    let html: String
    init(_ html: String) { self.html = html }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let response = URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html", expectedContentLength: -1, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(html.utf8))
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class PoetryFixtureNavigation: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        XCTFail("Offline fixture navigation failed: \(error)"); loaded.fulfill()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        XCTFail("Offline fixture navigation failed: \(error)"); loaded.fulfill()
    }
}

@MainActor final class WebStudyControllerTests: XCTestCase {
    // Authored test text only. The styles model the site's preview fade and hidden/clipped full block.
    private func pair(_ kind: String, _ id: Int, text: String) -> String {
        """
        <section><div id="\(kind)\(id)" class="sons"><h2>节选</h2><p>简短预览</p>
        <div class="fade" onclick="window.fixtureReadMore = true">展开</div></div>
        <div id="\(kind)quan\(id)" class="sons" hidden style="display:none!important;height:1px;max-height:1px;overflow:hidden">
        <div class="contyishang" style="height:1px;max-height:1px;overflow:hidden"><h2>测试标题</h2><p>\(text)</p>
        <div class="credit"><a href="/author">测试作者</a></div><a href="javascript:void(0)">收起</a></div></div></section>
        """
    }

    private func fixture(host: String, body: String) async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(PoetryFixtureHandler("<!doctype html><html><head><meta charset='utf-8'></head><body>\(body)</body></html>"), forURLScheme: "study-fixture")
        config.userContentController.addUserScript(WKUserScript(source: EmbeddedResource.poetryScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        let loaded = expectation(description: "Offline public poetry DOM loaded on \(host)")
        let navigation = PoetryFixtureNavigation(loaded)
        webView.navigationDelegate = navigation
        webView.load(URLRequest(url: try XCTUnwrap(URL(string: "study-fixture://\(host)/article"))))
        await fulfillment(of: [loaded], timeout: 5)
        withExtendedLifetime(navigation) {}
        webView.navigationDelegate = nil
        return webView
    }

    /// Wait one rendering turn and one task so MutationObserver changes are reflected in layout.
    private func rendered(_ webView: WKWebView) async throws {
        _ = try await webView.callAsyncJavaScript("await new Promise(resolve => setTimeout(resolve, 0)); return true;", arguments: [:], in: nil, contentWorld: .page)
    }

    func testPublicPoetryPairsRevealDeliveredTextAndKeepSelectionAndCredits() async throws {
        for host in ["gushiwen.cn", "www.gushiwen.cn", "m.guwendao.net", "guwendao.net"] {
            let web = try await fixture(host: host, body: pair("fanyi", 17, text: "完整译文甲。完整译文乙。") + pair("shangxi", 83, text: String(repeating: "公开赏析的后续段落。", count: 40)) + pair("fanyi", 291, text: "第二篇资料的注释。"))
            // Production also invokes the same script at didFinish; repeated execution must be harmless.
            _ = try await web.evaluateJavaScript(EmbeddedResource.poetryScript + "\ntrue;")
            try await rendered(web)
            let result = try await web.evaluateJavaScript("""
            ['fanyiquan17', 'shangxiquan83', 'fanyiquan291'].every(function(id) {
              var full = document.getElementById(id), content = full.querySelector('.contyishang');
              var preview = document.getElementById(id.replace('quan', ''));
              return getComputedStyle(full).display !== 'none' && !full.hidden &&
                full.clientHeight >= full.scrollHeight && content.clientHeight >= content.scrollHeight &&
                getComputedStyle(preview).display === 'none' && full.querySelector('h2').textContent === '测试标题' &&
                full.querySelector('.credit a').getAttribute('href') === '/author';
            }) && document.querySelectorAll('style').length === 2 && !window.fixtureReadMore
            """)
            XCTAssertEqual(result as? Bool, true, host)
            _ = try await web.evaluateJavaScript("var range = document.createRange(); range.selectNodeContents(document.querySelector('#fanyiquan17 p')); window.getSelection().removeAllRanges(); window.getSelection().addRange(range); true;")
            let controller = WebStudyController()
            controller.attach(web, originalURL: try XCTUnwrap(URL(string: "https://\(host)/article")))
            let selected = expectation(description: "Expanded public text can still be selected for a note")
            controller.selectedText { value in
                XCTAssertEqual(value, "完整译文甲。完整译文乙。"); selected.fulfill()
            }
            await fulfillment(of: [selected], timeout: 3)
        }
    }

    func testDynamicPublicPairsAndEmptyPlaceholders() async throws {
        let web = try await fixture(host: "www.guwendao.net", body: pair("fanyi", 17, text: " \n ") + pair("shangxi", 83, text: ""))
        let empty = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('fanyi17')).display !== 'none' && document.getElementById('fanyiquan17').hidden && getComputedStyle(document.getElementById('shangxi83')).display !== 'none'")
        XCTAssertEqual(empty as? Bool, true, "A heading, credit and controls alone do not establish complete public article content")
        // Populate a placeholder's text node and insert an entirely new pair after document-end.
        _ = try await web.callAsyncJavaScript("""
        document.querySelector('#fanyiquan17 p').firstChild.textContent = '稍后送达的公开译文。';
        document.body.insertAdjacentHTML('beforeend', newPair);
        return true;
        """, arguments: ["newPair": pair("shangxi", 902, text: "动态插入的公开赏析。")], in: nil, contentWorld: .page)
        try await rendered(web)
        // Site scripts may reapply clipping during initial load; the bounded observer remains idempotent.
        _ = try await web.evaluateJavaScript("document.getElementById('shangxiquan902').style.setProperty('display', 'none', 'important'); true;")
        try await rendered(web)
        let dynamic = try await web.evaluateJavaScript("getComputedStyle(document.getElementById('fanyi17')).display === 'none' && getComputedStyle(document.getElementById('fanyiquan17')).display !== 'none' && getComputedStyle(document.getElementById('shangxi902')).display === 'none' && getComputedStyle(document.getElementById('shangxiquan902')).display !== 'none' && getComputedStyle(document.getElementById('shangxi83')).display !== 'none' && document.getElementById('shangxiquan83').hidden")
        XCTAssertEqual(dynamic as? Bool, true)
    }

    func testPublicPresentationDoesNotRunOnUnrelatedOrLookalikeDocuments() async throws {
        for host in ["example.com", "notguwendao.net", "gushiwen.cn.evil.test", "www.guwendao.net.evil.test"] {
            // Deliberately inject the production script even here, as happens after manual navigation.
            let web = try await fixture(host: host, body: pair("fanyi", 17, text: "域外测试文字。") + "<a id='install' href='/app/Default'>下载APP</a>")
            let untouched = try await web.evaluateJavaScript("document.getElementById('fanyiquan17').hidden && getComputedStyle(document.getElementById('fanyi17')).display !== 'none' && getComputedStyle(document.getElementById('install')).display !== 'none' && document.querySelectorAll('style').length === 0 && !window.__gardenPublicPoetry")
            XCTAssertEqual(untouched as? Bool, true, host)
        }
    }

    func testPoetryHostRequiresExactDomainOrSubdomainBoundary() {
        for host in ["gushiwen.cn", "www.gushiwen.cn", "m.gushiwen.cn", "GUWENDAO.NET", "www.guwendao.net", "user.www.guwendao.net"] {
            XCTAssertTrue(EmbeddedResource.isPoetrySite(host), host)
        }
        for host in ["", "example.com", "notgushiwen.cn", "gushiwen.cn.evil.test", "evilguwendao.net", "www.guwendao.net.evil.test", "gushiwen.cn@evil.test"] {
            XCTAssertFalse(EmbeddedResource.isPoetrySite(host), host)
        }
    }

    func testLoginAndReturnUseSameWebViewAndExactOriginalURL() throws {
        for source in ["https://www.gushiwen.cn/shiwenv_630c04c81858.aspx?from=reader#translation", "https://m.guwendao.net/shiwenv_630c04c81858.aspx"] {
            let original = try XCTUnwrap(URL(string: source))
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = RecordingStudyWebView(frame: .zero, configuration: configuration)
            let dataStore = webView.configuration.websiteDataStore
            webView.customUserAgent = "reader-session-test"
            let controller = WebStudyController()
            controller.attach(webView, originalURL: original)
            XCTAssertFalse(controller.canReturnToOriginal)
            controller.returnToOriginal()
            XCTAssertTrue(webView.requests.isEmpty)

            controller.openLogin()
            XCTAssertTrue(controller.canReturnToOriginal, "This indicates navigation availability, never authentication success")
            controller.openLogin() // Repeating login must not replace the saved resource with the login URL.
            controller.returnToOriginal()

            XCTAssertEqual(webView.requests.compactMap(\.url).map(\.absoluteString), [
                "https://www.guwendao.net/user/wode.aspx",
                "https://www.guwendao.net/user/wode.aspx",
                source
            ])
            XCTAssertTrue(controller.webView === webView)
            XCTAssertTrue(webView.configuration.websiteDataStore === dataStore)
            XCTAssertEqual(webView.customUserAgent, "reader-session-test")
            XCTAssertEqual(controller.originalURL, original)
            XCTAssertFalse(controller.canReturnToOriginal)
        }
    }

    func testUnsupportedOrInvalidOriginalCannotOpenPoetryLogin() throws {
        for source in ["https://gushiwen.cn.evil.test/article", "https://notguwendao.net/article", "https://example.com/gushiwen.cn", "file://www.gushiwen.cn/article", "https://user@www.gushiwen.cn/article"] {
            let webView = RecordingStudyWebView(frame: .zero)
            let controller = WebStudyController()
            controller.attach(webView, originalURL: try XCTUnwrap(URL(string: source)))
            controller.openLogin()
            controller.returnToOriginal()
            XCTAssertTrue(webView.requests.isEmpty, source)
            XCTAssertFalse(controller.canReturnToOriginal, source)
        }
    }

    func testDetachedReaderDoesNotClaimNavigationStarted() {
        let controller = WebStudyController()
        controller.openLogin()
        controller.returnToOriginal()
        XCTAssertFalse(controller.canReturnToOriginal)
        XCTAssertNil(controller.originalURL)
    }
}
