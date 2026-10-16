import SwiftUI
import UIKit
import CarCore

/// 卡密体验网关：白名单外的手机号需输入站主提供的卡密（CH-XXXX-XXXX）
/// 兑换当天体验权限后才能进入，逻辑与网页版一致。
struct CardGateView: View {
    @EnvironmentObject private var appState: AppState

    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var showContactSheet = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                Image(systemName: "ticket.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("体验版 · 需要卡密")
                        .font(.title2.bold())
                    Text("本账号尚未获得体验授权。请输入站主提供的卡密，开启当天体验权限。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let phone = appState.credentials?.maskedPhone {
                    Text("当前账号：\(phone)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("卡密（CH-XXXX-XXXX）", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(.body, design: .monospaced))
                        .focused($codeFocused)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        verify()
                    } label: {
                        ZStack {
                            if isVerifying {
                                ProgressView().tint(.white)
                            } else {
                                Text("验证并进入体验")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)

                    Button {
                        showContactSheet = true
                    } label: {
                        Label("没有卡密？联系站主获取", systemImage: "person.crop.circle")
                            .font(.subheadline)
                    }

                    Button {
                        appState.logout()
                    } label: {
                        Text("返回重新登录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .padding(24)
            .background(Color(.systemBackground))
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "qrcode")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("卡密需向站主购买或索取")
                    .font(.headline)
                VStack(spacing: 8) {
                    Text("站主 QQ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(APIConfig.ownerContactQQ)
                        .font(.system(.title2, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    UIPasteboard.general.string = APIConfig.ownerContactQQ
                } label: {
                    Label("复制 QQ 号", systemImage: "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer()
            }
            .padding(24)
            .navigationTitle("联系站主")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
