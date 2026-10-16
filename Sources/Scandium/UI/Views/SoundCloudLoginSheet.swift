// SoundCloudLoginSheet.swift — WKWebView Popup Sheet with Automatic OAuth Token / Cookie Observer
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import WebKit

struct SoundCloudLoginSheet: View {
    @Binding var isPresented: Bool
    var onLoginSuccess: (() -> Void)? = nil

    @ObservedObject private var settings = AppSettings.shared
    @State private var isLoading: Bool = true
    @State private var progress: Double = 0.0

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                ScandiumTheme.bgPrimary
                    .ignoresSafeArea()

                SoundCloudLoginWebView(
                    isPresented: $isPresented,
                    isLoading: $isLoading,
                    progress: $progress,
                    onLoginSuccess: onLoginSuccess
                )
                .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    VStack(spacing: 0) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: ScandiumTheme.spotifyGreen))
                            .frame(height: 3)
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(settings.loc("Đăng nhập SoundCloud", "SoundCloud Sign In"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        isPresented = false
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    // MARK: - Sign Out & Session Cleanup

    /// Cleans up old soundcloud.com cookies and website storage so future sign-in prompts start fresh.
    /// SAFE: Only called explicitly on user sign-out action (never in any init).
    static func clearSoundCloudCookies(completion: (() -> Void)? = nil) {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()

            for cookie in cookies {
                let domain = cookie.domain.lowercased()
                if domain.contains("soundcloud") || cookie.name == "oauth_token" {
                    group.enter()
                    cookieStore.delete(cookie) {
                        group.leave()
                    }
                }
            }

            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: dataTypes) { records in
                let scRecords = records.filter { $0.displayName.lowercased().contains("soundcloud") }
                if !scRecords.isEmpty {
                    group.enter()
                    WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, for: scRecords) {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    completion?()
                }
            }
        }
    }
}

// MARK: - UIViewRepresentable (WKWebView + Cookie Observer)

struct SoundCloudLoginWebView: UIViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var isLoading: Bool
    @Binding var progress: Double
    var onLoginSuccess: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = ""
        configuration.allowsInlineMediaPlayback = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Mobile Safari standard User-Agent to avoid being blocked by SoundCloud
        let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Mobile/15E148 Safari/604.1"
        webView.customUserAgent = safariUserAgent
        webView.allowsBackForwardNavigationGestures = true

        // Register WKHTTPCookieStoreObserver
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.add(context.coordinator)
        context.coordinator.cookieStore = cookieStore

        // Set up progress observer safely
        context.coordinator.observeProgress(for: webView)

        // Initial check for pre-existing oauth_token cookie
        context.coordinator.checkCookies(in: cookieStore)

        // Load SoundCloud sign-in endpoint
        if let url = URL(string: "https://soundcloud.com/signin") {
            var request = URLRequest(url: url)
            request.setValue("https://soundcloud.com", forHTTPHeaderField: "Referer")
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        coordinator.cleanup(for: uiView)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        var parent: SoundCloudLoginWebView
        weak var cookieStore: WKHTTPCookieStore?
        private var hasCapturedToken: Bool = false
        private var progressObservation: NSKeyValueObservation?

        init(_ parent: SoundCloudLoginWebView) {
            self.parent = parent
            super.init()
        }

        func observeProgress(for webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = wv.estimatedProgress
                }
            }
        }

        func cleanup(for webView: WKWebView) {
            progressObservation?.invalidate()
            progressObservation = nil
            if let store = cookieStore {
                store.remove(self)
                self.cookieStore = nil
            }
        }

        func checkCookies(in cookieStore: WKHTTPCookieStore) {
            guard !hasCapturedToken else { return }

            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasCapturedToken else { return }

                if let oauthCookie = cookies.first(where: { $0.name == "oauth_token" && !$0.value.isEmpty }) {
                    self.hasCapturedToken = true
                    let tokenValue = oauthCookie.value

                    cookieStore.remove(self)
                    self.cookieStore = nil

                    DispatchQueue.main.async {
                        SoundCloudAuthManager.shared.saveToken(tokenValue)
                        self.parent.onLoginSuccess?()
                        self.parent.isPresented = false
                    }
                }
            }
        }

        // MARK: - WKHTTPCookieStoreObserver

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            checkCookies(in: cookieStore)
        }

        // MARK: - WKNavigationDelegate Security & Handlers

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Only allow standard http/https schemes for safe authentication
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
            if let store = cookieStore {
                checkCookies(in: store)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        // MARK: - WKUIDelegate (Support OAuth Popups like Google/Apple within webview)

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
