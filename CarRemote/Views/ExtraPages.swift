import SwiftUI
import CarCore
import UIKit

// MARK: - 行程统计（#5）

/// 最近一周 / 一月的里程、油耗、平均速度聚合统计。
/// 数据源复用 HistoryService.trips（与「我的行程」同源），按自然日聚合绘制柱状图。
/// 当所选区间没有真实行程记录时，展示一组确定性的演示数据并打上「演示数据」标识，
/// 让用户在未产生行程前也能直观看到统计形态。
struct TripStatsView: View {
    @EnvironmentObject private var appState: AppState

    enum StatsRange: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var title: String { self == .week ? "最近一周" : "最近一月" }
        var days: Int { self == .week ? 7 : 30 }
    }

    @State private var range: StatsRange = .week
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var records: [TripRecord] = []
    @State private var isDemo = false

    // 聚合结果
    @State private var dayBars: [DayBar] = []
    @State private var totalMileage = 0.0
    @State private var totalOil = 0.0
    @State private var avgSpeed = 0.0
    @State private var tripCount = 0

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
                        EmptyStateView(systemImage: "exclamationmark.triangle",
                                      title: "加载失败", message: errorText)
                    } else {
                        statsContent
                    }
                }
            }
            .inlineTitle("行程统计")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Picker("统计区间", selection: $range) {
                        ForEach(StatsRange.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
            }
            .compatOnChange(of: range) { _ in
                Task { await load() }
            }
            .task { await load() }
        }
    }

    // MARK: 统计内容

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isDemo {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("演示数据：近 \(range.days) 天暂无行程记录，以下为示例统计")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WebTheme.amber.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.top, 4)
                }

                // 总里程大数字
                SectionCard {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(CarStatus.format(totalMileage))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("km")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(WebTheme.muted)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(tripCount) 段行程")
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.muted)
                            Text(range.title)
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    .padding(.bottom, 4)
                    // 柱状图
                    barChart
                        .frame(height: 160)
                        .padding(.top, 6)
                }

                // 关键指标
                SectionCard {
                    HStack(spacing: 0) {
                        metricCell(title: "总油耗", value: CarStatus.format(totalOil) + " L")
                        Divider().frame(height: 36)
                        metricCell(title: "平均速度", value: CarStatus.format(avgSpeed) + " km/h")
                        Divider().frame(height: 36)
                        metricCell(title: "日均里程", value: CarStatus.format(tripCount > 0 ? totalMileage / Double(range.days) : 0) + " km")
                    }
                }

                if !isDemo && !records.isEmpty {
                    SectionCard(title: "行程明细") {
                        LazyVStack(spacing: 8) {
                            ForEach(records) { record in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(record.startAddress)
                                            .font(.system(size: 12))
                                            .foregroundStyle(WebTheme.txt)
                                            .lineLimit(1)
                                        Text(record.endAddress)
                                            .font(.system(size: 12))
                                            .foregroundStyle(WebTheme.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(CarStatus.format(record.mileage ?? 0) + " km")
                                            .font(.system(size: 12, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(WebTheme.txt)
                                        Text(record.startTime.prefix(10))
                                            .font(.system(size: 10))
                                            .foregroundStyle(WebTheme.faint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WebTheme.txt)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(WebTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var barChart: some View {
        let maxMileage = dayBars.map(\.mileage).max() ?? 0
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(dayBars) { bar in
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(bar.mileage > 0 ? WebTheme.blue : WebTheme.track)
                        .frame(height: maxMileage > 0 ? max(4, CGFloat(bar.mileage / maxMileage) * 132) : 4)
                    Text(bar.label)
                        .font(.system(size: range == .week ? 9 : 7))
                        .foregroundStyle(WebTheme.faint)
                        .lineLimit(1)
                }
                .accessibilityLabel("\(bar.label)，\(CarStatus.format(bar.mileage)) 公里")
            }
        }
    }

    // MARK: 数据加载与聚合

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            guard let credentials = appState.credentials else {
                throw APIError.server("未登录")
            }
            let (token, updated) = try await AuthService.validAccessToken(for: credentials)
            SharedStore.saveCredentials(updated)
            let cars = try await CarService.fetchCars(accessToken: token)
            guard let car = cars.first else { throw APIError.server("未获取到车辆信息") }
            let (start, end) = dateRange(for: range)
            records = try await HistoryService.trips(
                carId: car.carId, accessToken: token, startDate: start, endDate: end
            )
            isDemo = records.isEmpty
            aggregate()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func dateRange(for r: StatsRange) -> (start: String, end: String) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(r.days - 1), to: end)!
        return (dateFormatter.string(from: start), dateFormatter.string(from: end))
    }

    private func aggregate() {
        let source = isDemo ? Self.demoRecords(for: range) : records
        let calendar = Calendar.current
        let (start, end) = dateRange(for: range)
        guard let startDate = dateFormatter.date(from: start),
              let endDate = dateFormatter.date(from: end) else { return }

        var byDay: [String: Double] = [:]
        var totalM = 0.0, totalO = 0.0, totalMin = 0.0, count = 0
        for record in source {
            let dayKey = String(record.startTime.prefix(10))
            if let m = record.mileage { byDay[dayKey, default: 0] += m; totalM += m }
            if let o = record.oil { totalO += o }
            if let s = record.spendTime { totalMin += s }
            count += 1
        }

        // 按自然日顺序生成柱状图
        var bars: [DayBar] = []
        var cursor = startDate
        let weekdaySymbols = calendar.veryShortWeekdaySymbols
        while cursor <= endDate {
            let key = dateFormatter.string(from: cursor)
            let mileage = byDay[key] ?? 0
            let weekday = calendar.component(.weekday, from: cursor)
            let label = range == .week
                ? weekdaySymbols[(weekday - 1) % 7]
                : "\(calendar.component(.day, from: cursor))"
            bars.append(DayBar(date: cursor, label: label, mileage: mileage))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }

        dayBars = bars
        totalMileage = totalM
        totalOil = totalO
        tripCount = count
        // 平均速度 = 总里程 / 总耗时（小时）
        avgSpeed = totalMin > 0 ? (totalM / (totalMin / 60.0)) : 0
    }

    /// 确定性演示数据：用正弦曲线生成每日里程，保证每次展示一致、形态自然。
    static func demoRecords(for r: StatsRange) -> [TripRecord] {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -(r.days - 1), to: end)!
        var records: [TripRecord] = []
        var cursor = start
        var idx = 0
        while cursor <= end {
            let key = DateFormatter.yyyyMMdd.string(from: cursor)
            // 工作日里程高、周末低，叠加正弦波动；约 60% 的日子有行程
            let weekday = calendar.component(.weekday, from: cursor)
            let isWeekend = (weekday == 1 || weekday == 7)
            let base = isWeekend ? 8.0 : 28.0
            let wave = 14.0 * sin(Double(idx) * 0.9)
            let mileage = max(0, base + wave)
            if idx % 5 != 4 {
                records.append(TripRecord(
                    startTime: key + " 08:30:00", endTime: key + " 09:10:00",
                    startAddress: "家", endAddress: "公司",
                    mileage: mileage, spendTime: mileage / 22.0 * 60.0,
                    avgSpeed: 22.0 + Double(idx % 7), oil: mileage / 14.0
                ))
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            idx += 1
        }
        return records
    }
}

private struct DayBar: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let mileage: Double
}

// MARK: - 界面大小（#7）

private struct ScaleOption: Identifiable, Equatable {
    let id: Double
    let scale: Double
    let percent: String
    let desc: String

    init(scale: Double, percent: String, desc: String) {
        self.id = scale
        self.scale = scale
        self.percent = percent
        self.desc = desc
    }
}

/// 整体等比缩放 App 画面：通过窗口 transform 实现，缩小后一页可显示更多内容。
/// 选项即时生效并持久化到 AppSettings.uiScale，App 启动时会按保存值恢复。
struct UIScalePage: View {
    @State private var settings: AppSettings = SharedStore.loadSettings()

    private let options: [ScaleOption] = [
        ScaleOption(scale: 1.0,  percent: "100%", desc: "原始大小"),
        ScaleOption(scale: 0.95, percent: "95%",  desc: "略微紧凑"),
        ScaleOption(scale: 0.9,  percent: "90%",  desc: "紧凑"),
        ScaleOption(scale: 0.85, percent: "85%",  desc: "更紧凑"),
        ScaleOption(scale: 0.8,  percent: "80%",  desc: "最紧凑")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(options) { opt in
                    Button {
                        select(opt.scale)
                    } label: {
                        HStack(spacing: 12) {
                            Text(opt.percent)
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Text(opt.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.muted)
                            Spacer()
                            if abs(settings.uiScale - opt.scale) < 0.001 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WebTheme.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("界面大小 \(opt.percent) \(opt.desc)")
                }
            } header: {
                Text("界面大小")
            } footer: {
                Text("缩小整体界面可在一页内显示更多内容。修改后立即生效，重启 App 后按保存值自动恢复。极端缩放下部分控件可能略小，可随时调回 100%。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("界面大小")
    }

    private func select(_ scale: Double) {
        guard abs(settings.uiScale - scale) > 0.001 else { return }
        settings.uiScale = scale
        SharedStore.saveSettings(settings)
        applyUIScale(CGFloat(scale))
    }
}

// MARK: - 手机信息（#8）

/// 展示机型、系统、架构、屏幕、存储等硬件信息，并尽力识别安装环境
///（App Store / TestFlight / 企业签名 / 开发者·Ad-hoc / 巨魔 TrollStore / 免签）。
struct DeviceInfoPage: View {
    private let info = DeviceInfo.snapshot()

    var body: some View {
        ZStack {
            WebConsoleBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SectionCard(title: "设备") {
                        infoRow("机型", info.model)
                        divider
                        infoRow("系统", info.system)
                        divider
                        infoRow("架构", info.architecture)
                        divider
                        infoRow("处理器", info.processor)
                    }
                    SectionCard(title: "屏幕") {
                        infoRow("逻辑分辨率", info.screenPoints)
                        divider
                        infoRow("缩放倍率", info.screenScale)
                        divider
                        infoRow("物理像素", info.screenPixels)
                    }
                    SectionCard(title: "存储") {
                        infoRow("可用 / 总量", info.storage)
                    }
                    SectionCard(title: "安装环境") {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(envColor(info.installEnvironment).opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(envColor(info.installEnvironment))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.installEnvironment)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .foregroundStyle(WebTheme.txt)
                                Text(info.installEnvironmentHint)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(WebTheme.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("以上信息仅在本机展示，不会上传服务器。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .hideScrollBackground()
        .inlineTitle("手机信息")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(WebTheme.txt)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    private var divider: some View {
        Rectangle().fill(WebTheme.border.opacity(0.5)).frame(height: 0.5)
    }

    private func envColor(_ env: String) -> Color {
        if env.contains("App Store") { return WebTheme.green }
        if env.contains("TestFlight") { return WebTheme.blue }
        if env.contains("企业") { return WebTheme.purple }
        if env.contains("巨魔") { return WebTheme.amber }
        if env.contains("开发者") || env.contains("Ad-hoc") { return WebTheme.blue }
        return WebTheme.muted
    }
}

// MARK: - 设备信息采集

struct DeviceInfo {
    let model: String
    let system: String
    let architecture: String
    let processor: String
    let screenPoints: String
    let screenScale: String
    let screenPixels: String
    let storage: String
    let installEnvironment: String
    let installEnvironmentHint: String

    static func snapshot() -> DeviceInfo {
        let env = detectInstallEnvironment()
        return DeviceInfo(
            model: modelName,
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            architecture: archString,
            processor: "\(ProcessInfo.processInfo.processorCount) 核",
            screenPoints: screenPointString,
            screenScale: "@\(Int(UIScreen.main.scale))x",
            screenPixels: screenPixelString,
            storage: storageString,
            installEnvironment: env.name,
            installEnvironmentHint: env.hint
        )
    }

    // MARK: 机型识别

    static var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        // Mirror 逐字节读取 machine 元组（CChar 数组）拼字符串，纯 Swift、无指针、
        // 无 inout 独占访问，避免 iOS 26 SDK 的 overlapping accesses 编译报错。
        let mirror = Mirror(reflecting: systemInfo.machine)
        var bytes: [UInt8] = []
        for child in mirror.children {
            guard let byte = child.value as? Int8, byte != 0 else { break }
            bytes.append(UInt8(byte))
        }
        let identifier = String(decoding: bytes, as: UTF8.self)
        return modelMap[identifier] ?? (identifier.isEmpty ? "iPhone" : identifier)
    }

    private static let modelMap: [String: String] = [
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone18,1": "iPhone 16e",
        "iPhone18,2": "iPhone 17 Pro",
        "iPhone18,3": "iPhone 17 Pro Max",
        "iPhone18,4": "iPhone 17",
        "iPad13,1": "iPad Air (4th)",
        "iPad13,2": "iPad Air (4th)",
        "iPad14,3": "iPad Air (5th)",
        "iPad13,8": "iPad Pro 12.9 (5th)",
        "iPad13,9": "iPad Pro 12.9 (5th)",
        "iPad14,5": "iPad Pro 12.9 (6th)",
        "x86_64": "Simulator",
        "arm64": "Simulator"
    ]

    // MARK: 架构

    private static var archString: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }

    // MARK: 屏幕

    private static var screenPointString: String {
        let b = UIScreen.main.bounds
        return "\(Int(b.width)) × \(Int(b.height))"
    }

    private static var screenPixelString: String {
        let b = UIScreen.main.bounds
        let s = UIScreen.main.scale
        return "\(Int(b.width * s)) × \(Int(b.height * s))"
    }

    // MARK: 存储

    private static var storageString: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) else { return "--" }
        guard let total = values.volumeTotalCapacity,
              let avail = values.volumeAvailableCapacityForImportantUsage else { return "--" }
        return "\(gb(avail)) / \(gb(Int64(total))) GB"
    }

    private static func gb(_ bytes: Int64) -> Int {
        max(0, Int(bytes / 1_073_741_824))
    }

    // MARK: 安装环境识别

    private static func detectInstallEnvironment() -> (name: String, hint: String) {
        // 1. 巨魔 TrollStore：环境变量或安装路径特征
        if ProcessInfo.processInfo.environment["TROLLSTORE"] != nil ||
            (Bundle.main.executablePath ?? "").contains("/trollstore/") {
            return ("巨魔 TrollStore", "通过 TrollStore 永久签安装，重启不失效，无需电脑重签。")
        }
        // 2. TestFlight：沙箱收据
        if let receipt = Bundle.main.appStoreReceiptURL,
           receipt.lastPathComponent == "sandboxReceipt" {
            return ("TestFlight 测试版", "通过苹果 TestFlight 分发，90 天有效期，到期需重新安装。")
        }
        // 3. 内嵌描述文件（开发者 / Ad-hoc / 企业）
        if let provPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let data = FileManager.default.contents(atPath: provPath),
           let ascii = String(data: data, encoding: .ascii) {
            if ascii.contains("ProvisionsAllDevices") {
                return ("企业签名 (In-House)", "企业证书分发，安装数量不限，证书吊销后无法打开。")
            }
            return ("开发者 / Ad-hoc 签名", "开发或 Ad-hoc 描述文件安装，设备需登记，证书 1 年有效。")
        }
        // 4. App Store 正式版
        if Bundle.main.appStoreReceiptURL != nil {
            return ("App Store 商店", "通过苹果 App Store 正式下载安装。")
        }
        // 5. 兜底：无收据也无描述文件（免签 / 越狱环境）
        return ("免签 / 无签名环境", "未检测到标准签名信息，可能为免签或越狱环境安装。")
    }
}

// MARK: - 日期格式助手

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
