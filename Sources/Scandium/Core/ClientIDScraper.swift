// ClientIDScraper.swift — Dynamic client_id extraction with multi-tier fallback
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation

final class ClientIDScraper: ObservableObject {

    // MARK: - Published State

    public enum ScraperStatus {
        case ready
        case manual
        case cached
        case fallback
        case syncing
        case online
        case fallbackError
    }

    @Published private(set) var clientID: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var status: ScraperStatus = .ready

    var statusDescription: String {
        let isEn = AppSettings.shared.language == .english
        switch status {
        case .ready: return isEn ? "Ready" : "Sẵn sàng"
        case .manual: return isEn ? "Manual" : "Thủ công"
        case .cached: return isEn ? "Cached" : "Đã lưu đệm"
        case .fallback: return isEn ? "Fallback" : "Dự phòng"
        case .syncing: return isEn ? "Syncing..." : "Đang làm mới..."
        case .online: return isEn ? "Online" : "Trực tuyến"
        case .fallbackError: return isEn ? "Fallback (Error)" : "Dự phòng (Lỗi)"
        }
    }

    var currentClientID: String? {
        clientID
    }

    // MARK: - Constants & Fallbacks

    private static let cacheKey = "scandium_client_id"
    private static let cacheTimestampKey = "scandium_client_id_timestamp"
    private static let manualOverrideKey = "scandium_manual_client_id"
    private static let clientIDLength = 32
    private static let maxCacheAge: TimeInterval = 3600 * 24 * 7 // 7 days

    /// Primary & secondary endpoints to scrape
    private static let scrapeEndpoints = [
        "https://soundcloud.com",
        "https://soundcloud.com/discover"
    ]

    /// Built-in fallback Client IDs verified for SoundCloud API v2
    static let fallbackClientIDs: [String] = [
        "A0cxVCVBD6HAZsm0P3nxKaPaZtrGqkXN",
        "2t9loNfh0ekOfkJmyJEE9dnjy02RW2EC",
        "a3e059563d7fd3372b49b37f00a00bcf",
        "iZIs9mchVcX5lhVR1EzGCJqqnegPWvd7",
        "bIjQvHau4n9iEw3iVjGZkVw5Z2t4Gk3A"
    ]

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    private static let acceptLanguage = "en-US,en;q=0.9"

    // MARK: - Private State

    private let session: URLSession
    private var refreshTask: Task<String, Error>?

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
        // Priority: Manual override -> Cached ID -> First fallback ID
        if let manual = Self.loadManualClientID() {
            self.clientID = manual
            self.status = .manual
        } else if let cached = Self.loadCachedClientID(), !Self.isCacheExpired() {
            self.clientID = cached
            self.status = .cached
        } else {
            let fallback = Self.fallbackClientIDs.first ?? "A0cxVCVBD6HAZsm0P3nxKaPaZtrGqkXN"
            Self.cacheClientID(fallback)
            self.clientID = fallback
            self.status = .fallback
        }
    }

    // MARK: - Public API

    /// Returns a valid client_id immediately, using manual/cache/fallback first,
    /// and asynchronously refreshing in the background to prevent blocking UI requests.
    @discardableResult
    func getClientID() async throws -> String {
        // 1. Manual override always has top priority
        if let manual = Self.loadManualClientID() {
            await MainActor.run {
                self.clientID = manual
                self.status = .manual
            }
            return manual
        }

        // 2. Unexpired cached ID
        if let cached = Self.loadCachedClientID(), !Self.isCacheExpired() {
            await MainActor.run {
                self.clientID = cached
                self.status = .cached
            }
            return cached
        }

        // 3. Fast fallback: return working fallback immediately and refresh in background
        if let current = clientID ?? Self.fallbackClientIDs.first {
            Task { [weak self] in
                _ = try? await self?.refreshClientID()
            }
            return current
        }

        // 4. Scrape fresh ID with fallbacks
        return try await refreshClientID()
    }

    /// Forces a fresh scrape across all endpoints, falling back to built-in list.
    @discardableResult
    func refreshClientID() async throws -> String {
        if let manual = Self.loadManualClientID() {
            await MainActor.run {
                self.clientID = manual
                self.status = .manual
            }
            return manual
        }

        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task<String, Error> { [weak self] in
            guard let self = self else {
                throw ScraperError.deallocated
            }
            await MainActor.run {
                self.isLoading = true
                self.lastError = nil
                self.status = .syncing
            }

            do {
                let id = try await self.scrapeWithFallbacks()
                Self.cacheClientID(id)
                await MainActor.run {
                    self.clientID = id
                    self.isLoading = false
                    self.status = .online
                }
                return id
            } catch {
                // If scraping fails completely, use the first built-in fallback ID
                let fallback = Self.fallbackClientIDs.first ?? "A0cxVCVBD6HAZsm0P3nxKaPaZtrGqkXN"
                Self.cacheClientID(fallback)
                await MainActor.run {
                    self.clientID = fallback
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                    self.status = .fallbackError
                }
                return fallback
            }
        }

        self.refreshTask = task
        defer { self.refreshTask = nil }

        return try await task.value
    }

    /// Sets or removes manual client_id override from Settings.
    func setManualClientID(_ id: String?) {
        if let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), id.count == Self.clientIDLength {
            UserDefaults.standard.set(id, forKey: Self.manualOverrideKey)
            self.clientID = id
            self.status = .manual
            self.lastError = nil
        } else {
            UserDefaults.standard.removeObject(forKey: Self.manualOverrideKey)
            if let cached = Self.loadCachedClientID() {
                self.clientID = cached
                self.status = .cached
            } else {
                self.clientID = Self.fallbackClientIDs.first
                self.status = .fallback
            }
        }
    }

    var manualClientID: String? {
        Self.loadManualClientID()
    }

    var isManualOverride: Bool {
        Self.loadManualClientID() != nil
    }

    /// Clears cached client_id, forcing re-scrape.
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
        if !isManualOverride {
            self.clientID = Self.fallbackClientIDs.first
            self.status = .fallback
        }
    }

    // MARK: - Multi-Tier Scraping Pipeline

    private func scrapeWithFallbacks() async throws -> String {
        var collectedErrors: [String] = []

        // Try scraping from each endpoint in order
        for endpoint in Self.scrapeEndpoints {
            do {
                let id = try await scrapeFromEndpoint(endpoint)
                return id
            } catch {
                collectedErrors.append("\(endpoint): \(error.localizedDescription)")
            }
        }

        // Try verifying our built-in fallback IDs directly against API
        for candidate in Self.fallbackClientIDs {
            if await verifyClientID(candidate) {
                return candidate
            }
        }

        throw ScraperError.allEndpointsFailed(collectedErrors.joined(separator: " | "))
    }

    private func scrapeFromEndpoint(_ endpointURL: String) async throws -> String {
        let htmlString = try await fetchHTML(from: endpointURL)
        let scriptURLs = extractScriptURLs(from: htmlString)

        guard !scriptURLs.isEmpty else {
            throw ScraperError.noScriptsFound
        }

        // Fetch the last 4 JS bundle files in reverse order (assets with client_id are at the end)
        let bundlesToFetch = Array(scriptURLs.suffix(4).reversed())
        let clientID = try await fetchAndExtractFromBundles(bundlesToFetch)
        return clientID
    }

    /// Fetches HTML with Desktop User-Agent
    private func fetchHTML(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ScraperError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ScraperError.httpError(statusCode: statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ScraperError.invalidEncoding
        }

        return html
    }

    /// Extracts ALL `https://a-v2.sndcdn.com/assets/[^\s"'>]+\.js` URLs from HTML
    private func extractScriptURLs(from html: String) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()

        // Broad regex that captures any asset js URL regardless of attribute order
        let pattern = #"https://a-v2\.sndcdn\.com/assets/[^\s"'>]+\.js"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return urls
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            if let captureRange = Range(match.range(at: 0), in: html) {
                let url = String(html[captureRange])
                if !seen.contains(url) {
                    seen.insert(url)
                    urls.append(url)
                }
            }
        }

        return urls
    }

    /// Fetches multiple JS bundle files and extracts client_id
    private func fetchAndExtractFromBundles(_ urls: [String]) async throws -> String {
        try await withThrowingTaskGroup(of: String?.self) { group in
            for urlString in urls {
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    guard let url = URL(string: urlString) else { return nil }

                    var request = URLRequest(url: url)
                    request.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
                    request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
                    request.timeoutInterval = 12

                    do {
                        let (data, _) = try await self.session.data(for: request)
                        guard let jsContent = String(data: data, encoding: .utf8) else { return nil }
                        return Self.extractClientID(from: jsContent)
                    } catch {
                        return nil
                    }
                }
            }

            for try await result in group {
                if let id = result {
                    group.cancelAll()
                    return id
                }
            }

            throw ScraperError.clientIDNotFound
        }
    }

    /// Multi-pattern regex for client_id
    static func extractClientID(from jsContent: String) -> String? {
        let patterns = [
            #"client_id\s*:\s*"([a-zA-Z0-9]{32})"#,
            #"client_id\s*=\s*"([a-zA-Z0-9]{32})"#,
            #""client_id"\s*:\s*"([a-zA-Z0-9]{32})"#,
            #"client_id\s*[:=]\s*'([a-zA-Z0-9]{32})'"#,
            #""clientId"\s*:\s*"([a-zA-Z0-9]{32})"#,
            #"\bclient_id=([a-zA-Z0-9]{32})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }
            let range = NSRange(jsContent.startIndex..<jsContent.endIndex, in: jsContent)
            if let match = regex.firstMatch(in: jsContent, options: [], range: range),
               let captureRange = Range(match.range(at: 1), in: jsContent) {
                let candidate = String(jsContent[captureRange])
                if candidate.count == Self.clientIDLength {
                    return candidate
                }
            }
        }

        return nil
    }

    /// Verifies if a client_id works by calling search API
    private func verifyClientID(_ id: String) async -> Bool {
        guard let url = URL(string: "https://api-v2.soundcloud.com/search/tracks?q=test&client_id=\(id)&limit=1") else {
            return false
        }
        var request = URLRequest(url: url)
        request.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - Cache Helpers

    private static func loadCachedClientID() -> String? {
        let id = UserDefaults.standard.string(forKey: cacheKey)
        guard let id = id, id.count == clientIDLength else { return nil }
        return id
    }

    private static func loadManualClientID() -> String? {
        let id = UserDefaults.standard.string(forKey: manualOverrideKey)
        guard let id = id, id.count == clientIDLength else { return nil }
        return id
    }

    private static func isCacheExpired() -> Bool {
        let timestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard timestamp > 0 else { return true }
        let elapsed = Date().timeIntervalSince1970 - timestamp
        return elapsed > maxCacheAge
    }

    private static func cacheClientID(_ id: String) {
        UserDefaults.standard.set(id, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }
}

// MARK: - Errors

enum ScraperError: LocalizedError {
    case noScriptsFound
    case clientIDNotFound
    case invalidURL(String)
    case httpError(statusCode: Int)
    case invalidEncoding
    case deallocated
    case allEndpointsFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScriptsFound:
            return "Không tìm thấy JavaScript bundle nào của SoundCloud."
        case .clientIDNotFound:
            return "Không trích xuất được client_id từ các file JavaScript."
        case .invalidURL(let url):
            return "URL không hợp lệ: \(url)"
        case .httpError(let code):
            return "Lỗi máy chủ HTTP \(code) khi tải trang SoundCloud."
        case .invalidEncoding:
            return "Không thể giải mã phản hồi UTF-8."
        case .deallocated:
            return "ClientIDScraper bị giải phóng bộ nhớ."
        case .allEndpointsFailed(let msg):
            return "Tất cả các nguồn lấy client_id đều thất bại: \(msg)"
        }
    }
}
