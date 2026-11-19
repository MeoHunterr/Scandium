// ClientIDScraper.swift — Dynamic client_id extraction with multi-tier scraping
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation

final class ClientIDScraper: ObservableObject {

    // MARK: - Published State

    public enum ScraperStatus {
        case ready
        case manual
        case cached
        case syncing
        case online
        case fallbackError
        case noClientID
    }

    @Published private(set) var clientID: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var status: ScraperStatus = .ready

    var statusDescription: String {
        let isEn = AppSettings.shared.language == .english
        switch status {
        case .ready:        return isEn ? "Ready" : "Sẵn sàng"
        case .manual:       return isEn ? "Manual" : "Thủ công"
        case .cached:       return isEn ? "Cached" : "Đã lưu đệm"
        case .syncing:      return isEn ? "Syncing..." : "Đang làm mới..."
        case .online:       return isEn ? "Online" : "Trực tuyến"
        case .fallbackError: return isEn ? "Fallback (Error)" : "Dự phòng (Lỗi)"
        case .noClientID:   return isEn ? "No Client ID" : "Chưa có Client ID"
        }
    }

    var currentClientID: String? {
        clientID
    }

    // MARK: - Constants

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

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    private static let acceptLanguage = "en-US,en;q=0.9"

    // MARK: - Private State

    private let session: URLSession
    private let taskLock = NSLock()
    private var refreshTask: Task<String, Error>?

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
        // Priority: Manual override -> Cached ID -> nil (no fallback IDs)
        if let manual = Self.loadManualClientID() {
            self.clientID = manual
            self.status = .manual
        } else if let cached = Self.loadCachedClientID(), !Self.isCacheExpired() {
            self.clientID = cached
            self.status = .cached
        } else {
            // No manual override and no valid cache — start with nil, will scrape on demand
            self.clientID = nil
            self.status = .ready
        }
    }

    // MARK: - Public API

    /// Returns a valid client_id using manual/cache first. If nil, triggers a fresh scrape.
    @discardableResult
    func getClientID() async throws -> String {
        if let manual = Self.loadManualClientID() {
            await MainActor.run {
                self.clientID = manual
                self.status = .manual
            }
            return manual
        }

        if let cached = Self.loadCachedClientID(), !Self.isCacheExpired() {
            await MainActor.run {
                self.clientID = cached
                self.status = .cached
            }
            return cached
        }

        // No manual override, no valid cache — must scrape
        return try await refreshClientID()
    }

    private func getOrStartRefreshTask() -> Task<String, Error> {
        taskLock.lock()
        defer { taskLock.unlock() }
        if let existing = refreshTask {
            return existing
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
                // Scraping failed completely — no hardcoded fallbacks, surface the error
                await MainActor.run {
                    self.clientID = nil
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                    self.status = .noClientID
                }
                throw error
            }
        }
        self.refreshTask = task
        return task
    }

    private func clearRefreshTask() {
        taskLock.lock()
        defer { taskLock.unlock() }
        self.refreshTask = nil
    }

    /// Forces a fresh scrape across all endpoints. Throws on failure (no hardcoded fallback IDs).
    @discardableResult
    func refreshClientID() async throws -> String {
        if let manual = Self.loadManualClientID() {
            await MainActor.run {
                self.clientID = manual
                self.status = .manual
            }
            return manual
        }

        let task = getOrStartRefreshTask()
        defer { clearRefreshTask() }

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
                // No cache — no hardcoded fallback
                self.clientID = nil
                self.status = .noClientID
            }
        }
    }

    var manualClientID: String? {
        Self.loadManualClientID()
    }

    var isManualOverride: Bool {
        Self.loadManualClientID() != nil
    }

    /// Clears cached client_id, forcing re-scrape on next request.
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheTimestampKey)
        if !isManualOverride {
            self.clientID = nil
            self.status = .ready
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

        throw ScraperError.allEndpointsFailed(collectedErrors.joined(separator: " | "))
    }

    private func scrapeFromEndpoint(_ endpointURL: String) async throws -> String {
        let htmlString = try await fetchHTML(from: endpointURL)
        let scriptURLs = extractScriptURLs(from: htmlString)

        guard !scriptURLs.isEmpty else {
            throw ScraperError.noScriptsFound
        }

        // Fetch the last 8 JS bundle files in reverse order (broader scanning)
        let bundlesToFetch = Array(scriptURLs.suffix(8).reversed())
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
        let isEn = AppSettings.shared.language == .english
        switch self {
        case .noScriptsFound:
            return isEn ? "No JavaScript bundles found on SoundCloud." : "Không tìm thấy JavaScript bundle nào của SoundCloud."
        case .clientIDNotFound:
            return isEn ? "Could not extract client_id from JavaScript assets." : "Không trích xuất được client_id từ các file JavaScript."
        case .invalidURL(let url):
            return isEn ? "Invalid URL: \(url)" : "URL không hợp lệ: \(url)"
        case .httpError(let code):
            return isEn ? "HTTP \(code) error while loading SoundCloud page." : "Lỗi máy chủ HTTP \(code) khi tải trang SoundCloud."
        case .invalidEncoding:
            return isEn ? "Unable to decode UTF-8 response." : "Không thể giải mã phản hồi UTF-8."
        case .deallocated:
            return isEn ? "ClientIDScraper was deallocated." : "ClientIDScraper bị giải phóng bộ nhớ."
        case .allEndpointsFailed(let msg):
            return isEn ? "All client_id sources failed: \(msg)" : "Tất cả các nguồn lấy client_id đều thất bại: \(msg)"
        }
    }
}
