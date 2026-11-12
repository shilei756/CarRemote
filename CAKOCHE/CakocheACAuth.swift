import SwiftUI
import UIKit
import CarCore

/// 新版空调授权页（1.2.4）
///
/// CAKOCHE 空调恒定走网站「新版空调通道」（newAC / 长安开放平台），
/// 授权完全由站主网站统一判定，App 不自建授权体系。这里提供两条路径：
///  1. **直接调用网站授权**：站内 `/api/open/token`，同步网站已为该账号保存的凭证；
///  2. **走网站授权通道扫码开通**：`/api/ac/qrcode` + `/api/ac/status`，
///     用长安汽车 App 扫码确认，成功后把网站下发的 refresh_token 落盘。
///
/// 两条路径拿到的都是网站凭证，后续空调指令由 `ACService.executeOfficial` 下发。
struct CakocheACAuthSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var statusText = ACService.websiteAuthorizationText()
    @State private var busySync = false
    @State private var showQR = false
    @State private var qrImage: UIImage?
    @State private var qrURL: URL?
    @State private var qrId = ""
    @State private var deadline: Date?
    @State private var qrStatus = ""
    @State private var qrError: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            Mono.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: 顶部标题 + 关闭（Modal 必须可取消）
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            DotCnText(text: "新 版 空 调 授 权", size: 15, color: Mono.paperInk)
                            DotCnText(text: "空 调 通 道 · 网 站 统 一 授 权", size: 8, color: Mono.paperDim)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Mono.paperDim)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Mono.paperHair, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭授权页")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                    Hairline(color: Mono.paperHair)

                    // MARK: 说明
                    DotCnText(text: "空调指令统一走网站的新版空调通道。授权由站主网站校验，App 不另建账号或凭证体系。",
                              size: 9, color: Mono.paperDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)

                    // MARK: 当前授权状态
                    VStack(alignment: .leading, spacing: 8) {
                        DotCnText(text: "当 前 状 态", size: 8, color: Mono.paperDim)
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(statusText.contains("已授权") || statusText.contains("已同步")
                                      ? Mono.ok : Mono.red)
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                            DotCnText(text: statusText, size: 10, color: Mono.paperInk,
                                      wrapAlignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    Hairline(color: Mono.paperHair).padding(.top, 20)

                    // MARK: 路径 1：直接调用网站授权
                    sectionTitle("直 接 调 用 网 站 授 权")
                    DotCnText(text: "若已在网站开通新版空调，一键同步网站保存的凭证到本机，无需再次扫码。",
                              size: 8, color: Mono.paperDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    actionButton(busySync ? "同 步 中" : "从 网 站 同 步 授 权",
                                 filled: true, disabled: busySync) {
                        Task { await syncWebsite() }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                    Hairline(color: Mono.paperHair).padding(.top, 22)

                    // MARK: 路径 2：网站扫码开通通道
                    sectionTitle("网 站 授 权 通 道 · 扫 码 开 通")
                    DotCnText(text: "首次使用或凭证已过期时，由网站生成二维码，用长安汽车 App 扫码确认开通。",
                              size: 8, color: Mono.paperDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    actionButton(showQR ? "收 起 二 维 码" : "扫 码 开 通 / 刷 新 二 维 码",
                                 filled: false, disabled: false) {
                        if showQR {
                            pollTask?.cancel()
                            pollTask = nil
                            showQR = false
                        } else {
                            showQR = true
                            startQR(force: false)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                    if showQR {
                        qrPanel
                            .padding(.horizontal, 22)
                            .padding(.top, 16)
                    }

                    if let qrError {
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle().fill(Mono.red).frame(width: 2)
                            DotCnText(text: qrError, size: 8, color: Mono.paperInk,
                                      wrapAlignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 14)
                    }

                    Hairline(color: Mono.paperHair).padding(.top, 24)

                    DotCnText(text: "开通后网站会保存凭证，后续空调指令自动使用；到期前 App 会自动续期。",
                              size: 8, color: Mono.paperDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.light)
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: 二维码面板

    private var qrPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Mono.paperHair, lineWidth: 1))
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(14)
                } else if let qrURL {
                    AsyncImage(url: qrURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().interpolation(.none).scaledToFit().padding(14)
                        case .failure:
                            DotCnText(text: "二维码加载失败", size: 8, color: Mono.paperDim)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            ProgressView()
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(width: 212, height: 212)
            .frame(maxWidth: .infinity, alignment: .center)

            DotCnText(text: qrStatus, size: 9, color: Mono.paperInk, wrapAlignment: .center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("网站授权二维码，\(qrStatus)")
    }

    // MARK: 组件

    private func sectionTitle(_ text: String) -> some View {
        DotCnText(text: text, size: 9, color: Mono.paperInk)
            .padding(.horizontal, 22)
            .padding(.top, 20)
    }

    private func actionButton(_ title: String, filled: Bool, disabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DotCnText(text: title, size: 10,
                          color: filled ? Mono.paper : Mono.paperInk)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(filled ? Mono.paper : Mono.paperDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(filled ? Mono.paperInk : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2)
                .stroke(filled ? Color.clear : Mono.paperHair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(title.replacingOccurrences(of: " ", with: ""))
    }

    // MARK: 路径 1：直接调用网站授权

    @MainActor
    private func syncWebsite() async {
        guard let credentials = SharedStore.loadCredentials() else {
            statusText = "未登录，请先登录 CAKOCHE"
            qrError = nil
            return
        }
        busySync = true
        defer { busySync = false }
        let result = await ACService.syncWebsiteAuthorization(credentials: credentials)
        statusText = result.ok ? result.message : "未同步 · \(result.message)"
        qrError = result.ok ? nil : result.message
    }

    // MARK: 路径 2：网站扫码开通通道

    @MainActor
    private func startQR(force: Bool) {
        pollTask?.cancel()
        qrError = nil
        qrImage = nil
        qrURL = nil
        qrId = ""
        qrStatus = "正在向网站申请授权二维码…"
        guard let phone = SharedStore.loadCredentials()?.phone else {
            qrStatus = ""
            qrError = "未登录，请先登录 CAKOCHE"
            return
        }
        pollTask = Task {
            do {
                let qr = try await ACService.requestQRCode(phone: phone, force: force)
                if Task.isCancelled { return }
                qrId = qr.id
                deadline = Date().addingTimeInterval(Double(qr.ttl))
                if let data = qr.imageData, let image = UIImage(data: data) {
                    qrImage = image
                } else {
                    qrURL = qr.imageURL
                }
                qrStatus = qr.hasExisting
                    ? "网站已有授权记录 · 请扫码重新确认"
                    : "请用长安汽车 App 扫码"
                await poll()
            } catch {
                if Task.isCancelled { return }
                qrStatus = "生成失败"
                qrError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            if let deadline, Date() > deadline {
                qrStatus = "二维码已过期"
                qrError = "请点「扫码开通 / 刷新二维码」重新获取"
                return
            }
            guard !qrId.isEmpty else { continue }
            do {
                let status = try await ACService.pollStatus(qrcodeId: qrId)
                if Task.isCancelled { return }
                switch status.result {
                case .unauthorized:
                    qrStatus = "请用长安汽车 App 扫码"
                case .scanned:
                    qrStatus = "已扫码，请在手机上点「确认授权」"
                case .authorized:
                    // 网站授权成功：把网站下发的凭证落盘，供 executeOfficial 使用
                    if let token = status.refreshToken, !token.isEmpty {
                        SharedStore.saveACOpenRefreshToken(token)
                    }
                    qrStatus = "开通成功 · 空调已可用"
                    qrError = nil
                    statusText = ACService.websiteAuthorizationText()
                    showQR = false
                    return
                }
            } catch {
                if Task.isCancelled { return }
                qrStatus = "二维码已失效"
                qrError = error.localizedDescription
                return
            }
        }
    }
}
