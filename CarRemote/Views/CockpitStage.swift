import SwiftUI
import UIKit
import CarCore

// MARK: - 车模舞台 ↔ 空调座舱 的展开转场
//
// 对应录屏里的 hero 过渡：点「座舱」后车模模糊缩小淡出、座舱面板带轻微缩放
// 与位移淡入，胶囊上的高亮滑块用 matchedGeometryEffect 平滑滑动。全部使用
// iOS 15 可用的 SwiftUI API（.spring / .opacity / .scaleEffect / .blur /
// matchedGeometryEffect），不依赖 iOS 16+ 专属修饰符。

/// 车模舞台与座舱面板共用同一个容器，切换时做交叉缩放淡入淡出。
/// carContent 传入原有的 3D/2D 车模视图，避免改动既有车模实现。
struct CockpitStage<CarContent: View>: View {
    @Namespace private var tabNamespace
    @State private var showCockpit = false
    @State private var targetTemp: Int

    /// 车机当前设定温度（用于初始化目标温度）
    let currentTemp: Double?
    /// 开启空调（携带目标温度）
    let onOpenAC: (Int) -> Void
    /// 关闭空调
    let onCloseAC: () -> Void
    @ViewBuilder var carContent: () -> CarContent

    init(currentTemp: Double?,
         onOpenAC: @escaping (Int) -> Void,
         onCloseAC: @escaping () -> Void,
         @ViewBuilder carContent: @escaping () -> CarContent) {
        self.currentTemp = currentTemp
        self.onOpenAC = onOpenAC
        self.onCloseAC = onCloseAC
        self.carContent = carContent
        let initial: Int
        if let t = currentTemp, t >= 16, t <= 32 {
            initial = Int(t.rounded())
        } else {
            initial = 26
        }
        _targetTemp = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 车模：展开时模糊 + 缩小淡出
                carContent()
                    .scaleEffect(showCockpit ? 0.84 : 1.0)
                    .opacity(showCockpit ? 0 : 1)
                    .blur(radius: showCockpit ? 9 : 0)
                    .allowsHitTesting(!showCockpit)

                // 座舱面板：收起时放大偏移淡出
                cockpitPanel
                    .scaleEffect(showCockpit ? 1.0 : 1.14)
                    .opacity(showCockpit ? 1 : 0)
                    .offset(y: showCockpit ? 0 : 16)
                    .allowsHitTesting(showCockpit)
            }
            .frame(height: 216)
            .clipped()

            // 车辆 / 座舱 切换胶囊（高亮滑块用 matchedGeometryEffect 平滑滑动）
            HStack(spacing: 2) {
                tabButton(title: "车辆", symbol: "car.fill", selected: !showCockpit) {
                    switchTo(false)
                }
                tabButton(title: "座舱", symbol: "thermometer.medium", selected: showCockpit) {
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
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            showCockpit = cockpit
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - 座舱面板

    private var cockpitPanel: some View {
        ZStack {
            // 深色车内氛围：底部冷灰 + 顶部暖光晕
            LinearGradient(
                colors: [
                    Color(hex: 0x0b1220),
                    Color(hex: 0x1c2738),
                    Color(hex: 0x2b3547)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [WebTheme.amber.opacity(0.28), .clear],
                center: .init(x: 0.5, y: 0.18),
                startRadius: 4,
                endRadius: 150
            )
            RadialGradient(
                colors: [WebTheme.blue.opacity(0.18), .clear],
                center: .init(x: 0.12, y: 0.9),
                startRadius: 2,
                endRadius: 120
            )

            VStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "wind")
                        .font(.system(size: 9, weight: .semibold))
                    Text("CLIMATE · 座舱空调")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.55))

                // 温度大圆
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        .frame(width: 104, height: 104)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(
                            LinearGradient(
                                colors: [WebTheme.amber, WebTheme.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(140))
                    VStack(spacing: 0) {
                        Text("\(targetTemp)")
                            .font(.system(size: 40, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("°C  目标温度")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }

                // 调温 + 开关
                HStack(spacing: 10) {
                    tempStep(symbol: "minus") { targetTemp = max(16, targetTemp - 1) }
                    Button {
                        onOpenAC(targetTemp)
                    } label: {
                        Text("开启空调")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(WebTheme.blue.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("以 \(targetTemp) 度开启空调")

                    Button {
                        onCloseAC()
                    } label: {
                        Text("关闭")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭空调")

                    tempStep(symbol: "plus") { targetTemp = min(32, targetTemp + 1) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("座舱空调面板，目标温度 \(targetTemp) 度")
    }

    private func tempStep(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.13))
                .clipShape(Circle())
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
