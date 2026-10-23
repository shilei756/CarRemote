import SwiftUI
import CarCore

/// 登录 / 短信注册
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    modePicker
                    form
                    submitButton
                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                    // 上次会话被踢出的原因（体验到期 / 授权撤销），登录后自动清除
                    if let sessionMessage = appState.errorMessage {
                        errorBanner(sessionMessage)
                    }
                    if let infoMessage = viewModel.infoMessage {
                        infoBanner(infoMessage)
                    }
                    Spacer(minLength: 24)
                    footer
                }
                .padding(24)
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
            .disabled(viewModel.isSubmitting)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("长安控车")
                .font(.largeTitle.bold())
            Text("原生 App · 车况 / 控车 / 小组件 / Siri")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var modePicker: some View {
        Picker("登录方式", selection: $viewModel.mode) {
            ForEach(LoginViewModel.Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 表单

    @ViewBuilder
    private var form: some View {
        VStack(spacing: 14) {
            phoneField
            switch viewModel.mode {
            case .password:
                pinField(title: "控车码", placeholder: "输入你在网站设置的控车码")
            case .sms:
                smsCodeField
                pinField(title: "设置控车码", placeholder: "4 位以上，用于登录与控车")
            }
        }
    }

    private var phoneField: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone")
                .foregroundStyle(.secondary)
            TextField("手机号", text: $viewModel.phone)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .autocapitalization(.none)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pinField(title: String, placeholder: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: $viewModel.pin)
                .textContentType(.password)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var smsCodeField: some View {
        HStack(spacing: 12) {
            Image(systemName: "message")
                .foregroundStyle(.secondary)
            TextField("短信验证码", text: $viewModel.smsCode)
                .keyboardType(.numberPad)
            Button {
                viewModel.sendCode()
            } label: {
                Text(viewModel.cooldown > 0 ? "\(viewModel.cooldown)s" : "获取验证码")
                    .font(.subheadline.bold())
                    .frame(width: 88)
            }
            .disabled(viewModel.cooldown > 0 || viewModel.phone.count != 11)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            appState.errorMessage = nil
            viewModel.submit(appState: appState)
        } label: {
            ZStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(viewModel.mode == .password ? "登录" : "注册并登录")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(!viewModel.canSubmit)
    }

    // MARK: - 提示

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.red)
        .padding()
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func infoBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.green)
        .padding()
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("使用网站版账号直接登录；新用户可通过短信注册。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("登录即代表同意站主使用条款与免责声明。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}
