import SwiftUI
import WebKit

/// 内嵌网页版页面的 WebView 包装（车辆状态 / 360全景）
/// 网页版 embed=1 模式下为纯内容布局，无站点头部，直接全屏渲染即可
struct WebViewBridge: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // URL 不变则不重复加载；变化时重新加载
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
