// SoundCloudWebLoginView.swift — OAuth helper without embedded WKWebView wrapper
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SoundCloudWebLoginView: View {
    @Binding var isPresented: Bool
    var onTokenCaptured: (String) -> Void
    var onProfileSubmitted: (String) -> Void
    @Environment(\.openURL) private var openURL
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
                        Text("Đăng nhập SoundCloud")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text("Cách dễ nhất: chỉ cần dán link profile SoundCloud của bạn để đồng bộ thư viện công khai.")
                            .font(.system(size: 14))
                            .foregroundColor(ScandiumTheme.subtext)

                        TextField("soundcloud.com/username", text: $profileInput)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
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
                            Text("Đăng nhập bằng link profile")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(ScandiumTheme.spotifyGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        HairlineDivider()

                        Text("Nâng cao: đăng nhập web rồi dán oauth token (nếu bạn muốn dữ liệu riêng tư).")
                            .font(.system(size: 13))
                            .foregroundColor(ScandiumTheme.subtext)

                        Button(action: { showOAuthGuide = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle")
                                Text("Hướng dẫn lấy OAuth token (iOS + PC)")
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
                                Text("Mở soundcloud.com/signin")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        TextField("Dán OAuth token...", text: $tokenInput)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
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
                            Text("Lưu token")
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
                    Button("Đóng") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showOAuthGuide) {
            OAuthTokenGuideSheet()
        }
        .preferredColorScheme(.dark)
    }
}

struct OAuthTokenGuideSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedGuideTab: Int = 0 // 0: PC/Mac, 1: iPhone/iOS

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        Text("Hướng dẫn lấy OAuth Token")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ScandiumTheme.textPrimary)

                        // Segmented control (PC vs iOS)
                        HStack(spacing: 8) {
                            Button(action: { selectedGuideTab = 0 }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "laptopcomputer")
                                    Text("Máy tính (PC/Mac)")
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
                                    Text("Trên iPhone")
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
                    Button("Đã hiểu") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                    .font(.body.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(AppSettings.shared.themeMode.colorScheme)
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
                Text("Khuyên dùng: Lấy trên máy tính rất nhanh và chuẩn 100%, không cần cài thêm app bắt mạng.")
                    .font(.system(size: 13))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(nil)
            }
            .padding(12)
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Cách 1: Lấy qua Cookie trình duyệt (Rất dễ)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: "Mở trình duyệt trên PC & đăng nhập",
                detail: "Dùng Chrome, Edge, Cốc Cốc, Brave hoặc Firefox truy cập soundcloud.com và đăng nhập tài khoản của bạn."
            )

            oauthStep(
                number: "2",
                title: "Nhấn F12 mở Công cụ nhà phát triển (DevTools)",
                detail: "Bấm phím F12 (hoặc chuột phải chọn 'Kiểm tra' / 'Inspect', trên Mac nhấn Cmd + Option + I)."
            )

            oauthStep(
                number: "3",
                title: "Vào tab Application (hoặc Storage)",
                detail: "Trên thanh công cụ DevTools, chọn tab 'Application' (Chrome/Edge/Cốc Cốc) hoặc 'Storage' (Firefox)."
            )

            oauthStep(
                number: "4",
                title: "Chọn Cookies -> https://soundcloud.com",
                detail: "Ở menu bên trái, bấm mở rộng mục 'Cookies' rồi nhấp chọn 'https://soundcloud.com'."
            )

            oauthStep(
                number: "5",
                title: "Copy giá trị của oauth_token",
                detail: "Trong bảng bên phải, tìm dòng có Name là 'oauth_token'. Nhấp đúp vào ô Value để copy chuỗi mã (dạng: 2-293847-12345678-xxxxxx)."
            )

            oauthStep(
                number: "6",
                title: "Dán mã vào Scandium",
                detail: "Gửi chuỗi vừa copy sang iPhone (qua Zalo, Telegram, Ghi chú iCloud...) và dán vào ô 'Dán OAuth token' trong app."
            )

            HairlineDivider()

            Text("Cách 2: Lấy qua Network Request (Dự phòng)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: "Mở DevTools -> tab Network",
                detail: "Nhấn F12, chọn tab Network (Mạng) và gõ 'me' vào ô tìm kiếm/lọc."
            )

            oauthStep(
                number: "2",
                title: "Bấm phát 1 bài nhạc bất kỳ",
                detail: "Bấm Play bài hát bất kỳ trên web, các request gọi đến api-v2 sẽ xuất hiện."
            )

            oauthStep(
                number: "3",
                title: "Mở Headers và copy OAuth",
                detail: "Bấm vào request 'me' trong danh sách -> tab Headers bên phải -> cuộn xuống mục Request Headers -> copy phần mã sau chữ 'OAuth ' trong header Authorization."
            )
        }
    }

    // MARK: - iOS Guide

    @ViewBuilder
    private var iosGuideContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cách lấy trực tiếp trên iPhone:")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            oauthStep(
                number: "1",
                title: "Cài app bắt gói tin HTTPS",
                detail: "Bạn cần 1 app bắt request HTTPS như HTTP Catcher, Surge, Thor hoặc Shadowrocket trên App Store."
            )

            oauthStep(
                number: "2",
                title: "Mở bắt log và đăng nhập SoundCloud bằng Safari",
                detail: "Bật chế độ ghi log của app bắt mạng. Vào soundcloud.com/signin trên Safari và đăng nhập bình thường."
            )

            oauthStep(
                number: "3",
                title: "Phát 1 bài nhạc bất kỳ",
                detail: "Trong lịch sử log, tìm request gửi tới api-v2.soundcloud.com/me hoặc /stream rồi mở phần Header."
            )

            oauthStep(
                number: "4",
                title: "Copy OAuth token",
                detail: "Lấy giá trị trong header Authorization dạng: OAuth xxxxxxxxx... (chỉ copy phần chuỗi sau chữ OAuth)."
            )

            oauthStep(
                number: "5",
                title: "Dán token vào Scandium",
                detail: "Quay lại Scandium, dán token vào ô 'Dán OAuth token' và bấm 'Lưu token'."
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
