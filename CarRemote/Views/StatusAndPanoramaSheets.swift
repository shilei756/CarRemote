import SwiftUI
import CarCore

// MARK: - 车辆状态（原生，替代内嵌网页）

/// 分组状态行
private struct StatusRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color ?? WebTheme.txt)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WebTheme.border.opacity(0.5)).frame(height: 0.5)
        }
    }
}

/// 分组卡片
private struct StatusGroup<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
            }
            .padding(.bottom, 6)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
    }
}

/// 车辆状态页（原生重写网页版 /vehicle_status；已独立为底部「车况」标签页）
struct VehicleStatusPage: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if let status = appState.status {
                            header(status: status)
                            powerGroup(status: status)
                            climateGroup(status: status)
                            doorsGroup(status: status)
                            tiresGroup(status: status)
                        } else {
                            EmptyStateView(systemImage: "gauge.with.dots.needle.33percent",
                                           title: "暂无车况数据",
                                           message: "下拉或稍候自动获取车况")
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .inlineTitle("车辆状态")
            .refreshable {
                await appState.refreshStatus()
            }
            .task {
                // 进入页面先刷一次（控车页 30 秒轮询仍在后台持续更新）
                if appState.statusUpdatedAt == nil {
                    await appState.refreshStatus()
                }
            }
        }
        .tint(WebTheme.blue)
    }

    private func header(status: CarStatus) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("更新时间：\(appState.statusUpdatedAt.map { Self.timeText($0) } ?? "--")")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.muted)
            }
            Spacer()
            let badge = status.stateFlags.statusBadge
            HStack(spacing: 5) {
                Circle().fill(Self.flagColor(badge.key)).frame(width: 6, height: 6)
                Text(badge.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.flagColor(badge.key))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Self.flagColor(badge.key).opacity(0.09))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
    }

    /// 动力系统
    private func powerGroup(status: CarStatus) -> some View {
        StatusGroup(title: "动力系统", symbol: "engine.combustion", tint: WebTheme.amber) {
            StatusRow(label: "发动机",
                      value: status.engineRunning ? "运行中" : "已熄火",
                      color: status.engineRunning ? WebTheme.green : WebTheme.muted)
            if let t = Self.number(status.raw, ["coolantTemperature", "engineCoolantTemp", "coolantTemp"]) {
                StatusRow(label: "发动机水温", value: String(format: "%.1f ℃", t))
            }
            StatusRow(label: "电瓶电压",
                      value: status.batteryVoltage.map { String(format: "%.1f V", $0) } ?? "--",
                      color: voltageColor(status.batteryVoltage))
            if let speed = Self.number(status.raw, ["vehicleSpeed", "speed"]) {
                StatusRow(label: "车速", value: String(format: "%.0f km/h", speed))
            }
            StatusRow(label: "总里程", value: (CarStatus.format(status.totalOdometerKm)) + " km")
        }
    }

    /// 空调环境
    private func climateGroup(status: CarStatus) -> some View {
        StatusGroup(title: "空调环境", symbol: "snowflake", tint: WebTheme.blue) {
            StatusRow(label: "车外温度", value: status.vehicleTempC.map { String(format: "%.0f ℃", $0) } ?? "--")
            StatusRow(label: "空调设定", value: status.acTempC.map { String(format: "%.0f ℃", $0) } ?? "未开启")
        }
    }

    /// 门窗
    private func doorsGroup(status: CarStatus) -> some View {
        StatusGroup(title: "门窗", symbol: "door.left.hand.open", tint: WebTheme.purple) {
            StatusRow(label: "左前门", value: doorText(["leftFrontDoorStatus"]))
            StatusRow(label: "右前门", value: doorText(["rightFrontDoorStatus"]))
            StatusRow(label: "左后门", value: doorText(["leftRearDoorStatus"]))
            StatusRow(label: "右后门", value: doorText(["rightRearDoorStatus"]))
            StatusRow(label: "后备箱", value: doorText(["trunk"]))
            StatusRow(label: "引擎盖", value: doorText(["hood"]))
            StatusRow(label: "天窗", value: doorText(["sunroof", "skyWindow", "dormer"]))
            StatusRow(label: "车窗", value: windowText())
        }
    }

    /// 胎压
    private func tiresGroup(status: CarStatus) -> some View {
        StatusGroup(title: "胎压监测", symbol: "circle.hexagongrid.circle", tint: WebTheme.green) {
            ForEach(Array(status.tirePressures.enumerated()), id: \.offset) { _, tire in
                let text = tire.valueKPa.map { "\(Int($0.rounded())) kPa" } ?? "--"
                StatusRow(label: tire.label, value: text,
                          color: tire.isLow ? WebTheme.red : nil)
            }
        }
    }

    // MARK: - 取值工具

    /// 车门类：1 = 打开（网页版同语义），nil = 官网未返回
    private func doorText(_ keys: [String]) -> String {
        guard let raw = appState.status else { return "--" }
        for key in keys {
            if let v = Self.number(raw.raw, [key]) {
                return v == 1 ? "打开" : "关闭"
            }
            if let s = raw.raw[key] as? String, s == "1" || s == "0" {
                return s == "1" ? "打开" : "关闭"
            }
        }
        return "--"
    }

    private func windowText() -> String {
        guard let raw = appState.status else { return "--" }
        let keys = ["diverWindow", "driverWindow", "leftFrontDoorrWindow", "leftFrontDoorWindow",
                    "passengerWindow", "leftRearWindow", "rightRearWindow", "window"]
        for key in keys {
            if let v = Self.number(raw.raw, [key]), v == 1 { return "有车窗未关" }
        }
        if keys.contains(where: { Self.number(raw.raw, [$0]) != nil }) { return "全部关闭" }
        return "--"
    }

    private static func number(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let s = value as? String, let d = Double(s) { return d }
        }
        return nil
    }

    private func voltageColor(_ voltage: Double?) -> Color {
        guard let voltage else { return WebTheme.green }
        if voltage < 11.8 || voltage > 14.8 { return WebTheme.red }
        return WebTheme.green
    }

    private static func flagColor(_ key: String) -> Color {
        switch key {
        case "door": return WebTheme.amber
        case "win": return WebTheme.blue
        case "engine": return WebTheme.red
        default: return WebTheme.green
        }
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - 360 全景（原生，替代内嵌网页）

struct PanoramaSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // 拍照任务
    @State private var isRequesting = false
    @State private var pendingTaskId: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var pendingStart: Date?
    @State private var toast: String?
    @State private var newImages: [PanoramaImage] = []

    // 历史
    @State private var records: [PanoramaRecord] = []
    @State private var isLoadingHistory = false
    @State private var rangeKey: String = "all"   // all / today / 7d / 30d

    // 大图查看
    @State private var viewerURL: URL?

    private let posLabels = ["前视", "左视", "右视", "后视"]

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        requestCard
                        if !newImages.isEmpty { newImagesCard }
                        historyCard
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .inlineTitle("360全景")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("关闭") {
                        pollTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(WebTheme.blue)
                }
            }
            .sheet(item: Binding(
                get: { viewerURL.map { ViewerItem(url: $0) } },
                set: { viewerURL = $0?.url }
            )) { item in
                ImageViewerSheet(url: item.url)
            }
            .toast(toast)
            .compatOnChange(of: toast) { newValue in
                if newValue != nil {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        toast = nil
                    }
                }
            }
            .task { await loadHistory() }
            .onDisappear { pollTask?.cancel() }
        }
        .tint(WebTheme.blue)
    }

    private struct ViewerItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    // MARK: - 拍照卡片

    private var requestCard: some View {
        VStack(spacing: 12) {
            Button {
                Task { await requestPanorama() }
            } label: {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(pendingTaskId != nil ? "车端拍照中，稍后自动取图…" : "远程拍照（生成 360 全景）")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isRequesting ? WebTheme.blue.opacity(0.6) : WebTheme.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRequesting)

            Text("下发指令后车端自动拍照并上传，约需 1-2 分钟；拍好的四视角图会自动存入下方历史")
                .font(.system(size: 11))
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)

            if let start = pendingStart {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(WebTheme.blue)
                    Text("已等待 \(Int(Date().timeIntervalSince(start) / 60)) 分钟，最多等 8 分钟")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(WebTheme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 14)
    }

    // MARK: - 新拍图片

    private var newImagesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本次拍摄")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            imageGrid(urls: newImages.map { URL(string: $0.url) },
                      labels: posLabels,
                      files: newImages.map { $0.name })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
    }

    // MARK: - 历史

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                if isLoadingHistory {
                    ProgressView().scaleEffect(0.7).tint(WebTheme.muted)
                }
            }
            HStack(spacing: 8) {
                ForEach([("all", "全部"), ("today", "今天"), ("7d", "近7天"), ("30d", "近30天")], id: \.0) { key, label in
                    Button {
                        rangeKey = key
                        Task { await loadHistory() }
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: rangeKey == key ? .bold : .regular))
                            .foregroundStyle(rangeKey == key ? .white : WebTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(rangeKey == key ? WebTheme.blue : WebTheme.card2)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            if records.isEmpty && !isLoadingHistory {
                Text("暂无历史全景图")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                let dateText = PanoramaService.formattedTime(record.timestamp.timeIntervalSince1970)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(dateText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WebTheme.txt)
                        Spacer()
                        Text("4 视角")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }
                    imageGrid(urls: record.imageFiles.map { file in
                        PanoramaService.cacheURL(file: file, phone: appState.credentials?.phone ?? "")
                    }, labels: record.dirLabels.isEmpty ? posLabels : record.dirLabels,
                      files: record.imageFiles)
                }
                .padding(12)
                .background(WebTheme.card2.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
    }

    /// 2×2 图片网格
    private func imageGrid(urls: [URL?], labels: [String], files: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<4, id: \.self) { idx in
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Rectangle().fill(WebTheme.card2).aspectRatio(4/3, contentMode: .fit)
                        if idx < urls.count, let url = urls[idx] {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    ProgressView().tint(WebTheme.muted)
                                }
                            }
                            .aspectRatio(4/3, contentMode: .fit)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { viewerURL = url }
                        } else {
                            Text("图片已失效")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    HStack {
                        Text(idx < labels.count && !labels[idx].isEmpty ? labels[idx] : posLabels[idx])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WebTheme.txt)
                        Spacer()
                        if idx < urls.count, urls[idx] != nil {
                            Button {
                                Task { await saveToAlbum(idx: idx, urls: urls, files: files) }
                            } label: {
                                Label("保存", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WebTheme.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(WebTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WebTheme.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - 逻辑

    private func requestPanorama() async {
        guard let credentials = appState.credentials else {
            toast = "请先登录"
            return
        }
        isRequesting = true
        defer { isRequesting = false }
        do {
            let taskId = try await PanoramaService.request(credentials: credentials)
            pendingTaskId = taskId
            pendingStart = Date()
            toast = "拍照指令已下发，车端上传后自动取图"
            pollTask?.cancel()
            pollTask = Task { await pollImages(taskId: taskId, started: Date()) }
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 每 25 秒查一次车端是否上传完成，最多 8 分钟
    private func pollImages(taskId: String, started: Date) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            if Task.isCancelled { return }
            if Date().timeIntervalSince(started) > 8 * 60 {
                pendingTaskId = nil
                pendingStart = nil
                toast = "拍照任务等待超时，车端未上传图片"
                return
            }
            guard let credentials = appState.credentials else { return }
            do {
                let images = try await PanoramaService.fetchImages(taskId: taskId, credentials: credentials)
                guard !images.isEmpty else { continue }
                newImages = images
                pendingTaskId = nil
                pendingStart = nil
                toast = "360 全景图已取回"
                await PanoramaService.save(
                    phone: credentials.phone,
                    taskId: taskId,
                    images: images
                )
                await loadHistory()
                return
            } catch {
                // 单次查询失败继续下一轮
            }
        }
    }

    private func loadHistory() async {
        guard let phone = appState.credentials?.phone else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let (start, end) = rangeDates()
        records = (try? await PanoramaService.history(phone: phone, start: start, end: end)) ?? []
    }

    private func rangeDates() -> (start: String, end: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        switch rangeKey {
        case "today": return (f.string(from: now), f.string(from: now))
        case "7d": return (f.string(from: now.addingTimeInterval(-6 * 86400)), f.string(from: now))
        case "30d": return (f.string(from: now.addingTimeInterval(-29 * 86400)), f.string(from: now))
        default: return ("", "")
        }
    }

    /// 保存图片到相册（远程图走同源代理绕跨域）
    private func saveToAlbum(idx: Int, urls: [URL?], files: [String]) async {
        guard idx < urls.count, let url = urls[idx] else { return }
        do {
            let data: Data
            if idx < files.count, !files[idx].isEmpty, url.absoluteString.contains("/pano_cache/") {
                guard let d = try? Data(contentsOf: url) else {
                    toast = "图片下载失败"
                    return
                }
                data = d
            } else if url.absoluteString.hasPrefix("http") {
                let proxy = PanoramaService.proxyURL(
                    for: url.absoluteString,
                    name: "360全景_\(Int(Date().timeIntervalSince1970)).jpg"
                )
                guard let proxy, let d = try? Data(contentsOf: proxy) else {
                    toast = "图片下载失败"
                    return
                }
                data = d
            } else {
                guard let d = try? Data(contentsOf: url) else {
                    toast = "图片下载失败"
                    return
                }
                data = d
            }
            guard let image = UIImage(data: data) else {
                toast = "图片格式异常"
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            toast = "已保存到相册"
        }
    }
}

/// 全屏大图查看（捏合缩放）
struct ImageViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = min(max($0, 1), 5) }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { scale = scale > 1 ? 1 : 2.5 }
                        }
                } else {
                    ProgressView().tint(.white)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .padding(16)
        }
    }
}
