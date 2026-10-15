// SoundCloudWebLoginView.swift — OAuth helper without embedded WKWebView wrapper
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SoundCloudWebLoginView: View {
    @Binding var isPresented: Bool
    var onTokenCaptured: (String) -> Void
    var onProfileSubmitted: (String) -> Void
    @Environment(\.openURL) private var openURL
    @ObservedObject private var settings = AppSettings.shared
    @State private var tokenInput: String = ""
    @State private var profileInput: String = ""
    @State private var showOAuthGuide: Bool = false

    init(
        isPresented: Binding<Bool>,
        onTokenCaptured: @escaping (String) -> Void,
        onProfileSubmitted: @escaping (String) -> Void
    ) {
        self._isPresented = isPresented
        self.onTokenCaptured = onTokenCaptured
        self.onProfileSubmitted = onProfileSubmitted
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(settings.loc("Đồng bộ tài khoản SoundCloud", "SoundCloud Account Sync"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)

                        Text(settings.loc(
                            "Cách thuận tiện nhất: dán đường dẫn trang cá nhân công khai để đồng bộ thư viện.",
                            "Most convenient: paste public profile link to synchronize library."
                        ))
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.subtext)

                        TextField(settings.loc("soundcloud.com/tên_người_dùng", "soundcloud.com/username"), text: $profileInput)
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.textPrimary)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button(action: {
                            let profile = profileInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !profile.isEmpty else { return }
                            onProfileSubmitted(profile)
                            isPresented = false
                        }) {
                            Text(settings.loc("Đồng bộ qua link hồ sơ", "Sync via Profile Link"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(ScandiumTheme.spotifyGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        HairlineDivider()

                        Text(settings.loc(
                            "Nâng cao: trích xuất Service Token (OAuth) từ trình duyệt web để đồng bộ dữ liệu riêng tư.",
                            "Advanced: extract Service Token (OAuth) from web browser to synchronize private data."
                        ))
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)

                        Button(action: { showOAuthGuide = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                Text(settings.loc("Xem hướng dẫn lấy OAuth Token (PC & iOS)", "Guide to obtain OAuth Token (PC & iOS)"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(ScandiumTheme.subtext)
                        }

                        Button(action: {
                            if let url = URL(string: "https://soundcloud.com/signin") {
                                openURL(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "safari")
                                Text(settings.loc("Mở trang xác thực soundcloud.com/signin", "Open signin page soundcloud.com/signin"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(ScandiumTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        TextField(settings.loc("Dán OAuth token...", "Paste OAuth token..."), text: $tokenInput)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(ScandiumTheme.textPrimary)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button(action: {
                            let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !token.isEmpty else { return }
                            onTokenCaptured(token)
                            isPresented = false
                        }) {
                            Text(settings.loc("Lưu Token", "Save Token"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(ScandiumTheme.spotifyGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        isPresented = false
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showOAuthGuide) {
            OAuthTokenGuideSheet()
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}

struct OAuthTokenGuideSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedGuideTab: Int = 0 // 0: PC/Mac, 1: iPhone/iOS

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        Text(settings.loc("Hướng dẫn lấy Token dịch vụ (OAuth)", "Service Token (OAuth) Guide"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)

                        // Segmented control (PC vs iOS)
                        HStack(spacing: 8) {
                            Button(action: { selectedGuideTab = 0 }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "laptopcomputer")
                                    Text(settings.loc("Máy tính (PC/Mac)", "Computer (PC/Mac)"))
                                }
                                .font(.system(size: 13, weight: selectedGuideTab == 0 ? .semibold : .regular))
                                .foregroundColor(selectedGuideTab == 0 ? (ScandiumTheme.isDark ? .black : .white) : ScandiumTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedGuideTab == 0 ? ScandiumTheme.textPrimary : ScandiumTheme.surfaceElevated)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: { selectedGuideTab = 1 }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "iphone")
                                    Text(settings.loc("Trên iPhone", "On iPhone"))
                                }
                                .font(.system(size: 13, weight: selectedGuideTab == 1 ? .semibold : .regular))
                                .foregroundColor(selectedGuideTab == 1 ? (ScandiumTheme.isDark ? .black : .white) : ScandiumTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedGuideTab == 1 ? ScandiumTheme.textPrimary : ScandiumTheme.surfaceElevated)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(4)
                        .background(ScandiumTheme.surfaceDark)
                        .clipShape(Capsule())

                        if selectedGuideTab == 0 {
                            pcGuideContent
                        } else {
                            iosGuideContent
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.loc("Đã hiểu", "Got it")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                    .font(.body.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    // MARK: - PC / Mac Guide (Recommended)

    @ViewBuilder
    private var pcGuideContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Note banner
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 14))
                Text(settings.loc(
                    "Khuyên dùng: Thao tác trên trình duyệt máy tính rất nhanh và chuẩn xác, không cần cài thêm công cụ bên ngoài.",
                    "Recommended: Extracting on desktop browser is quick and reliable, requires no third-party tools."
                ))
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(nil)
            }
            .padding(12)
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(settings.loc("Cách 1: Lấy qua Cookie trình duyệt (Khuyên dùng)", "Method 1: Extract via Browser Cookies (Recommended)"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: settings.loc("Mở trình duyệt trên máy tính & truy cập soundcloud.com", "Open desktop browser & visit soundcloud.com"),
                detail: settings.loc("Dùng Chrome, Edge, Safari hoặc Firefox truy cập soundcloud.com và đăng nhập tài khoản của bạn.", "Use Chrome, Edge, Safari or Firefox to visit soundcloud.com and sign in.")
            )

            oauthStep(
                number: "2",
                title: settings.loc("Nhấn F12 mở Công cụ nhà phát triển (DevTools)", "Press F12 to open Developer Tools (DevTools)"),
                detail: settings.loc("Bấm phím F12 (hoặc chuột phải chọn 'Kiểm tra' / 'Inspect', trên Mac nhấn Cmd + Option + I).", "Press F12 (or right-click 'Inspect', on Mac press Cmd + Option + I).")
            )

            oauthStep(
                number: "3",
                title: settings.loc("Vào tab Application (hoặc Storage)", "Navigate to Application (or Storage) tab"),
                detail: settings.loc("Trên thanh công cụ DevTools, chọn tab 'Application' (Chrome/Edge) hoặc 'Storage' (Firefox/Safari).", "In DevTools bar, select 'Application' (Chrome/Edge) or 'Storage' (Firefox/Safari).")
            )

            oauthStep(
                number: "4",
                title: settings.loc("Chọn Cookies -> https://soundcloud.com", "Select Cookies -> https://soundcloud.com"),
                detail: settings.loc("Ở menu bên trái, mở rộng mục 'Cookies' rồi nhấp chọn 'https://soundcloud.com'.", "In the left panel, expand 'Cookies' and select 'https://soundcloud.com'.")
            )

            oauthStep(
                number: "5",
                title: settings.loc("Sao chép giá trị của oauth_token", "Copy value of oauth_token"),
                detail: settings.loc("Trong bảng bên phải, tìm dòng có Name là 'oauth_token'. Nhấp đúp vào ô Value để sao chép chuỗi mã.", "In the table, locate the row named 'oauth_token'. Double-click the Value field to copy the token.")
            )

            oauthStep(
                number: "6",
                title: settings.loc("Dán mã vào Scandium", "Paste token into Scandium"),
                detail: settings.loc("Gửi chuỗi vừa sao chép sang iPhone và dán vào ô 'Dán OAuth token' trong Scandium.", "Send the copied string to your iPhone and paste into 'Paste OAuth token' in Scandium.")
            )

            HairlineDivider()

            Text(settings.loc("Cách 2: Lấy qua Network Request (Dự phòng)", "Method 2: Extract via Network Request (Fallback)"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: settings.loc("Mở DevTools -> tab Network", "Open DevTools -> Network tab"),
                detail: settings.loc("Nhấn F12, chọn tab Network và gõ 'me' vào ô lọc.", "Press F12, select Network tab and filter for 'me'.")
            )

            oauthStep(
                number: "2",
                title: settings.loc("Bấm phát bài hát bất kỳ", "Play any track"),
                detail: settings.loc("Bấm Play bài hát trên web, các request gọi đến dịch vụ mạng sẽ xuất hiện.", "Play a track on web; network requests will appear in DevTools.")
            )

            oauthStep(
                number: "3",
                title: settings.loc("Mở Headers và sao chép OAuth token", "Open Headers and copy OAuth token"),
                detail: settings.loc("Chọn request 'me' -> tab Headers -> cuộn xuống Request Headers -> sao chép phần mã sau chữ 'OAuth ' trong Authorization.", "Select 'me' request -> Headers tab -> scroll to Request Headers -> copy string after 'OAuth ' in Authorization header.")
            )
        }
    }

    // MARK: - iOS Guide

    @ViewBuilder
    private var iosGuideContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(settings.loc("Cách lấy trực tiếp trên iPhone:", "Direct extraction on iPhone:"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: settings.loc("Cài ứng dụng ghi log mạng HTTPS", "Install network capture utility"),
                detail: settings.loc("Cài ứng dụng hỗ trợ phân tích gói tin mạng như HTTP Catcher, Surge, Thor hoặc Shadowrocket trên App Store.", "Install an HTTPS network capture app such as HTTP Catcher, Surge, Thor or Shadowrocket from the App Store.")
            )

            oauthStep(
                number: "2",
                title: settings.loc("Bật ghi log và truy cập soundcloud.com", "Enable logging and visit soundcloud.com"),
                detail: settings.loc("Bật chế độ ghi log của app bắt mạng. Mở Safari, truy cập soundcloud.com và đăng nhập.", "Enable request capture. Open Safari, visit soundcloud.com and sign in.")
            )

            oauthStep(
                number: "3",
                title: settings.loc("Phát một bài hát bất kỳ", "Play any track"),
                detail: settings.loc("Trong danh sách log, tìm request gửi tới dịch vụ mạng có đuôi /me hoặc /stream rồi xem Header.", "In captured log, find requests ending with /me or /stream and inspect Headers.")
            )

            oauthStep(
                number: "4",
                title: settings.loc("Sao chép OAuth token", "Copy OAuth token"),
                detail: settings.loc("Sao chép giá trị trong header Authorization (chỉ lấy phần chuỗi sau chữ OAuth).", "Copy the value in the Authorization header (only the string after 'OAuth ').")
            )

            oauthStep(
                number: "5",
                title: settings.loc("Dán token vào Scandium", "Paste token into Scandium"),
                detail: settings.loc("Quay lại Scandium, dán mã vào ô và bấm 'Lưu Token'.", "Return to Scandium, paste into the field and tap 'Save Token'.")
            )
        }
    }

    private func oauthStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(ScandiumTheme.surfaceElevated)
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ScandiumTheme.spotifyGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScandiumTheme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
