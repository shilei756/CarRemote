import SwiftUI
import CarCore

/// ID.CONTROL「车库」页：车辆卡（模糊车图 + 演示车辆）+ 设置列表（车辆连接 / 数字钥匙 / 行程统计 / 燃油 / 位置 / 健康 / 消息 / 设置 / 应用信息）。
struct GarageView: View {
    @EnvironmentObject private var appState: AppState
    private var settings: AppSettings { SharedStore.loadSettings() }

    @State private var presented: GarageDestination? = nil

    var body: some View {
        ZStack {
            WebConsoleBackground()
            ScrollView {
                VStack(spacing: 12) {
                    // 顶部栏：左设置 · 中「车库」点阵标题 · 右刷新
                    HStack(spacing: 12) {
                        circleButton(icon: "slider.horizontal.3") { }
                        Spacer()
                        Text("车库")
                            .font(Font.webLedFont(size: 20))
                            .foregroundStyle(WebTheme.txt)
                        Spacer()
                        circleButton(icon: "antenna.radiowaves.left.and.right") {
                            Task { await appState.refreshStatus() }
                        }
                        .disabled(appState.isRefreshing)
                    }
                    .padding(.top, 6)

                    vehicleCard
                    settingsListCard
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .sheet(item: $presented) { dest in
            destinationView(for: dest)
                .environmentObject(appState)
                .environmentObject(ThemeManager.shared)
        }
    }

    // MARK: 车辆卡

    private var vehicleCard: some View {
        ZStack {
            Image(settings.carModelStyle.sideImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 140)
                .clipped()
                .blur(radius: 14)
                .opacity(0.45)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appState.carName.isEmpty ? "我的爱车" : appState.carName)
                        .font(Font.webLedFont(size: 22))
                        .foregroundStyle(WebTheme.txt)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(WebTheme.blue)
                        .font(.system(size: 20))
                }
                Text("演示车辆")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.faint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                .strokeBorder(WebTheme.border, lineWidth: 1)
        )
    }

    // MARK: 设置列表

    private var settingsListCard: some View {
        VStack(spacing: 0) {
            ForEach(GarageDestination.allCases) { dest in
                Button {
                    presented = dest
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: dest.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WebTheme.muted)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dest.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WebTheme.txt)
                            Text(dest.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.faint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WebTheme.faint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if dest != GarageDestination.allCases.last {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                .strokeBorder(WebTheme.border, lineWidth: 1)
        )
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .strokeBorder(WebTheme.border, lineWidth: 1)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("按钮")
    }

    @ViewBuilder
    private func destinationView(for dest: GarageDestination) -> some View {
        switch dest {
        case .trips:
            VehicleStatusPage()
        case .fuel:
            FuelTrackerView(appState: appState)
        case .appearance:
            CarModelGalleryView()
        case .settings:
            SettingsView()
        default:
            DemoSheetView(title: dest.title)
        }
    }
}

/// 车库列表条目（对应 ID. CONTROL 设置列表）
enum GarageDestination: String, CaseIterable, Identifiable {
    case vehicleConnection, digitalKey, trips, fuel, location, health, messages, appearance, settings, appInfo

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vehicleConnection: return "antenna.radiowaves.left.and.right"
        case .digitalKey: return "key.fill"
        case .trips: return "chart.bar.xaxis"
        case .fuel: return "fuelpump.fill"
        case .location: return "location.fill"
        case .health: return "heart.text.square.fill"
        case .messages: return "bell.fill"
        case .appearance: return "view.3d"
        case .settings: return "gearshape.fill"
        case .appInfo: return "info.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .vehicleConnection: return "车辆连接"
        case .digitalKey: return "数字钥匙"
        case .trips: return "行程统计"
        case .fuel: return "燃油"
        case .location: return "车辆位置"
        case .health: return "健康报告"
        case .messages: return "消息中心"
        case .appearance: return "外观"
        case .settings: return "设置"
        case .appInfo: return "应用信息"
        }
    }

    var subtitle: String {
        switch self {
        case .vehicleConnection: return "大众账号"
        case .digitalKey: return "服务与连接"
        case .trips: return "行程记录与详情"
        case .fuel: return "油量 · 油耗 · 加油记录"
        case .location: return "最近上报位置"
        case .health: return "最近报告 · 异常详情"
        case .messages: return "通知 · 消息"
        case .appearance: return "车模库与配色"
        case .settings: return "通用设置"
        case .appInfo: return "版本与关于"
        }
    }
}

/// 演示占位页（对应 ID. CONTROL 中暂未接入真实数据的条目）
private struct DemoSheetView: View {
    let title: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.system(size: 30))
                .foregroundStyle(WebTheme.blue)
                .padding(.top, 40)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            Text("演示功能 · 暂未接入真实数据")
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.faint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WebTheme.bg0.ignoresSafeArea())
    }
}
