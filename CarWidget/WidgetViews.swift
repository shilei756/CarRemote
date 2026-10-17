import WidgetKit
import SwiftUI
import AppIntents
import CarCore

/// 各尺寸小组件视图：实车图 + 状态 + 5 个自定义控车按钮
struct CarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CarStatusEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - 公共元素

private struct LockBadge: View {
    let isUnlocked: Bool
    var body: some View {
        Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.caption2.bold())
            .foregroundStyle(isUnlocked ? Color.orange : Color.green)
            .accessibilityLabel(isUnlocked ? "已解锁" : "已锁止")
    }
}

/// 5 个自定义控车按钮（App 内可改：设置 → 小组件按钮）
private struct QuickControlButtons: View {
    let commands: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                let command = commands.indices.contains(index) ? CarCommand(rawValue: commands[index]) : nil
                slotButton(index, command: command)
            }
        }
    }

    @ViewBuilder
    private func slotButton(_ index: Int, command: CarCommand?) -> some View {
        switch index {
        case 0: slotButtonBody(command, intent: WidgetSlot1Intent())
        case 1: slotButtonBody(command, intent: WidgetSlot2Intent())
        case 2: slotButtonBody(command, intent: WidgetSlot3Intent())
        case 3: slotButtonBody(command, intent: WidgetSlot4Intent())
        default: slotButtonBody(command, intent: WidgetSlot5Intent())
        }
    }

    private func slotButtonBody<I: AppIntent>(_ command: CarCommand?, intent: I) -> some View {
        Button(intent: intent) {
            VStack(spacing: 3) {
                Image(systemName: command?.sfSymbol ?? "questionmark")
                    .font(.system(size: 13, weight: .semibold))
                Text(command?.displayName ?? "未设")
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(buttonTint(command).opacity(0.16))
            .foregroundStyle(buttonTint(command))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func buttonTint(_ command: CarCommand?) -> Color {
        switch command {
        case .flashLight: return .blue
        case .unlockDoor: return .orange
        case .lockDoor: return .green
        case .whistle: return .purple
        case .remoteSearchCar: return .cyan
        case .openEngine: return .red
        case .closeEngine: return .gray
        case .openAir: return .teal
        case .closeAir: return .indigo
        default: return .blue
        }
    }
}

/// 实车图（跟随 App 里选的车型）
private struct WidgetCarImage: View {
    let style: CarModelStyle
    let isUnlocked: Bool

    private var imageName: String {
        switch style {
        case .sedan: return "car_yidong"
        case .coupe: return "car_univ"
        case .suv: return "car_cs75plus"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel(isUnlocked ? "车辆图片，已解锁" : "车辆图片，已锁止")
    }
}

/// 状态徽章（绿色车辆正常 / 橙色已开锁 / 红色发动机…）
private struct StateBadge: View {
    let summaryText: String
    let level: String

    init(snapshot: StatusSnapshot) {
        self.summaryText = snapshot.summaryText
        self.level = snapshot.level
    }

    var body: some View {
        let (text, color): (String, Color) = {
            switch level {
            case "door": return ("已开锁", Color.orange)
            case "engine": return ("发动机运行", Color.red)
            case "win": return ("车窗未关", Color.blue)
            default: return ("车辆正常", Color.green)
            }
        }()
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private func relativeTimeText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.localizedString(for: date, relativeTo: Date())
}

private struct NoDataView: View {
    var isLoggedIn: Bool
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.circle")
                .font(.system(size: compact ? 28 : 40))
                .foregroundStyle(.secondary)
            Text(isLoggedIn ? "暂无车况数据" : "未登录")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
            Text(isLoggedIn ? "等待刷新，或打开 App 下拉刷新" : "打开 App 登录后自动同步")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 小号

struct SmallWidgetView: View {
    let entry: CarStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.carName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    LockBadge(isUnlocked: snapshot.doorUnlocked)
                }
                WidgetCarImage(style: entry.carStyle, isUnlocked: snapshot.doorUnlocked)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    Label("\(CarStatus.format(snapshot.remainingRangeKm))km", systemImage: "road.lanes")
                    Label("\(CarStatus.format(snapshot.fuelLeftLiters))L", systemImage: "fuelpump.fill")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(relativeTimeText(snapshot.updatedAt))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView(isLoggedIn: entry.isLoggedIn, compact: true)
        }
    }
}

// MARK: - 中号（主力布局：实车图 + 状态 + 5 按钮）

struct MediumWidgetView: View {
    let entry: CarStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(snapshot.carName)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            StateBadge(snapshot: snapshot)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(CarStatus.format(snapshot.remainingRangeKm))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .widgetAccentable()
                            Text("km 续航")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text("油量 \(CarStatus.format(snapshot.fuelLeftLiters)) L · 里程 \(CarStatus.format(snapshot.totalOdometerKm)) km · 电压 \(CarStatus.format(snapshot.batteryVoltage)) V")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("更新于 \(relativeTimeText(snapshot.updatedAt))")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    WidgetCarImage(style: entry.carStyle, isUnlocked: snapshot.doorUnlocked)
                        .frame(height: 74)
                }
                QuickControlButtons(commands: entry.widgetCommands)
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView(isLoggedIn: entry.isLoggedIn)
        }
    }
}

// MARK: - 大号

struct LargeWidgetView: View {
    let entry: CarStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(snapshot.carName)
                        .font(.title3.bold())
                    StateBadge(snapshot: snapshot)
                    Spacer()
                    LockBadge(isUnlocked: snapshot.doorUnlocked)
                    Text(relativeTimeText(snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CarStatus.format(snapshot.remainingRangeKm))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .widgetAccentable()
                            Text("km 续航")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("油量 \(CarStatus.format(snapshot.fuelLeftLiters)) L · 电压 \(CarStatus.format(snapshot.batteryVoltage)) V")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    WidgetCarImage(style: entry.carStyle, isUnlocked: snapshot.doorUnlocked)
                        .frame(height: 84)
                }

                // 胎压四轮
                let pressures = snapshot.tirePressures
                HStack(spacing: 8) {
                    ForEach(Array(pressures.enumerated()), id: \.offset) { index, value in
                        let names = ["左前", "右前", "左后", "右后"]
                        let name = index < names.count ? names[index] : "轮胎"
                        VStack(spacing: 2) {
                            Text(name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(CarStatus.format(value))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(isLowPressure(value) ? Color.red : Color.primary)
                            Text("kPa")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                Spacer(minLength: 0)
                QuickControlButtons(commands: entry.widgetCommands)
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView(isLoggedIn: entry.isLoggedIn)
        }
    }

    private func isLowPressure(_ value: Double?) -> Bool {
        guard let value, value > 0 else { return false }
        return value < 220
    }
}

// MARK: - 锁屏（圆形）

struct AccessoryCircularView: View {
    let entry: CarStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot, let range = snapshot.remainingRangeKm {
            Gauge(value: min(max(range / 600, 0), 1)) {
                Image(systemName: snapshot.doorUnlocked ? "lock.open.fill" : "lock.fill")
            } currentValueLabel: {
                Text("\(CarStatus.format(range))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "car.circle.fill")
                    .font(.title3)
            }
        }
    }
}

// MARK: - 锁屏（矩形）

struct AccessoryRectangularView: View {
    let entry: CarStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(snapshot.carName)
                        .font(.headline)
                        .widgetAccentable()
                    Spacer()
                    Image(systemName: snapshot.doorUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.caption)
                        .widgetAccentable()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("续航")
                        .font(.caption)
                    Text(CarStatus.format(snapshot.remainingRangeKm))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("km")
                        .font(.caption2)
                    Spacer()
                    Text("油 \(CarStatus.format(snapshot.fuelLeftLiters)) L")
                        .font(.caption)
                }
                Text(snapshot.summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label(entry.isLoggedIn ? "打开 App 查看车况" : "打开 App 登录", systemImage: "car.circle")
                .font(.caption)
                .widgetAccentable()
        }
    }
}
