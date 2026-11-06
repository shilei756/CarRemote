import SwiftUI
import CarCore

/// ID.CONTROL「空调」页：座舱 hero（3D 车模，可切外/内）+ 座舱空调卡 + 制冷/制热/启动 三卡。
/// 全部为「预览」态，不向车辆真实下发指令（对齐 ID. CONTROL 演示语义）。
struct ClimateView: View {
    @EnvironmentObject private var appState: AppState
    private var settings: AppSettings { SharedStore.loadSettings() }

    @State private var previewTemp: Double = 20.0
    @State private var departureOn = false

    var body: some View {
        ZStack {
            WebConsoleBackground()
            ScrollView {
                VStack(spacing: 12) {
                    // 顶部栏：左设置 · 中「空调」点阵标题 · 右刷新
                    HStack(spacing: 12) {
                        circleButton(icon: "slider.horizontal.3") { }
                        Spacer()
                        Text("空调")
                            .font(Font.webLedFont(size: 20))
                            .foregroundStyle(WebTheme.txt)
                            .tracking(1)
                        Spacer()
                        circleButton(icon: "antenna.radiowaves.left.and.right") {
                            Task { await appState.refreshStatus() }
                        }
                        .disabled(appState.isRefreshing)
                    }
                    .padding(.top, 6)
                    // 车名
                    Text(appState.carName.isEmpty ? "我的爱车" : appState.carName)
                        .font(Font.webLedFont(size: 18))
                        .foregroundStyle(WebTheme.txt)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let status = appState.status {
                        // 座舱 hero：复用 3D 车模（自带外/内视角切换）
                        CarVisual3DStage(
                            style: settings.carModelStyle,
                            doorsAndWindows: status.doorsAndWindows,
                            vehicleStarted: status.isVehicleStarted,
                            wheelsRolling: status.shouldRollWheels
                        )
                        .frame(height: 220)
                        .padding(.horizontal, 8)
                        // 状态行
                        HStack(spacing: 4) {
                            Text("状态").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                            Text("座舱").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                            Text("·").foregroundStyle(WebTheme.faint)
                            Text("气流跟随空调状态").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                        }
                    } else {
                        ProgressView()
                            .tint(WebTheme.blue)
                            .frame(height: 200)
                    }

                    // 座舱空调卡
                    climateControlCard
                    // 三快捷卡
                    HStack(spacing: 12) {
                        quickACCard(icon: "snowflake", title: "制冷")
                        quickACCard(icon: "sun.max.fill", title: "制热")
                        quickACCard(icon: "power", title: "启动")
                    }
                    Text("仅为预览，不向车辆发送指令。")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity, alignment: .center)
                    // 出发空调卡
                    departureCard
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
    }

    // MARK: 组件

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

    private var climateControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "fan.fill").foregroundStyle(WebTheme.blue)
                Text("目标温度 · 预览")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text("每次调节 ±5°C")
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
            }
            HStack {
                Circle().fill(WebTheme.txt).frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "minus")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .bold))
                    )
                    .onTapGesture { previewTemp = max(16, previewTemp - 0.5) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("降低温度")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", previewTemp))
                        .font(Font.webSegFont(size: 40))
                        .foregroundStyle(WebTheme.txt)
                        .monospacedDigit()
                    Text("°C")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WebTheme.faint)
                }
                Spacer()
                Circle().fill(WebTheme.txt).frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .bold))
                    )
                    .onTapGesture { previewTemp = min(30, previewTemp + 0.5) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("升高温度")
            }
        }
        .padding(16)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                .strokeBorder(WebTheme.border, lineWidth: 1)
        )
    }

    private func quickACCard(icon: String, title: String) -> some View {
        Button {
            // 演示：仅预览，不下发指令
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(WebTheme.blue)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WebTheme.txt)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                    .strokeBorder(WebTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var departureCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("出发空调")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.txt)
                Text("计划预览")
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
            }
            Spacer()
            Toggle("", isOn: $departureOn)
                .labelsHidden()
                .tint(WebTheme.blue)
        }
        .padding(16)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                .strokeBorder(WebTheme.border, lineWidth: 1)
        )
    }
}
