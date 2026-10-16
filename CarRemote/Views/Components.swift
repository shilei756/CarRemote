import SwiftUI

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension SectionCard {
    /// 无标题卡片
    init(@ViewBuilder content: () -> Content) {
        self.init(title: nil, content: content)
    }
}

// MARK: - 状态数值块

struct StatusTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 状态旗标

struct FlagChip: View {
    let text: String
    let systemImage: String
    var color: Color = .orange

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - 控车按钮

struct ControlButtonView: View {
    let command: CarCommand
    var isPrimary = false
    var isExecuting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: isPrimary ? 64 : 52, height: isPrimary ? 64 : 52)
                    if isExecuting {
                        ProgressView()
                            .frame(width: isPrimary ? 64 : 52, height: isPrimary ? 64 : 52)
                    } else {
                        Image(systemName: command.sfSymbol)
                            .font(.system(size: isPrimary ? 26 : 20, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                Text(command.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(command.displayName)\(command.isDangerous ? "，高危操作" : "")")
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
    }

    private var tint: Color {
        command.isDangerous ? .orange : .accentColor
    }
}

// MARK: - 车辆可视化

struct CarVisualView: View {
    let style: CarModelStyle
    let isUnlocked: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 车身
                RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                    .fill(bodyGradient)
                    .frame(width: w * 0.94, height: h * 0.40)
                    .position(x: w * 0.5, y: h * 0.66)
                // 车顶
                roof(in: CGSize(width: w, height: h))
                    .fill(bodyGradient)
                // 车窗
                windowGlass(in: CGSize(width: w, height: h))
                    .fill(Color(.systemBackground).opacity(0.9))
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

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.53, blue: 0.96),
                Color(red: 0.06, green: 0.35, blue: 0.80)
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
                control: CGPoint(x: w * 0.40, y: h * 0.26)
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
            CGRect(x: w * 0.38, y: h * 0.33, width: w * 0.18, height: h * 0.17),
            cornerSize: CGSize(width: 4, height: 4)
        )
        path.addRoundedRect(
            CGRect(x: w * 0.58, y: h * 0.33, width: w * 0.10, height: h * 0.17),
            cornerSize: CGSize(width: 4, height: 4)
        )
        return path
    }

    private func wheel(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(.label))
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: diameter * 0.45, height: diameter * 0.45)
        }
    }

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isUnlocked ? Color.orange : Color.green)
        }
    }
}

// MARK: - 轻提示

struct ToastModifier: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let message {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
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
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
