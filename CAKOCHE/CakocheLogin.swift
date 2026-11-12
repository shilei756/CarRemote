import SwiftUI
import UIKit
import CarCore

/// CAKOCHE 登录页：黑底点阵，账号 / 控车码全部由站主网站校验。
/// 明确写出「非白名单禁止登录」——校验失败时 AppState 会清凭据并回本页横幅提示。
struct CakocheLoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phone = ""
    @State private var pin = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            Mono.night.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 74)

                    DotMatrixText(text: "CAKOCHE", size: 30, color: Mono.nightInk)
                    DotCnText(text: "长安 · 远程控车", size: 9, color: Mono.nightDim)
                        .padding(.top, 10)
                    Hairline(color: Mono.nightHair).padding(.top, 28)

                    VStack(alignment: .leading, spacing: 24) {
                        field(title: "手机号", placeholder: "11 位手机号",
                              text: $phone, keyboard: .numberPad)
                        field(title: "控车码", placeholder: "控车码",
                              text: $pin, secure: true)
                    }
                    .padding(.top, 32)

                    if let message = appState.errorMessage, !message.isEmpty {
                        HStack(alignment: .top, spacing: 9) {
                            Rectangle().fill(Mono.red).frame(width: 2)
                            DotCnText(text: message, size: 9, color: Mono.nightInk,
                                      wrapWidth: 290, wrapAlignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 22)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 10) {
                            DotCnText(text: busy ? "校 验 中" : "登 录", size: 13, color: Mono.night)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(Mono.night)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .background(Mono.nightInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || phone.count != 11 || pin.isEmpty)
                    .opacity(busy || phone.count != 11 || pin.isEmpty ? 0.45 : 1)
                    .padding(.top, 34)
                    .accessibilityLabel("登录")

                    HStack(spacing: 7) {
                        Circle().fill(Mono.red).frame(width: 5, height: 5)
                        DotCnText(text: "仅限网站白名单用户 · 非授权账号禁止登录",
                                  size: 8, color: Mono.nightDim)
                    }
                    .padding(.top, 20)

                    DotCnText(text: "账号、控车码与车辆授权均由站主网站统一校验，本 App 不提供注册入口。",
                              size: 8, color: Mono.nightDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 9)

                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 26)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func field(title: String, placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            DotCnText(text: title, size: 8, color: Mono.nightDim)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboard)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Mono.nightInk)
            .tint(Mono.red)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Hairline(color: Mono.nightHair)
        }
        .accessibilityLabel(title == "手机号" ? "手机号" : "控车码")
    }

    @MainActor
    private func submit() async {
        busy = true
        defer { busy = false }
        appState.errorMessage = nil
        do {
            let credentials = try await AuthService.login(phone: phone, pin: pin)
            // 交给 AppState 走网站白名单严格校验；不在白名单会被清凭据并回本页
            appState.loginCompleted(credentials)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
