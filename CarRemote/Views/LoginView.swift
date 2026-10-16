import SwiftUI
import CarCore

/// 登录 / 短信注册（样式照搬网页版首页：暗色背景 + 毛玻璃卡片 + 珊瑚渐变徽标 + 橙红渐变按钮）
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        ZStack {
            // 网页版 body：深底 + 三处径向光晕
            WebLoginBackground()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // 毛玻璃主卡片（网页版 .glass-card：rounded-3xl 大卡）
                    VStack(spacing: 0) {
                        // 头部：渐变徽标 + 标题（网页版 logo-badge）
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(WebLoginTheme.logoGradient)
                                    .frame(width: 52, height: 52)
                                    .shadow(color: WebLoginTheme.cyan.opacity(0.35), radius: 24, x: 0, y: 8)
                                Image(systemName: "car.side.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text("远程控车系统")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(WebLoginTheme.txt)
                            Text("车况 · 控车 · Siri · 圈子")
                                .font(.system(size: 12))
                                .foregroundStyle(WebLoginTheme.muted)
                        }
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                        // 登录/注册切换（网页版 tab-bar）
                        modePicker
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)

                        // 表单
                        VStack(spacing: 14) {
                            phoneField
                            switch viewModel.mode {
                            case .password:
                                pinField(title: "控车码", placeholder: "输入你在网站设置的控车码", image: "key.fill")
                            case .sms:
                                smsCodeField
                                pinField(title: "设置控车码", placeholder: "4 位以上，用于登录与控车", image: "lock.fill")
                            }
                        }
                        .padding(.horizontal, 24)

                        // 主按钮（网页版 .btn-primary：橙→红→深红渐变）
                        submitButton
                            .padding(.horizontal, 24)
                            .padding(.top, 20)

                        // 提示
                        VStack(spacing: 10) {
                            if let errorMessage = viewModel.errorMessage {
                                loginBanner(errorMessage, isError: true)
                            }
                            if let infoMessage = viewModel.infoMessage {
                                loginBanner(infoMessage, isError: false)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                        // 系统公告（网页版 .notice）
                        notice
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                            .padding(.bottom, 28)
                    }
                    .background(
                        ZStack {
                            // 毛玻璃（网页版 backdrop-filter: blur(18px)）
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.10),
                                            Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(WebLoginTheme.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 60, x: 0, y: 24)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(viewModel.isSubmitting)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - 登录/注册切换（网页版 tab-bar / tab-btn）

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(LoginViewModel.Mode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.mode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.mode == mode ? WebLoginTheme.cyan : WebLoginTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            viewModel.mode == mode
                                ? WebLoginTheme.card2
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(WebLoginTheme.bg0.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(WebLoginTheme.border, lineWidth: 1)
        )
    }

    // MARK: - 输入框（网页版 .input-wrap：深色底 + 圆角 14 + 聚焦光晕）

    private var phoneField: some View {
        webInput {
            Image(systemName: "phone.fill")
                .foregroundStyle(WebLoginTheme.faint)
                .frame(width: 18)
            TextField("手机号", text: $viewModel.phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .autocapitalization(.none)
                .foregroundStyle(WebLoginTheme.txt)
                .tint(WebLoginTheme.cyan)
        }
    }

    private func pinField(title: String, placeholder: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WebLoginTheme.muted)
            webInput {
                Image(systemName: image)
                    .foregroundStyle(WebLoginTheme.faint)
                    .frame(width: 18)
                SecureField(placeholder, text: $viewModel.pin)
                    .textContentType(.password)
                    .foregroundStyle(WebLoginTheme.txt)
                    .tint(WebLoginTheme.cyan)
            }
        }
    }

    private var smsCodeField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("短信验证码")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WebLoginTheme.muted)
            HStack(spacing: 10) {
                webInput {
                    Image(systemName: "message.fill")
                        .foregroundStyle(WebLoginTheme.faint)
                        .frame(width: 18)
                    TextField("6 位验证码", text: $viewModel.smsCode)
                        .keyboardType(.numberPad)
                        .foregroundStyle(WebLoginTheme.txt)
                        .tint(WebLoginTheme.cyan)
                }
                // 网页版 .code-btn
                Button {
                    viewModel.sendCode()
                } label: {
                    Text(viewModel.cooldown > 0 ? "\(viewModel.cooldown)s" : "获取验证码")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WebLoginTheme.cyan)
                        .frame(width: 92, height: 48)
                        .background(WebLoginTheme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    viewModel.cooldown > 0 || viewModel.phone.count != 11
                                        ? WebLoginTheme.border
                                        : WebLoginTheme.cyan.opacity(0.55),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.cooldown > 0 || viewModel.phone.count != 11)
            }
        }
    }

    /// 网页版 .input-wrap：深色底 + 1.5px 边框 + 圆角 14
    private func webInput<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(WebLoginTheme.bg0.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WebLoginTheme.border, lineWidth: 1.5)
            )
    }

    // MARK: - 主按钮（网页版 .btn-primary）

    private var submitButton: some View {
        Button {
            viewModel.submit(appState: appState)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WebLoginTheme.primaryGradient)
                    .shadow(color: Color(hex: 0xdc2626).opacity(0.4), radius: 22, x: 0, y: 8)
                    // 内高光（网页版 inset 0 1px 0 rgba(255,255,255,.2)）
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(viewModel.mode == .password ? "登录" : "注册并登录")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .opacity(viewModel.canSubmit || viewModel.isSubmitting ? 1 : 0.55)
        .disabled(!viewModel.canSubmit)
    }

    // MARK: - 系统公告（网页版 .notice）

    private var notice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WebLoginTheme.amber)
                Text("系统公告")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebLoginTheme.txt)
            }
            VStack(alignment: .leading, spacing: 5) {
                noticeItem("本 App 为原生客户端，车控数据与网页版实时同步")
                noticeItem("支持 Siri 语音控车，指令可在设置中管理")
                noticeItem("请勿将账号借予他人，注意保护个人控车码")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebLoginTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WebLoginTheme.border, lineWidth: 1)
        )
    }

    private func noticeItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(WebLoginTheme.cyan)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(WebLoginTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 提示条

    private func loginBanner(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isError ? WebLoginTheme.blue : WebLoginTheme.green)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? WebLoginTheme.blue : WebLoginTheme.green).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
