import SwiftUI
import UIKit
import CarCore

// MARK: - 车模舞台 ↔ 车内空调视角 的展开转场
//
// 1.5.0：座舱视觉由 GLB 3D 车模的**完整车身 + Int_P 内饰**共同渲染，
// 相机直接坐进前排眼位朝仪表台 / 前挡风看（Car3DView.setViewMode(.interior)）。
// 不再隐藏车身外壳、不再让轨道相机在车外绕圈，也不再用手绘矢量假场景。
// 切换时渲染视口加高 + 72° 广角，形成镜头推进放大的 hero 效果，
// 下方浮现「遥控空调」控制卡。
//
// 全部使用 iOS 15 可用的 SwiftUI API，不依赖 iOS 16+ 专属修饰符。

/// 车模舞台与车内空调视角共用同一个 3D 车模：切到座舱时相机进入车内、画面放大。
/// carContent 传入原有的 3D/2D 车模视图，并接收「是否处于座舱态」以便隐藏
/// 车外展示专用的地面阴影；通过环境值把车内视角下发给车模舞台。
struct CockpitStage<CarContent: View>: View {
    @Namespace private var tabNamespace
    @State private var showCockpit = false
    @State private var targetTemp: Int
    // 空调控件的视觉状态（本地态，不额外下发指令）
    @State private var acPowerOn = false
    @State private var coolOn = true
    @State private var autoOn = false
    @State private var fanLevel = 2

    /// 车机当前设定温度（用于初始化目标温度）
    let currentTemp: Double?
    /// 开启空调（携带目标温度）
    let onOpenAC: (Int) -> Void
    /// 关闭空调
    let onCloseAC: () -> Void
    /// 车模内容（参数为是否处于座舱第一视角）
    @ViewBuilder var carContent: (Bool) -> CarContent

    init(currentTemp: Double?,
         onOpenAC: @escaping (Int) -> Void,
         onCloseAC: @escaping () -> Void,
         @ViewBuilder carContent: @escaping (Bool) -> CarContent) {
        self.currentTemp = currentTemp
        self.onOpenAC = onOpenAC
        self.onCloseAC = onCloseAC
        self.carContent = carContent
        let initial: Int
        if let t = currentTemp, t >= 16, t <= 32 {
            initial = Int(t.rounded())
        } else {
            initial = 20
        }
        _targetTemp = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .center) {
                // 座舱态铺一层「车外天空 → 车内暗部」背景：前挡风玻璃背面被剔除后
                // 透出的是这层，而不是浅绿龙纹壁纸（1.4.0 的车窗穿帮问题）。
                if showCockpit { cockpitBackdrop }

                // 3D 车模常驻：切到座舱时把「车内视角」下发给车模舞台，
                // 由其相机坐进前排、保留完整车身做真实车内渲染。
                carContent(showCockpit)
                    .environment(\.carCockpitStage, .managed(interior: showCockpit))
            }
            .frame(height: showCockpit ? 288 : 214)
            .clipShape(RoundedRectangle(cornerRadius: showCockpit ? 20 : 0, style: .continuous))
            .overlay(
                Group {
                    if showCockpit {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(WebTheme.border, lineWidth: 1)
                    }
                }
            )
            .contentShape(Rectangle())

            // 展开后下方浮现「遥控空调」控制卡
            if showCockpit {
                climateControlCard
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 车辆 / 座舱 切换胶囊（高亮滑块用 matchedGeometryEffect 平滑滑动）
            HStack(spacing: 2) {
                tabButton(title: "车辆", symbol: "car.fill", selected: !showCockpit) {
                    switchTo(false)
                }
                tabButton(title: "座舱", symbol: "snowflake", selected: showCockpit) {
                    switchTo(true)
                }
            }
            .padding(3)
            .background(WebTheme.card2)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(WebTheme.border, lineWidth: 1)
            )
            .padding(.top, 10)
            .accessibilityElement(children: .contain)
        }
    }

    private func switchTo(_ cockpit: Bool) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            showCockpit = cockpit
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 座舱画面背景：模拟从车内透过前挡风玻璃看到的天空（上）与仪表台暗部（下）。
    /// 用中性冷灰，既不抢内饰的高光，也彻底隔绝自定义壁纸从车窗透出。
    private var cockpitBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.79, green: 0.84, blue: 0.86), location: 0),
                .init(color: Color(red: 0.62, green: 0.69, blue: 0.72), location: 0.38),
                .init(color: Color(red: 0.27, green: 0.31, blue: 0.34), location: 0.70),
                .init(color: Color(red: 0.11, green: 0.13, blue: 0.15), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 遥控空调控制卡

    private var climateControlCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("遥控空调")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WebTheme.muted)
                Spacer()
                Text("最低设定温度 · 舒适")
                    .font(.system(size: 9))
                    .foregroundStyle(WebTheme.faint)
                Text("最高设定温度 30.5°C")
                    .font(.system(size: 9))
                    .foregroundStyle(WebTheme.faint)
            }

            // 大温度 + −/+
            HStack(spacing: 16) {
                tempStep(symbol: "minus") {
                    targetTemp = max(16, targetTemp - 1)
                }
                Text(String(format: "%.1f°", Double(targetTemp)))
                    .font(.system(size: 40, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.txt)
                    .frame(minWidth: 118)
                    .accessibilityLabel("目标温度 \(targetTemp) 度")
                tempStep(symbol: "plus") {
                    targetTemp = min(32, targetTemp + 1)
                }
            }

            // 制冷 / 风量 / AUTO / 电源
            HStack(spacing: 0) {
                climateButton(symbol: "snowflake", title: "制冷", active: coolOn) {
                    coolOn.toggle()
                    if coolOn, !acPowerOn {
                        acPowerOn = true
                        onOpenAC(targetTemp)
                    }
                }
                climateButton(symbol: "wind", title: "风量 \(fanLevel)", active: fanLevel > 0) {
                    fanLevel = fanLevel % 3 + 1
                }
                climateButton(symbol: "a.circle", title: "AUTO", active: autoOn) {
                    autoOn.toggle()
                }
                climateButton(symbol: "power", title: acPowerOn ? "关闭" : "开启",
                              active: acPowerOn) {
                    acPowerOn.toggle()
                    if acPowerOn { onOpenAC(targetTemp) }
                    else { onCloseAC() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WebTheme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func climateButton(symbol: String, title: String, active: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? WebTheme.blue : WebTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(active ? WebTheme.blue.opacity(0.12) : WebTheme.card2)
                    )
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? WebTheme.txt : WebTheme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func tempStep(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WebTheme.txt)
                .frame(width: 38, height: 38)
                .background(Circle().fill(WebTheme.card2))
                .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "调高温度" : "调低温度")
    }

    private func tabButton(title: String, symbol: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? WebTheme.txt : WebTheme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule()
                        .fill(WebTheme.card)
                        .matchedGeometryEffect(id: "cockpitTab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
