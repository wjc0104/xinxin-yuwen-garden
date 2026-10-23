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

@MainActor final class WebStudyControllerTests: XCTestCase {
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
