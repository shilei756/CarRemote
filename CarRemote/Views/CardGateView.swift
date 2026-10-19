import SwiftUI
import UIKit
import CarCore

/// 卡密体验网关：白名单外的手机号需输入站主提供的卡密（CH-XXXX-XXXX）
/// 兑换当天体验权限后才能进入，逻辑与网页版一致。
/// 样式照搬网页版卡密弹窗：暗色背景 + 毛玻璃 + 珊瑚渐变徽标 + 橙红渐变按钮。
struct CardGateView: View {
    @EnvironmentObject private var appState: AppState

    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var showContactSheet = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavStack {
            ZStack {
                WebLoginBackground()
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 24)

                        // 渐变徽标（网页版弹窗头部图标）
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(WebLoginTheme.logoGradient)
                                .frame(width: 52, height: 52)
                                .shadow(color: WebLoginTheme.cyan.opacity(0.35), radius: 24, x: 0, y: 8)
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(spacing: 8) {
                            Text("体验版 · 需要卡密")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(WebLoginTheme.txt)
                            Text("本账号尚未获得体验授权。请输入站主提供的卡密，开启当天体验权限。")
                                .font(.system(size: 13))
                                .foregroundStyle(WebLoginTheme.muted)
                                .multilineTextAlignment(.center)
                        }

                        if let phone = appState.credentials?.maskedPhone {
                            Text("当前账号：\(phone)")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(WebLoginTheme.faint)
                        }

                        VStack(spacing: 14) {
                            // 网页版 .input-wrap 输入框
                            HStack(spacing: 10) {
                                Image(systemName: "ticket.fill")
                                    .foregroundStyle(WebLoginTheme.faint)
                                    .frame(width: 18)
                                TextField("CH-XXXX-XXXX", text: $code)
                                    .textInputAutocapitalization(.characters)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.center)
                                    .font(.system(.body, design: .monospaced))
                                    .focused($codeFocused)
                                    .foregroundStyle(WebLoginTheme.txt)
                                    .tint(WebLoginTheme.cyan)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(WebLoginTheme.bg0.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(WebLoginTheme.border, lineWidth: 1.5)
                            )

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(WebLoginTheme.blue)
                                    .multilineTextAlignment(.center)
                            }

                            // 网页版 .btn-primary 渐变按钮
                            Button {
                                verify()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(WebLoginTheme.primaryGradient)
                                        .shadow(color: Color(hex: 0xdc2626).opacity(0.4), radius: 22, x: 0, y: 8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                        )
                                    if isVerifying {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("验证并进入体验")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)

                            Button {
                                showContactSheet = true
                            } label: {
                                Label("没有卡密？联系站主获取", systemImage: "person.crop.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WebLoginTheme.cyan)
                            }
                            .buttonStyle(.plain)

                            Button {
                                appState.logout()
                            } label: {
                                Text("返回重新登录")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WebLoginTheme.faint)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 8)

                        Spacer(minLength: 24)
                    }
                    .padding(24)
                }
            }
            .onAppear { codeFocused = true }
            .sheet(isPresented: $showContactSheet) {
                ContactOwnerSheet()
            }
        }
    }

    private func verify() {
        guard let credentials = appState.credentials else { return }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isVerifying = true
        errorMessage = nil
        Task {
            defer { isVerifying = false }
            do {
                let ok = try await CardService.verify(phone: credentials.phone, code: trimmed)
                if ok {
                    appState.cardVerified()
                } else {
                    errorMessage = "卡密无效，请检查后重试"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 联系站主
struct ContactOwnerSheet: View {
    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 20)
                        ZStack {
                            Circle()
                                .fill(WebTheme.blue.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(WebTheme.blue)
                        }
                        Text("联系站主")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                        Text("卡密由站主发放。可通过网页版公告中的联系方式获取。")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.muted)
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 20)
                    }
                    .padding(24)
                }
            }
            .inlineTitle("联系站主")
        }
        .compatMediumDetent()
    }
}
