import WidgetKit
import SwiftUI
import AppIntents
import CarCore

/// 各尺寸小组件视图
struct CarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CarStatusEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeWidgetView(snapshot: entry.snapshot)
        case .accessoryCircular:
            AccessoryCircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            AccessoryRectangularView(snapshot: entry.snapshot)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - 公共元素

/// 锁态徽标
private struct LockBadge: View {
    let isUnlocked: Bool
    var body: some View {
        Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.caption2.bold())
            .foregroundStyle(isUnlocked ? Color.orange : Color.green)
            .accessibilityLabel(isUnlocked ? "已解锁" : "已锁止")
    }
}

/// 小组件底部快捷按钮（iOS 17+ 交互式按钮，点按直接执行不打开 App）
private struct QuickControlButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            widgetButton(intent: FlashLightsIntent(), title: "闪灯", symbol: "light.beacon.max.fill", tint: .blue)
            widgetButton(intent: UnlockCarIntent(), title: "开锁", symbol: "lock.open.fill", tint: .orange)
            widgetButton(intent: LockCarIntent(), title: "闭锁", symbol: "lock.fill", tint: .green)
            widgetButton(intent: HonkHornIntent(), title: "鸣笛", symbol: "speaker.wave.2.fill", tint: .purple)
        }
    }

    private func widgetButton<I: AppIntent>(intent: I, title: String, symbol: String, tint: Color) -> some View {
        Button(intent: intent) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 无数据占位
private struct NoDataView: View {
    var compact = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.circle")
                .font(.system(size: compact ? 28 : 40))
                .foregroundStyle(.secondary)
            Text(compact ? "打开 App 查看车况" : "暂无车况数据")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
            Text("登录后自动刷新")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 相对时间文本
private func relativeTimeText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - 小号（主屏）

struct SmallWidgetView: View {
    let snapshot: StatusSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot.carName)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    LockBadge(isUnlocked: snapshot.doorUnlocked)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(CarStatus.format(snapshot.remainingRangeKm))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .widgetAccentable()
                    Text("剩余续航 km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(CarStatus.format(snapshot.fuelLeftLiters)) L", systemImage: "fuelpump.fill")
                    Label("\(CarStatus.format(snapshot.totalOdometerKm)) km", systemImage: "speedometer")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                QuickControlButtons()
                Text(relativeTimeText(snapshot.updatedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView(compact: true)
        }
    }
}

// MARK: - 中号（主屏）

struct MediumWidgetView: View {
    let snapshot: StatusSnapshot?

    var body: some View {
        if let snapshot {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(snapshot.carName)
                                .font(.headline)
                            LockBadge(isUnlocked: snapshot.doorUnlocked)
                        }
                        Text(snapshot.summaryText)
                            .font(.caption)
                            .foregroundStyle(stateColor(level: snapshot.level))
                        Text("更新于 \(relativeTimeText(snapshot.updatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CarStatus.format(snapshot.remainingRangeKm))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .widgetAccentable()
                            Text("km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("油量 \(CarStatus.format(snapshot.fuelLeftLiters)) L · 电压 \(CarStatus.format(snapshot.batteryVoltage)) V")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                QuickControlButtons()
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView()
        }
    }

    private func stateColor(level: String) -> Color {
        switch level {
        case "door": return .orange
        case "win": return .blue
        case "engine": return .red
        default: return .green
        }
    }
}

// MARK: - 大号（主屏）

struct LargeWidgetView: View {
    let snapshot: StatusSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(snapshot.carName)
                        .font(.title3.bold())
                    Spacer()
                    LockBadge(isUnlocked: snapshot.doorUnlocked)
                    Text(relativeTimeText(snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    WidgetStat(title: "续航", value: CarStatus.format(snapshot.remainingRangeKm), unit: "km", symbol: "road.lanes", tint: .green)
                    WidgetStat(title: "油量", value: CarStatus.format(snapshot.fuelLeftLiters), unit: "L", symbol: "fuelpump", tint: .orange)
                    WidgetStat(title: "总里程", value: CarStatus.format(snapshot.totalOdometerKm), unit: "km", symbol: "speedometer", tint: .blue)
                    WidgetStat(title: "电压", value: CarStatus.format(snapshot.batteryVoltage), unit: "V", symbol: "bolt.fill", tint: .yellow)
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
                                .foregroundStyle(isLowPressure(value) ? .red : .primary)
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

                Text(snapshot.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
                QuickControlButtons()
            }
            .widgetURL(URL(string: APIConfig.urlScheme + "://dashboard"))
        } else {
            NoDataView()
        }
    }

    private func isLowPressure(_ value: Double?) -> Bool {
        guard let value, value > 0 else { return false }
        return value < 220
    }
}

/// 大号小组件数值格
private struct WidgetStat: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 锁屏（圆形）

struct AccessoryCircularView: View {
    let snapshot: StatusSnapshot?

    var body: some View {
        if let snapshot, let range = snapshot.remainingRangeKm {
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
    let snapshot: StatusSnapshot?

    var body: some View {
        if let snapshot {
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
            Label("打开 App 查看车况", systemImage: "car.circle")
                .font(.caption)
                .widgetAccentable()
        }
    }
}
