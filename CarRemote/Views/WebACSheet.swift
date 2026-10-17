import SwiftUI
import WebKit
import CarCore

// MARK: - 网页版空调（稳定通道）
// 直接内嵌站点的 user_info 页（带凭据自动登录）。
// 新版空调在原生通道异常时，网页链路是验证可用的兜底方案，
// 由站点自己的 JS（newAC）执行，行为与网页版完全一致。

struct WebACSheet: View {
    let credentials: Credentials
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var progress: Double = 0

    var body: some View {
        NavigationStack {
            WebACWebView(
                url: makeURL(),
                isLoading: $isLoading,
                progress: $progress
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("网页版空调")
                            .font(.system(size: 15, weight: .semibold))
                        Text("与网页版完全一致 · 自动登录")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        NotificationCenter.default.post(
                            name: Notification.Name("webac.reload"), object: nil
                        )
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .overlay {
                if isLoading {
                    GeometryReader { geo in
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: geo.size.width, height: 2, alignment: .top)
                            .tint(.blue)
                    }
                }
            }
        }
    }

    /// 站点支持 URL 参数自动登录：/user_info?phone=&ref_token=&pin=
    private func makeURL() -> URL {
        var components = URLComponents(string: APIConfig.siteBaseURL + "/user_info")!
        components.queryItems = [
            URLQueryItem(name: "phone", value: credentials.phone),
            URLQueryItem(name: "ref_token", value: credentials.refToken),
            URLQueryItem(name: "pin", value: credentials.pin)
        ]
        return components.url!
    }
}

// MARK: - WKWebView 封装

private struct WebACWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var progress: Double

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 网页版空调逻辑依赖 localStorage 缓存凭证，必须持久化
        config.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.isLoading), options: .new, context: nil)

        // 顶部「刷新」按钮
        context.coordinator.webView = webView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.reload),
            name: Notification.Name("webac.reload"),
            object: nil
        )

        var request = URLRequest(url: url)
        // 模拟移动端 Safari，保证站点输出移动版式
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebACWebView
        weak var webView: WKWebView?

        init(parent: WebACWebView) {
            self.parent = parent
        }

        @objc func reload() {
            webView?.reload()
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard let webView else { return }
            DispatchQueue.main.async {
                if keyPath == #keyPath(WKWebView.estimatedProgress) {
                    self.parent.progress = webView.estimatedProgress
                } else if keyPath == #keyPath(WKWebView.isLoading) {
                    self.parent.isLoading = webView.isLoading
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
