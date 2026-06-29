import SwiftUI
import WebKit

struct BrowserTabData: Identifiable {
    let id: UUID
    var url: URL?
    let store: WebViewStore

    init(url: URL? = nil) {
        id = UUID()
        self.url = url
        store = WebViewStore()
    }
}

final class WebViewStore: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
}

struct BrowserPanel: View {
    @Binding var url: URL?
    @ObservedObject var store: WebViewStore
    @State private var addressText = ""

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            Divider()
            if let u = url {
                AgentWebView(url: u, store: store) { navigated in
                    url = navigated
                    addressText = navigated.absoluteString
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Enter a URL or click a port to preview")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: url, initial: true) { _, newURL in
            addressText = newURL?.absoluteString ?? ""
        }
    }

    private var addressBar: some View {
        HStack(spacing: 4) {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left").frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!store.canGoBack)
            .accessibilityLabel("Back")
            Button { store.goForward() } label: {
                Image(systemName: "chevron.right").frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!store.canGoForward)
            .accessibilityLabel("Forward")
            TextField("https://", text: $addressText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { navigate() }
            Button { store.reload() } label: {
                Image(systemName: "arrow.clockwise").frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.borderless)
            .disabled(url == nil)
            .accessibilityLabel("Reload")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func navigate() {
        var text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.lowercased().hasPrefix("http") { text = "https://\(text)" }
        url = URL(string: text)
    }
}

private struct AgentWebView: NSViewRepresentable {
    let url: URL
    let store: WebViewStore
    let onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, onNavigate: onNavigate) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        store.webView = webView
        context.coordinator.observe(webView)
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        guard url != context.coordinator.lastLoadedURL else { return }
        context.coordinator.lastLoadedURL = url
        nsView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let store: WebViewStore
        var onNavigate: (URL) -> Void
        var lastLoadedURL: URL?
        private var observations: [NSKeyValueObservation] = []

        init(store: WebViewStore, onNavigate: @escaping (URL) -> Void) {
            self.store = store
            self.onNavigate = onNavigate
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.store.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.store.canGoForward = wv.canGoForward }
                },
            ]
        }

        func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
            guard let url = webView.url else { return }
            lastLoadedURL = url
            DispatchQueue.main.async { [weak self] in self?.onNavigate(url) }
        }
    }
}
