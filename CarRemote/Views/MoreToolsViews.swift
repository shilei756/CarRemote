import SwiftUI
import CarCore
import PhotosUI

// MARK: - 相册图片选择器（iOS 15+ 通用，用于自定义壁纸）

/// 从系统相册选一张图片，通过 onPick 回传 UIImage（已切回主线程）。
/// 用 PHPicker 而非 PhotosPicker 以兼容 iOS 15 部署目标。
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { parent.onCancel(); return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.parent.onPick(image) }
                } else {
                    DispatchQueue.main.async { self.parent.onCancel() }
                }
            }
        }
    }
}

/// 把图片等比缩放到最大边不超过 maxSide，再压成 JPEG Data（控制壁纸体积）
func downscaleToJPEG(_ image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.82) -> Data? {
    let side = max(image.size.width, image.size.height)
    guard side > maxSide else {
        return image.jpegData(compressionQuality: quality)
    }
    let scale = maxSide / side
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return resized.jpegData(compressionQuality: quality)
}

// MARK: - 空调开通扫码（网页版 openAcQrScan / startAcQr / pollAcStatus）

/// 扫码开通空调：展示二维码 → 轮询扫码状态 → 授权成功
struct ACQRScanSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 开通成功回调（供外部刷新剩余天数）
    var onActivated: () -> Void = {}

    @State private var qrImage: UIImage?
    @State private var qrURL: URL?
    @State private var statusText = "正在生成二维码…"
    @State private var statusColor: Color = WebTheme.muted
    @State private var errorText: String?
    @State private var qrId = ""
    @State private var deadline: Date?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                VStack(spacing: 16) {
                    Text("空调开通（新版）")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WebTheme.txt)
                    Text("新版空调指令通过长安开放平台下发，需先用「长安汽车」App 扫码授权")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(WebTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(WebTheme.border, lineWidth: 1)
                            )
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 180, height: 180)
                        } else if qrURL != nil {
                            AsyncImage(url: qrURL) { image in
                                image.resizable().interpolation(.none)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 180, height: 180)
                        } else {
                            ProgressView()
                                .frame(width: 180, height: 180)
                        }
                    }
                    .frame(width: 212, height: 212)

                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusColor)

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    HStack(spacing: 12) {
                        Button("刷新二维码") {
                            start(force: false)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(WebTheme.navGradient)
                        .clipShape(Capsule())

                        if appState.credentials != nil {
                            Button("已开通，去用新版") {
                                dismiss()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WebTheme.blue)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(WebTheme.blue.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(.top, 20)
            }
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(WebTheme.blue)
                }
            }
            .onAppear { start(force: false) }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private func start(force: Bool) {
        guard let credentials = appState.credentials else { return }
        pollTask?.cancel()
        errorText = nil
        statusText = "正在生成二维码…"
        statusColor = WebTheme.muted
        qrImage = nil
        qrURL = nil
        pollTask = Task {
            do {
                let qr = try await ACService.requestQRCode(phone: credentials.phone, force: force)
                if Task.isCancelled { return }
                qrId = qr.id
                deadline = Date().addingTimeInterval(Double(qr.ttl))
                if let data = qr.imageData, let image = UIImage(data: data) {
                    qrImage = image
                } else if let url = qr.imageURL {
                    qrURL = url
                }
                statusText = "请用长安汽车 App 扫码"
                statusColor = WebTheme.txt
                startPolling()
            } catch {
                if Task.isCancelled { return }
                statusText = "生成失败"
                statusColor = WebTheme.red
                errorText = error.localizedDescription
            }
        }
    }

    private func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                guard !qrId.isEmpty else { continue }
                if let deadline, Date() > deadline {
                    statusText = "二维码已过期"
                    statusColor = WebTheme.red
                    errorText = "请点击「刷新二维码」后重新扫码"
                    return
                }
                do {
                    let status = try await ACService.pollStatus(qrcodeId: qrId)
                    if Task.isCancelled { return }
                    switch status.result {
                    case .unauthorized:
                        statusText = "请用长安汽车 App 扫码"
                        statusColor = WebTheme.txt
                    case .scanned:
                        statusText = "已扫码，请在手机上点「确认授权」"
                        statusColor = WebTheme.amber
                    case .authorized:
                        statusText = "✅ 开通成功！空调已可用"
                        statusColor = WebTheme.green
                        // 保存授权成功返回的新鲜 refresh_token（首次刷新它才有车控权限）
                        if let rt = status.refreshToken, !rt.isEmpty {
                            SharedStore.saveACOpenRefreshToken(rt)
                        }
                        onActivated()
                        return
                    }
                } catch {
                    if Task.isCancelled { return }
                    statusText = "二维码已失效"
                    statusColor = WebTheme.red
                    errorText = error.localizedDescription
                    return
                }
            }
        }
    }
}

// MARK: - 操作历史

struct ControlHistorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var records: [ControlActionRecord] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                Group {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().tint(WebTheme.blue)
                            Text("加载中…").font(.system(size: 13)).foregroundStyle(WebTheme.muted)
                        }
                    } else if let errorText {
                        EmptyStateView(systemImage: "exclamationmark.triangle", title: "加载失败", message: errorText)
                    } else if records.isEmpty {
                        EmptyStateView(systemImage: "clock.arrow.circlepath", title: "暂无操作历史", message: "执行控车指令后会显示在这里")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(records) { record in
                                    SectionCard(sakura: false) {
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Text(record.cmdDescription)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(WebTheme.txt)
                                                    Text(record.statusText)
                                                        .font(.system(size: 9.5, weight: .semibold))
                                                        .foregroundStyle(record.isSuccess ? WebTheme.green : WebTheme.red)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background((record.isSuccess ? WebTheme.green : WebTheme.red).opacity(0.12))
                                                        .clipShape(Capsule())
                                                }
                                                if !record.resultDesc.isEmpty {
                                                    Text(record.resultDesc)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(WebTheme.muted)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            Text(record.createAt)
                                                .font(.system(size: 9.5))
                                                .monospacedDigit()
                                                .foregroundStyle(WebTheme.faint)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .inlineTitle("操作历史")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(WebTheme.blue)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let credentials = appState.credentials else { return }
        do {
            let (token, updated) = try await AuthService.validAccessToken(for: credentials)
            SharedStore.saveCredentials(updated)
            let cars = try await CarService.fetchCars(accessToken: token)
            guard let car = cars.first else { throw APIError.server("未获取到车辆信息") }
            records = try await HistoryService.controlActions(carId: car.carId, accessToken: token)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 消息记录

struct MessageHistorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var records: [MessageRecord] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                Group {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().tint(WebTheme.blue)
                            Text("加载中…").font(.system(size: 13)).foregroundStyle(WebTheme.muted)
                        }
                    } else if let errorText {
                        EmptyStateView(systemImage: "exclamationmark.triangle", title: "加载失败", message: errorText)
                    } else if records.isEmpty {
                        EmptyStateView(systemImage: "bubble.left.and.text.bubble.right", title: "暂无消息", message: "近 30 天的车辆消息会显示在这里")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(records) { record in
                                    SectionCard(sakura: false) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(record.msgTime)
                                                .font(.system(size: 9.5))
                                                .monospacedDigit()
                                                .foregroundStyle(WebTheme.faint)
                                            Text(record.msgContent)
                                                .font(.system(size: 12.5))
                                                .foregroundStyle(WebTheme.txt)
                                            if !record.typeName.isEmpty {
                                                Text(record.typeName)
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(WebTheme.muted)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .inlineTitle("消息记录")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(WebTheme.blue)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let credentials = appState.credentials else { return }
        do {
            let (token, updated) = try await AuthService.validAccessToken(for: credentials)
            SharedStore.saveCredentials(updated)
            let cars = try await CarService.fetchCars(accessToken: token)
            guard let car = cars.first else { throw APIError.server("未获取到车辆信息") }
            records = try await HistoryService.messages(carId: car.carId, accessToken: token)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 我的行程

struct TripHistorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var records: [TripRecord] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                Group {
                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView().tint(WebTheme.blue)
                            Text("加载中…").font(.system(size: 13)).foregroundStyle(WebTheme.muted)
                        }
                    } else if let errorText {
                        EmptyStateView(systemImage: "exclamationmark.triangle", title: "加载失败", message: errorText)
                    } else if records.isEmpty {
                        EmptyStateView(systemImage: "road.lanes", title: "暂无行程", message: "近 7 天的行程会显示在这里")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(records) { record in
                                    SectionCard(sakura: false) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Text(record.startTime)
                                                    .font(.system(size: 11))
                                                    .monospacedDigit()
                                                    .foregroundStyle(WebTheme.muted)
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(WebTheme.faint)
                                                Text(record.endTime)
                                                    .font(.system(size: 11))
                                                    .monospacedDigit()
                                                    .foregroundStyle(WebTheme.muted)
                                            }
                                            HStack(spacing: 5) {
                                                Circle().fill(WebTheme.green).frame(width: 6, height: 6)
                                                Text(record.startAddress)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(WebTheme.txt)
                                                    .lineLimit(1)
                                            }
                                            HStack(spacing: 5) {
                                                Circle().fill(WebTheme.red).frame(width: 6, height: 6)
                                                Text(record.endAddress)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(WebTheme.txt)
                                                    .lineLimit(1)
                                            }
                                            HStack(spacing: 12) {
                                                tripStat(title: "里程", value: record.mileage.map { CarStatus.format($0) + " km" } ?? "--")
                                                tripStat(title: "耗时", value: record.spendTime.map { CarStatus.format($0) + " 分" } ?? "--")
                                                tripStat(title: "均速", value: record.avgSpeed.map { CarStatus.format($0) + " km/h" } ?? "--")
                                                tripStat(title: "油耗", value: record.oil.map { CarStatus.format($0) + " L" } ?? "--")
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .inlineTitle("我的行程")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(WebTheme.blue)
                }
            }
            .task { await load() }
        }
    }

    private func tripStat(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(WebTheme.faint)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WebTheme.txt)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard let credentials = appState.credentials else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let end = formatter.string(from: Date())
        let start = formatter.string(from: Date().addingTimeInterval(-6 * 24 * 3600))
        do {
            let (token, updated) = try await AuthService.validAccessToken(for: credentials)
            SharedStore.saveCredentials(updated)
            let cars = try await CarService.fetchCars(accessToken: token)
            guard let car = cars.first else { throw APIError.server("未获取到车辆信息") }
            records = try await HistoryService.trips(carId: car.carId, accessToken: token, startDate: start, endDate: end)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 车辆状态 / 360全景（内嵌网页版页面）

struct EmbedWebSheet: View {
    let key: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                if let url = embedURL {
                    WebViewBridge(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    EmptyStateView(systemImage: "globe", title: "暂不可用", message: "请先登录后重试")
                }
            }
            .inlineTitle(key == "vehicle_status" ? "车辆状态" : "360全景")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(WebTheme.blue)
                }
            }
        }
    }

    /// 与网页版 credQuery 一致：phone + ref_token + pin + embed=1
    private var embedURL: URL? {
        guard let credentials = appState.credentials else { return nil }
        var components = URLComponents(string: APIConfig.siteBaseURL + "/" + key)
        components?.queryItems = [
            URLQueryItem(name: "phone", value: credentials.phone),
            URLQueryItem(name: "ref_token", value: credentials.refToken),
            URLQueryItem(name: "pin", value: credentials.pin),
            URLQueryItem(name: "embed", value: "1")
        ]
        return components?.url
    }
}

// MARK: - 背景壁纸

struct WallpaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    /// true = 由「我的」页 NavigationLink 推入（不自带 NavStack、点选即时保存）
    var isPushed = false
    @State private var sakuraEnabled = SharedStore.loadSakuraEnabled()
    /// 神兽主题授权（网页版 /myth/check）
    @State private var mythAllowed = false
    @State private var mythChecked = false
    /// 自定义壁纸选择
    @State private var showImagePicker = false
    @State private var hasCustomWallpaper: Bool = SharedStore.loadCustomWallpaper() != nil

    /// 当前神兽主题（AppState 持久化发布属性，变化时整树换色）
    private var myth: MythTheme? {
        get { appState.mythTheme }
        nonmutating set { appState.mythTheme = newValue }
    }

    var body: some View {
        Group {
            if isPushed {
                ZStack {
                    WebConsoleBackground()
                    ScrollView { options }
                }
            } else {
                NavStack {
                    ZStack {
                        WebConsoleBackground()
                        ScrollView { options }
                    }
                    .inlineTitle("背景壁纸")
                    .toolbar {
                        ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                            Button("完成") {
                                SharedStore.saveSakuraEnabled(sakuraEnabled)
                                dismiss()
                            }
                            .foregroundStyle(WebTheme.blue)
                        }
                    }
                }
            }
        }
        .task {
            // 网页版 mythEntry：服务端授权判定后才显示神兽主题区
            guard !mythChecked, let phone = appState.credentials?.phone else { return }
            mythChecked = true
            let access = await MythService.check(phone: phone)
            mythAllowed = access.allowed
        }
        .sheet(isPresented: $showImagePicker) {
            PhotoLibraryPicker(
                onPick: { image in
                    if let data = downscaleToJPEG(image) {
                        SharedStore.saveCustomWallpaper(data)
                        hasCustomWallpaper = true
                    }
                },
                onCancel: { }
            )
        }
    }

    /// 壁纸选项（push 模式下点选即时保存）
    private var options: some View {
        VStack(spacing: 14) {
            wallpaperOption(
                title: "樱花飘落",
                subtitle: "卡片顶部花瓣缓缓飘落（网页版默认）",
                symbol: "snowflake",
                selected: sakuraEnabled && !hasCustomWallpaper
            ) {
                sakuraEnabled = true
                SharedStore.saveCustomWallpaper(nil)
                hasCustomWallpaper = false
                if isPushed { SharedStore.saveSakuraEnabled(true) }
            }
            wallpaperOption(
                title: "纯净背景",
                subtitle: "仅保留浅色背景与光晕，无花瓣动画",
                symbol: "circle",
                selected: !sakuraEnabled && !hasCustomWallpaper
            ) {
                sakuraEnabled = false
                SharedStore.saveCustomWallpaper(nil)
                hasCustomWallpaper = false
                if isPushed { SharedStore.saveSakuraEnabled(false) }
            }
            // 自定义图片：从相册上传作为背景
            wallpaperOption(
                title: "自定义图片",
                subtitle: "从相册选择一张图作为背景（适配液态玻璃控车栏）",
                symbol: "photo.on.rectangle.angled",
                selected: hasCustomWallpaper
            ) {
                showImagePicker = true
            }
            if hasCustomWallpaper {
                Button {
                    SharedStore.saveCustomWallpaper(nil)
                    hasCustomWallpaper = false
                } label: {
                    HStack {
                        Spacer()
                        Text("移除自定义壁纸")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WebTheme.red)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .background(WebTheme.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(WebTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            if mythAllowed {
                mythSection
            }
            Spacer(minLength: 32)
        }
        .padding(16)
    }

    /// 神兽主题区（网页版 mythPage：四张主题卡 + 恢复经典默认）
    private var mythSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebTheme.blue)
                Text("神兽主题")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text("整套界面换装")
                    .font(.system(size: 10))
                    .foregroundStyle(WebTheme.faint)
            }
            Text("背景、卡片、按键、图标、顶底栏全部随神兽换色（网页版同款）")
                .font(.system(size: 10.5))
                .foregroundStyle(WebTheme.muted)

            ForEach(MythTheme.allCases, id: \.self) { theme in
                mythOption(theme)
            }

            Button {
                myth = nil
            } label: {
                HStack {
                    Spacer()
                    Text("恢复经典默认")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WebTheme.muted)
                    Spacer()
                }
                .padding(.vertical, 11)
                .background(WebTheme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WebTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard()
    }

    /// 单个神兽主题卡（网页版 mythList 行）
    private func mythOption(_ theme: MythTheme) -> some View {
        let selected = myth == theme
        return Button {
            myth = theme
        } label: {
            HStack(spacing: 12) {
                // 渐变预览块 + 神兽图标
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: theme.previewHexes.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(theme.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                        .opacity(0.85)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(theme.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                        if selected {
                            Text("使用中")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(WebTheme.green.opacity(0.12))
                                .foregroundStyle(WebTheme.green)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    Text(theme.subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: theme.mainHex))
                    Text(theme.desc)
                        .font(.system(size: 9.5))
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: theme.mainHex))
                }
            }
            .padding(10)
            .background(WebTheme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color(hex: theme.mainHex) : WebTheme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func wallpaperOption(title: String, subtitle: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? WebTheme.blue : WebTheme.muted)
                    .frame(width: 40, height: 40)
                    .background((selected ? WebTheme.blue : WebTheme.muted).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WebTheme.muted)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WebTheme.blue)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
