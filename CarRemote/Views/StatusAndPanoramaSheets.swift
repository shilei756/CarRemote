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

/// 双列单元：左「字段名」灰、右「值」黑（对齐网页版每行两组字段）
struct StatusPair: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var color: Color? = nil

    init(_ label: String, _ value: String, _ color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}

/// 双列网格：每行两组「字段名 + 值」，间距宽松贴合网页版车况卡
private struct StatusPairGrid: View {
    let items: [StatusPair]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
            spacing: 0
        ) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.label)
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                    Text(item.value)
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(item.color ?? WebTheme.txt)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WebTheme.border.opacity(0.45)).frame(height: 0.5)
                }
            }
        }
    }
}

/// 分组卡片（网页版圆角白卡 + 加粗彩色标题）
private struct StatusGroup<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.bottom, 4)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }
}

/// 车辆状态页（1.11.7 重写：同步网页版 /vehicle_status 全部车况字段，双列卡片布局）
/// 对照网页截图：动力系统 / 门窗 / 灯光状态 / 空调环境 / 里程与能耗 / 车辆概况 / 胎压
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
                            powerGroup(status: status)       // 动力系统
                            doorsGroup(status: status)       // 门窗
                            lightsGroup(status: status)      // 灯光状态
                            climateGroup(status: status)     // 空调环境
                            mileageGroup(status: status)     // 里程与能耗
                            overviewGroup(status: status)    // 车辆概况
                            tiresGroup(status: status)       // 胎压
                        } else {
                            EmptyStateView(systemImage: "gauge.with.dots.needle.33percent",
                                           title: "暂无车况数据",
                                           message: "下拉或稍候自动获取车况")
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
            .inlineTitle("车况")
            .refreshable {
                await appState.refreshStatus()
            }
            .task {
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
                Text("车况")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(WebTheme.txt)
                Text("更新于 \(appState.statusUpdatedAt.map { Self.timeText($0) } ?? "--")")
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
            }
            Spacer()
            let badge = status.stateFlags.statusBadge
            HStack(spacing: 5) {
                Circle().fill(Self.flagColor(badge.key)).frame(width: 7, height: 7)
                Text(badge.text)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Self.flagColor(badge.key))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Self.flagColor(badge.key).opacity(0.10))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - 各分组（双列）

    private func powerGroup(status: CarStatus) -> some View {
        StatusGroup(title: "动力系统", symbol: "engine.combustion", tint: WebTheme.amber) {
            StatusPairGrid(items: [
                .init("发动机", status.engineRunning ? "运行中" : "熄火",
                      status.engineRunning ? WebTheme.green : WebTheme.txt),
                .init("发动机水温", Self.fmt(status.raw, ["engineWaterTemp", "coolantTemperature", "waterTemp", "engineCoolantTemp"], "℃", 1)),
                .init("冷却液状态", Self.stateText(status.raw, ["engineCoolantStatus", "coolantStatus"])),
                .init("机油压力", Self.stateText(status.raw, ["oilPressureStatus", "engineOilPressure"])),
                .init("变速箱", Self.stateText(status.raw, ["transmissionSystemStatus", "gearboxStatus"])),
                .init("ABS", Self.stateText(status.raw, ["absStatus"])),
                .init("稳定控制", Self.stateText(status.raw, ["vehicleStabilityControlSystemStatus", "stabilityControlStatus"])),
                .init("安全气囊", Self.stateText(status.raw, ["airbagSystemStatus", "airbagStatus"])),
                .init("发动机系统", Self.stateText(status.raw, ["engineSystemStatus"])),
                .init("驱动电机", Self.stateText(status.raw, ["driveMotorStatus", "motorStatus"])),
                .init("动力电池", Self.stateText(status.raw, ["powerBatteryStatus", "batterySystemStatus"])),
                .init("充电系统", Self.stateText(status.raw, ["chargingSystemStatus"])),
                .init("无钥匙系统", Self.stateText(status.raw, ["keylessEntryStartSystemStatus", "keylessSystemStatus"])),
                .init("转向助力", Self.stateText(status.raw, ["assistantSteeringStatus", "steeringAssistStatus"])),
                .init("燃油压力", Self.stateText(status.raw, ["fuelPressureStatus", "fuelPressure"])),
            ])
        }
    }

    private func doorsGroup(status: CarStatus) -> some View {
        StatusGroup(title: "门窗", symbol: "door.left.hand.open", tint: WebTheme.blue) {
            StatusPairGrid(items: [
                .init("左前门", Self.lockText(Self.val(status.raw, ["leftFrontDoorStatus"]))),
                .init("右前门", Self.lockText(Self.val(status.raw, ["rightFrontDoorStatus"]))),
                .init("左后门", Self.lockText(Self.val(status.raw, ["leftRearDoorStatus"]))),
                .init("右后门", Self.lockText(Self.val(status.raw, ["rightRearDoorStatus"]))),
                .init("左前车窗", Self.closeText(Self.val(status.raw, ["diverWindow", "driverWindow", "leftFrontDoorrWindow", "leftFrontDoorWindow"]))),
                .init("右前车窗", Self.closeText(Self.val(status.raw, ["passengerWindow"]))),
                .init("左后车窗", Self.closeText(Self.val(status.raw, ["leftRearWindow"]))),
                .init("右后车窗", Self.closeText(Self.val(status.raw, ["rightRearWindow"]))),
                .init("天窗", Self.closeText(Self.val(status.raw, ["sunroof", "skyWindow", "dormer"]))),
                .init("后备箱", Self.closeText(Self.val(status.raw, ["trunk"]))),
                .init("前机盖", Self.closeText(Self.val(status.raw, ["hood"]))),
            ])
        }
    }

    private func lightsGroup(status: CarStatus) -> some View {
        StatusGroup(title: "灯光状态", symbol: "lightbulb", tint: WebTheme.amber) {
            StatusPairGrid(items: [
                .init("近光灯", Self.onOffText(Self.val(status.raw, ["lowBeam", "lowBeamStatus"]))),
                .init("远光灯", Self.onOffText(Self.val(status.raw, ["highBeam", "highBeamStatus"]))),
                .init("示廓灯", Self.onOffText(Self.val(status.raw, ["positionLight", "widthLight"]))),
                .init("前雾灯", Self.onOffText(Self.val(status.raw, ["frontFogLight"]))),
                .init("后雾灯", Self.onOffText(Self.val(status.raw, ["rearFogLight"]))),
                .init("左转向灯", Self.onOffText(Self.val(status.raw, ["leftTurnSignal"]))),
                .init("右转向灯", Self.onOffText(Self.val(status.raw, ["rightTurnSignal"]))),
                .init("双闪", Self.onOffText(Self.val(status.raw, ["hazardLight", "doubleFlash", "warningLight"]))),
            ])
        }
    }

    private func climateGroup(status: CarStatus) -> some View {
        StatusGroup(title: "空调环境", symbol: "snowflake", tint: WebTheme.blue) {
            StatusPairGrid(items: [
                .init("车外温度", Self.fmt(status.raw, ["vehicleTemperature", "outsideTemp", "ambientTemperature"], "℃", 0)),
                .init("车内温度", Self.fmt(status.raw, ["vehicleTempIn", "insideTemp", "interiorTemperature", "inCarTemperature"], "℃", 0)),
                .init("设定温度", Self.acSetText(status.raw)),
                .init("空气循环", Self.recycleText(Self.val(status.raw, ["airRecycleStatus", "airCirculationStatus"]))),
                .init("PM2.5", Self.fmt(status.raw, ["pm25", "pm2_5", "pm25Value"], "", 0)),
                .init("空气质量", Self.fmt(status.raw, ["airQualityInCarLevel", "airQuality", "airQualityLevel"], "级", 0)),
                .init("风速档位", Self.fanText(status.raw)),
            ])
        }
    }

    private func mileageGroup(status: CarStatus) -> some View {
        let fuelPct = status.fuelLeftLiters.map { l in
            Int(min(max(l / SharedStore.loadSettings().tankCapacityL * 100, 0), 100).rounded())
        }
        return StatusGroup(title: "里程与能耗", symbol: "road.lanes", tint: WebTheme.green) {
            StatusPairGrid(items: [
                .init("剩余续航", (CarStatus.format(status.remainingRangeKm)) + " km"),
                .init("剩余油量", (CarStatus.format(status.fuelLeftLiters)) + " L"),
                .init("剩余油量", fuelPct.map { "\($0)%" } ?? "--"),
                .init("百公里油耗", Self.fmt(status.raw, ["fuelConsumption100km", "oilWear100km", "averageFuelConsumption"], "L", 1)),
                .init("总里程", (CarStatus.format(status.totalOdometerKm)) + " km"),
                .init("电瓶电压", status.batteryVoltage.map { String(format: "%.1f V", $0) } ?? "--"),
                .init("上次行程", Self.lastTripText(status)),
            ])
        }
    }

    private func overviewGroup(status: CarStatus) -> some View {
        StatusGroup(title: "车辆概况", symbol: "car.fill", tint: WebTheme.purple) {
            StatusPairGrid(items: [
                .init("总里程", (CarStatus.format(status.totalOdometerKm)) + " km"),
                .init("钥匙电量", Self.stateText(status.raw, ["keyBatteryStatus", "remoteKeyBatteryStatus"])),
                .init("GPS", Self.val(status.raw, ["gpsStatus"]) == 1 ? "有效" : "--"),
                .init("信号强度", Self.fmt(status.raw, ["signalStrength", "gpsSignalStrength"], "%", 0)),
                .init("上次点火", Self.timeStampText(status.raw, ["ignitionTime", "lastIgnitionTime", "startTime"])),
            ])
        }
    }

    private func tiresGroup(status: CarStatus) -> some View {
        StatusGroup(title: "胎压", symbol: "circle.hexagongrid.circle", tint: WebTheme.green) {
            StatusPairGrid(items: status.tirePressures.map { tire in
                .init(tire.label, tire.valueKPa.map { "\(Int($0.rounded()))" } ?? "--",
                      tire.isLow ? WebTheme.red : WebTheme.txt)
            })
        }
    }

    // MARK: - 取值工具（多候选键容错，缺字段显示 "--"，不误报异常）

    private static func val(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            guard let v = dict[key] else { continue }
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let b = v as? Bool { return b ? 1 : 0 }
            if let s = v as? String, let d = Double(s) { return d }
        }
        return nil
    }

    /// 数值 + 单位（nil → "--"）
    private static func fmt(_ dict: [String: Any], _ keys: [String], _ unit: String, _ digits: Int) -> String {
        guard let v = val(dict, keys) else { return "--" }
        let num = String(format: "%.\(digits)f", v)
        return num + unit
    }

    /// 正常 / 异常（1=正常，0=异常，缺失=--）
    private static func stateText(_ dict: [String: Any], _ keys: [String]) -> String {
        guard let v = val(dict, keys) else { return "--" }
        return v == 1 ? "正常" : "异常"
    }

    /// 门锁：1=已解锁，0=已上锁，缺失=--
    private static func lockText(_ v: Double?) -> String {
        guard let v else { return "--" }
        return v == 1 ? "已解锁" : "已上锁"
    }

    /// 门窗/天窗：1=关闭，0=打开（网页版 isOpen 语义 1=已关闭），缺失=--
    private static func closeText(_ v: Double?) -> String {
        guard let v else { return "--" }
        return v == 1 ? "关闭" : "打开"
    }

    private static func onOffText(_ v: Double?) -> String {
        guard let v else { return "--" }
        return v == 1 ? "开启" : "关闭"
    }

    private static func recycleText(_ v: Double?) -> String {
        guard let v else { return "--" }
        return v == 1 ? "内循环" : "外循环"
    }

    private static func acSetText(_ dict: [String: Any]) -> String {
        guard let v = val(dict, ["airConditioningSetTemperature", "acTemp"]) else { return "--" }
        return String(format: "设定 %.0f℃", v)
    }

    private static func fanText(_ dict: [String: Any]) -> String {
        guard let v = val(dict, ["windSpeed", "fanSpeed", "airVolume", "wind"]) else { return "--" }
        return String(format: "%.0f 档", v)
    }

    private static func lastTripText(_ status: CarStatus) -> String {
        guard status.lastTripKm != nil || status.lastTripOilLiters != nil else { return "--" }
        return "\(CarStatus.format(status.lastTripKm)) km · 油耗 \(CarStatus.format(status.lastTripOilLiters)) L"
    }

    private static func timeStampText(_ dict: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
        }
        return "--"
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
