import WidgetKit
import SwiftUI
import AppIntents
import CarCore

// MARK: - 小组件入口（按家族分发）

struct CakocheStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CakocheStatusWidget", provider: CakocheWidgetProvider()) { entry in
            CakocheWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CAKOCHE 控车")
        .description("点阵车况 + 自定义控车按钮，与 CAKOCHE App 同一套白名单授权")
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
            WidgetDotCnText(text: text, size: 7.5, color: alarm ? WMono.red : WMono.dim)
        }
    }
}

/// 执行反馈横幅（优先「再点一次确认」，其次执行结果）
private struct FeedbackBanner: View {
    var body: some View {
        if let pending = CakocheWidgetRunner.pendingCommand() {
            HStack(spacing: 4) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 8, weight: .bold))
                WidgetDotCnText(text: pending.displayName + " · 再点一次确认", size: 7.5, color: WMono.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let action = CakocheWidgetRunner.lastAction() {
            HStack(spacing: 4) {
                Image(systemName: action.ok ? "checkmark" : "xmark")
                    .font(.system(size: 8, weight: .bold))
                WidgetDotCnText(text: action.text, size: 7.5,
                                color: action.ok ? WMono.ink : WMono.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 5 个自定义控车按钮（App「我的 → 小组件按钮」配置）
private struct ControlButtonRow: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                slotButton(index)
            }
        }
    }

    @ViewBuilder
    private func slotButton(_ index: Int) -> some View {
        let commands = CakocheWidgetRunner.resolvedCommands()
        let command = commands.indices.contains(index) ? commands[index] : nil
        let pending = CakocheWidgetRunner.pendingCommand()?.rawValue == command?.rawValue
        let label = command?.displayName ?? "未设"
        Group {
            switch index {
            case 0: buttonBody(command, intent: CakocheSlot1Intent(), pending: pending, label: label)
            case 1: buttonBody(command, intent: CakocheSlot2Intent(), pending: pending, label: label)
            case 2: buttonBody(command, intent: CakocheSlot3Intent(), pending: pending, label: label)
            case 3: buttonBody(command, intent: CakocheSlot4Intent(), pending: pending, label: label)
            default: buttonBody(command, intent: CakocheSlot5Intent(), pending: pending, label: label)
            }
        }
    }

    private func buttonBody(_ command: CarCommand?, intent: some AppIntent,
                            pending: Bool, label: String) -> some View {
        cakocheWidgetButton(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: command?.sfSymbol ?? "questionmark")
                    .font(.system(size: 13, weight: .semibold))
                WidgetDotCnText(text: pending ? "再点一次" : label, size: 6.5,
                                color: pending ? WMono.red : WMono.ink)
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
        .accessibilityLabel(pending ? "待确认，再点一次执行\(label)" : label)
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
            WidgetDotCnText(text: isLoggedIn ? "暂无车况数据" : "未登录", size: 9, color: WMono.ink)
            WidgetDotCnText(text: "打开 CAKOCHE App 自动同步车况", size: 7, color: WMono.dim)
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
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 24, color: WMono.ink)
                    WidgetDotCnText(text: "剩余续航 · 油 \(CarStatus.format(s.fuelLeftLiters)) L",
                                    size: 7, color: WMono.dim)
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

// MARK: - 中号：状态 + 点阵续航 + 5 按钮

private struct MediumStatus: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 7) {
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
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 26, color: WMono.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetDotCnText(text: "剩余续航", size: 7, color: WMono.dim)
                        WidgetDotCnText(text: "油 \(CarStatus.format(s.fuelLeftLiters)) L · \(CarStatus.format(s.batteryVoltage)) V",
                                        size: 7, color: WMono.dim)
                    }
                    Spacer()
                }
                FeedbackBanner()
                ControlButtonRow()
            }
            .padding(12)
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            NoData(isLoggedIn: entry.isLoggedIn)
        }
    }
}

// MARK: - 大号：状态 + 点阵续航 + 胎压 + 5 按钮

private struct LargeStatus: View {
    let entry: CakocheWidgetEntry

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 9) {
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
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 30, color: WMono.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetDotCnText(text: "剩余续航 KM", size: 7, color: WMono.dim)
                        WidgetDotCnText(text: "油 \(CarStatus.format(s.fuelLeftLiters)) L · \(CarStatus.format(s.batteryVoltage)) V",
                                        size: 7, color: WMono.dim)
                    }
                    Spacer()
                }
                // 胎压四轮
                let names = ["左前", "右前", "左后", "右后"]
                HStack(spacing: 6) {
                    ForEach(Array(s.tirePressures.enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 3) {
                            WidgetDotCnText(text: index < names.count ? names[index] : "轮胎",
                                            size: 6.5, color: WMono.dim)
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
                ControlButtonRow()
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

/// 锁屏圆形：大锁钮，点按智能反向开关锁（点按后需二次确认）
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
                    WidgetDotText(text: CarStatus.format(s.remainingRangeKm), size: 14, color: WMono.ink)
                        .widgetAccentable()
                    Text("KM 续航 · 油 \(CarStatus.format(s.fuelLeftLiters)) L")
                        .font(.system(size: 8))
                        .foregroundStyle(WMono.dim)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .widgetURL(URL(string: "cakoche://home"))
        } else {
            WidgetDotCnText(text: "打开 CAKOCHE App 登录", size: 8, color: WMono.ink)
                .widgetAccentable()
                .widgetURL(URL(string: "cakoche://home"))
        }
    }
}
