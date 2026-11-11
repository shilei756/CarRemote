import WidgetKit
import SwiftUI
import CarCore

// MARK: - 小组件入口（按家族分发）

struct CakocheStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CakocheStatusWidget", provider: CakocheWidgetProvider()) { entry in
            CakocheWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CAKOCHE 控车")
        .description("点阵车况 + 一键控车，与 CAKOCHE App 同一套白名单授权")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

struct CakocheWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CakocheWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallStatus(entry: entry)
            case .systemMedium: MediumStatus(entry: entry)
            case .systemLarge: LargeStatus(entry: entry)
            case .accessoryRectangular: LockRectangular(entry: entry)
            default: LockCircular(entry: entry)
            }
        }
        .widgetBackground()
    }
}

// 小组件容器背景：iOS 17 要求用 containerBackground 修饰，iOS 16 直接给底色
extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { Color(white: 0.045) }
        } else {
            background(Color(white: 0.045))
        }
    }
}

// MARK: - 公共元素

/// 状态文字徽标：红 = 有异常项，白 = 正常
private struct StateBadge: View {
    let text: String
    let alarm: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(alarm ? WMono.red : WMono.ink).frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(alarm ? WMono.red : WMono.dim)
        }
    }
}

/// 执行反馈横幅（优先「再点一次确认」，其次绿✓/红✗）
private struct FeedbackBanner: View {
    var body: some View {
        if let pending = CakocheWidgetRunner.pendingCommand() {
            banner(text: pending.displayName + " · 再点一次确认", color: WMono.red)
        } else if let action = CakocheWidgetRunner.lastAction() {
            HStack(spacing: 4) {
                Image(systemName: action.ok ? "checkmark" : "xmark")
                    .font(.system(size: 8, weight: .bold))
                Text(action.text)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(action.ok ? WMono.ink : WMono.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.tap")
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 快捷控车按钮排（黑底白图标红确认，点阵风格的克制表达）
private struct ControlButtonRow: View {
    let unlocked: Bool
    let engineOn: Bool
    var columns: Int

    var body: some View {
        HStack(spacing: 5) {
            button(icon: unlocked ? "lock.open.fill" : "lock.fill",
                   text: unlocked ? "闭锁" : "开锁",
                   intent: CakocheLockToggleIntent(),
                   pending: pendingText == (unlocked ? "闭锁" : "开锁"))
            if columns >= 3 {
                button(icon: engineOn ? "engine.combustion.fill" : "engine.combustion",
                       text: engineOn ? "熄火" : "点火",
                       intent: CakocheEngineToggleIntent(),
                       pending: pendingText == (engineOn ? "熄火" : "点火"))
            }
            if columns >= 4 {
                button(icon: "light.beacon.max", text: "寻车",
                       intent: CakocheWhistleIntent(), pending: false)
            }
            if columns >= 5 {
                button(icon: "hourglass", text: "闪灯",
                       intent: CakocheFlashIntent(), pending: false)
            }
        }
    }

    private var pendingText: String? {
        CakocheWidgetRunner.pendingCommand()?.displayName
    }

    private func button(icon: String, text: String,
                        intent: some AppIntent, pending: Bool) -> some View {
        cakocheWidgetButton(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(pending ? "再点一次" : text)
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(pending ? WMono.red : WMono.ink)
            .background(pending ? WMono.red.opacity(0.16) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(pending ? WMono.red : WMono.hair, lineWidth: pending ? 1.2 : 0.5)
            )
        }
        .accessibilityLabel(pending ? "待确认，再点一次执行\(text)" : text)
    }
}

/// 无数据占位
private struct NoData: View {
    let isLoggedIn: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "car")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(WMono.dim)
            Text(isLoggedIn ? "暂无车况数据" : "未登录")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WMono.ink)
            Text("打开 CAKOCHE App 自动同步车况")
                .font(.system(size: 9))
                .foregroundStyle(WMono.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 相对时间
private func relativeTime(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    f.locale = Locale(identifier: "zh_CN")
    return f.localizedString(for: date, relativeTo: Date())
}

// MARK: - 小号：车名 + 点阵续航 + 锁态

private struct SmallStatus: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(s.carName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(WMono.ink)
                    Spacer()
                    Image(systemName: s.doorUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(s.doorUnlocked ? WMono.red : WMono.dim)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 26, color: WMono.ink)
                    HStack(spacing: 6) {
                        Text("剩余续航")
                            .font(.system(size: 8.5))
                            .foregroundStyle(WMono.dim)
                        Text("油 \(CarStatus.format(s.fuelLeftLiters)) L")
                            .font(.system(size: 8.5))
                            .foregroundStyle(WMono.dim)
                    }
                }
                Spacer(minLength: 0)
                Text(relativeTime(s.updatedAt))
                    .font(.system(size: 7.5))
                    .foregroundStyle(WMono.dim)
            }
            .padding(12)
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            NoData(isLoggedIn: entry.isLoggedIn)
        }
    }
}

// MARK: - 中号：状态 + 四按钮

private struct MediumStatus: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(s.carName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(WMono.ink)
                    StateBadge(text: s.summaryText,
                               alarm: s.doorUnlocked || s.windowOpen || s.engineRunning)
                    Spacer()
                    Text(relativeTime(s.updatedAt))
                        .font(.system(size: 7.5))
                        .foregroundStyle(WMono.dim)
                }
                HStack(alignment: .center, spacing: 12) {
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 30, color: WMono.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("剩余续航")
                            .font(.system(size: 8.5))
                            .foregroundStyle(WMono.dim)
                        Text("油量 \(CarStatus.format(s.fuelLeftLiters)) L · 电压 \(CarStatus.format(s.batteryVoltage)) V")
                            .font(.system(size: 8.5).monospacedDigit())
                            .foregroundStyle(WMono.dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                }
                FeedbackBanner()
                ControlButtonRow(unlocked: s.doorUnlocked, engineOn: s.engineRunning, columns: 4)
            }
            .padding(12)
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            NoData(isLoggedIn: entry.isLoggedIn)
        }
    }
}

// MARK: - 大号：状态 + 胎压 + 四按钮

private struct LargeStatus: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(s.carName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(WMono.ink)
                    StateBadge(text: s.summaryText,
                               alarm: s.doorUnlocked || s.windowOpen || s.engineRunning)
                    Spacer()
                    Text(relativeTime(s.updatedAt))
                        .font(.system(size: 7.5))
                        .foregroundStyle(WMono.dim)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 34, color: WMono.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("剩余续航 KM")
                            .font(.system(size: 8.5))
                            .foregroundStyle(WMono.dim)
                        Text("油量 \(CarStatus.format(s.fuelLeftLiters)) L · 电压 \(CarStatus.format(s.batteryVoltage)) V")
                            .font(.system(size: 8.5).monospacedDigit())
                            .foregroundStyle(WMono.dim)
                    }
                    Spacer()
                }
                // 胎压四轮
                let names = ["左前", "右前", "左后", "右后"]
                HStack(spacing: 6) {
                    ForEach(Array(s.tirePressures.enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 3) {
                            Text(index < names.count ? names[index] : "轮胎")
                                .font(.system(size: 8))
                                .foregroundStyle(WMono.dim)
                            Text(CarStatus.format(value))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(isLow(value) ? WMono.red : WMono.ink)
                            Text("kPa")
                                .font(.system(size: 7))
                                .foregroundStyle(WMono.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                FeedbackBanner()
                Spacer(minLength: 0)
                ControlButtonRow(unlocked: s.doorUnlocked, engineOn: s.engineRunning, columns: 4)
            }
            .padding(14)
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            NoData(isLoggedIn: entry.isLoggedIn)
        }
    }

    private func isLow(_ value: Double?) -> Bool {
        guard let value, value > 0 else { return false }
        return value < 220
    }
}

// MARK: - 锁屏配件

/// 锁屏圆形：大锁钮，点按智能反向开关锁
private struct LockCircular: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        let unlocked = entry.snapshot?.doorUnlocked ?? false
        let pending = CakocheWidgetRunner.pendingCommand() != nil
        ZStack {
            AccessoryWidgetBackground()
            cakocheWidgetButton(intent: CakocheLockToggleIntent()) {
                VStack(spacing: 1) {
                    Image(systemName: pending ? "hand.tap.fill" : (unlocked ? "lock.open.fill" : "lock.fill"))
                        .font(.system(size: 18, weight: .bold))
                    Text(pending ? "再点一次" : (unlocked ? "闭锁" : "开锁"))
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(pending ? Color.orange : (unlocked ? Color.orange : Color.green))
            }
        }
        .accessibilityLabel(pending ? "待确认，再点一次执行" : (unlocked ? "当前已开锁，点按闭锁" : "当前已锁止，点按开锁"))
    }
}

/// 锁屏矩形：车名 + 点阵续航 + 开关锁
private struct LockRectangular: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(s.carName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                        .foregroundStyle(WMono.ink)
                    Spacer()
                    cakocheWidgetButton(intent: CakocheLockToggleIntent()) {
                        Image(systemName: s.doorUnlocked ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(s.doorUnlocked ? Color.orange : Color.green)
                    }
                    .accessibilityLabel(s.doorUnlocked ? "已开锁，点按闭锁" : "已锁止，点按开锁")
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 15, color: WMono.ink)
                        .widgetAccentable()
                    Text("KM 续航")
                        .font(.system(size: 8))
                        .foregroundStyle(WMono.dim)
                    Spacer()
                    Text("油 \(CarStatus.format(s.fuelLeftLiters)) L")
                        .font(.system(size: 8.5))
                        .foregroundStyle(WMono.dim)
                }
            }
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            Text("打开 CAKOCHE App 登录")
                .font(.system(size: 11, weight: .medium))
                .widgetAccentable()
                .widgetURL(URL(string: "cakoche://home"))
        }
    }
}
