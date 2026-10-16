import SwiftUI
import CarCore

// MARK: - 卡片容器（网页版 .card：白底圆角 20 + 轻阴影 + 顶部樱花花瓣）

struct SectionCard<Content: View>: View {
    var title: String?
    /// 是否显示顶部樱花花瓣飘落（网页版 .myth-card 的 card-snow）
    var sakura = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
        .overlay(alignment: .top) {
            if sakura {
                SakuraOverlay()
                    .frame(height: 16)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension SectionCard {
    /// 无标题卡片
    init(@ViewBuilder content: () -> Content) {
        self.init(title: nil, content: content)
    }
}

// MARK: - 卡片标题（网页版 .card-title）

struct CardTitleText: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.faint)
            }
        }
    }
}

// MARK: - 状态数值块（网页版车况数据行：图标 + 标签 + 数值）

struct StatusTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var systemImage: String?
    var tint: Color = WebTheme.blue

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .frame(width: 20)
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(WebTheme.muted)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.txt)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(WebTheme.faint)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 状态旗标（网页版车况标签胶囊）

struct FlagChip: View {
    let text: String
    let systemImage: String
    var color: Color = WebTheme.amber

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - 控车按钮（网页版 .cbtn / .cbig）

/// 网页版快捷按钮：白底圆钮 + 底部小标签；主控（开锁/闭锁）为 54px 描边大钮
struct ControlButtonView: View {
    let command: CarCommand
    var isPrimary = false
    var isExecuting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    // 白底圆钮（.cbtn / .cbig 均为白底）
                    Circle()
                        .fill(WebTheme.card)
                        .frame(width: isPrimary ? 54 : 46, height: isPrimary ? 54 : 46)
                    if isPrimary {
                        // 大钮描边：开锁=绿、闭锁=灰（.cbig.unlock / .cbig.lock）
                        Circle()
                            .strokeBorder(borderColor, lineWidth: 2.5)
                            .frame(width: 54, height: 54)
                            .shadow(color: shadowColor, radius: 14, x: 0, y: 4)
                    } else {
                        Circle()
                            .strokeBorder(WebTheme.border, lineWidth: 1)
                            .frame(width: 46, height: 46)
                            .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.05), radius: 8, x: 0, y: 2)
                    }
                    if isExecuting {
                        ProgressView()
                            .tint(iconColor)
                    } else {
                        Image(systemName: command.sfSymbol)
                            .font(.system(size: isPrimary ? 24 : 19, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                }
                Text(command.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(command.displayName)\(command.isDangerous ? "，高危操作" : "")")
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
    }

    /// 大钮描边色：开锁绿 / 闭锁灰（网页版 .cbig.unlock/.cbig.lock）
    private var borderColor: Color {
        command == .unlockDoor ? WebTheme.green : WebTheme.lockBorder
    }

    private var shadowColor: Color {
        command == .unlockDoor
            ? WebTheme.green.opacity(0.22)
            : Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.08)
    }

    private var iconColor: Color {
        switch command {
        case .unlockDoor: return WebTheme.green
        case .lockDoor: return WebTheme.muted
        default: return Color(hex: 0x475569)
        }
    }
}

// MARK: - 迷你圆形刷新按钮（网页版 .mini-refresh）

struct MiniRefreshButton: View {
    var isRunning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(WebTheme.muted)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text("刷新")
                    .font(.system(size: 11))
            }
            .foregroundStyle(WebTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(WebTheme.card2)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel("刷新")
    }
}

// MARK: - 进度条（网页版 .ftrack / .btrack）

struct WebTrack<Fill: ShapeStyle>: View {
    var fraction: Double
    var fill: Fill
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WebTheme.track)
                Capsule()
                    .fill(fill)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - 车辆可视化（浅色背景适配）

struct CarVisualView: View {
    let style: CarModelStyle
    let isUnlocked: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 车身（浅色主题下车身改为深灰蓝，与浅色背景形成对比）
                RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                    .fill(bodyGradient)
                    .frame(width: w * 0.94, height: h * 0.40)
                    .position(x: w * 0.5, y: h * 0.66)
                // 车顶
                roof(in: CGSize(width: w, height: h))
                    .fill(bodyGradient)
                // 车窗
                windowGlass(in: CGSize(width: w, height: h))
                    .fill(Color(hex: 0xedf0f4).opacity(0.92))
                // 车轮
                wheel(diameter: h * 0.24)
                    .position(x: w * 0.25, y: h * 0.76)
                wheel(diameter: h * 0.24)
                    .position(x: w * 0.75, y: h * 0.76)
                // 锁状态徽标
                lockBadge
                    .position(x: w * 0.88, y: h * 0.16)
            }
        }
        .aspectRatio(2.1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnlocked ? "车辆示意图，当前已解锁" : "车辆示意图，当前已锁止")
    }

    /// 浅色背景下车身用深色金属渐变（深蓝灰 → 深灰）
    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.29, green: 0.35, blue: 0.44),
                Color(red: 0.15, green: 0.19, blue: 0.25)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func roof(in size: CGSize) -> Path {
        var path = Path()
        let w = size.width
        let h = size.height
        switch style {
        case .sedan:
            path.move(to: CGPoint(x: w * 0.24, y: h * 0.56))
            path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))
        case .coupe:
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.56))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.66, y: h * 0.28),
                control: CGPoint(x: w * 0.40, y: 0.26)
            )
            path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.56))
        case .suv:
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.56))
            path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.24))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.24))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.56))
        }
        path.closeSubpath()
        return path
    }

    private func windowGlass(in size: CGSize) -> Path {
        var path = Path()
        let w = size.width
        let h = size.height
        path.addRoundedRect(
            in: CGRect(x: w * 0.38, y: h * 0.33, width: w * 0.18, height: h * 0.17),
            cornerSize: CGSize(width: 4, height: 4)
        )
        path.addRoundedRect(
            in: CGRect(x: w * 0.58, y: h * 0.33, width: w * 0.10, height: h * 0.17),
            cornerSize: CGSize(width: 4, height: 4)
        )
        return path
    }

    private func wheel(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x1e293b))
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(WebTheme.card)
                .frame(width: diameter * 0.45, height: diameter * 0.45)
        }
    }

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(WebTheme.card)
                .frame(width: 34, height: 34)
                .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.15), radius: 4, y: 2)
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isUnlocked ? WebTheme.amber : WebTheme.green)
        }
    }
}

// MARK: - 轻提示（网页版 toast：右上滑入，红/绿底色）

struct ToastModifier: ViewModifier {
    let message: String?
    var isError = false

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let message {
                HStack(spacing: 6) {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isError ? Color(hex: 0xdc2626) : Color(hex: 0x059669))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: message)
    }
}

extension View {
    func toast(_ message: String?) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(WebTheme.faint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WebTheme.muted)
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.faint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
