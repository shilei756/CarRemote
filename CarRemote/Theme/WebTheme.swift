import SwiftUI

// MARK: - 网页版设计规范（照搬 https://a9db267525c1cf6b2.app.workbuddy.host/ 控制台）

/// 控制台浅色主题（与网页版 /user_info 的 :root CSS 变量一一对应）
enum WebTheme {
    // 背景与卡片
    static let bg0 = Color(hex: 0xedf0f4)          // 页面背景
    static let card = Color(hex: 0xffffff)         // 卡片底
    static let card2 = Color(hex: 0xf1f4f8)        // 次级底（分段控件底等）
    static let border = Color(hex: 0xe4e9f0)       // 边框
    static let track = Color(hex: 0xe8edf3)        // 进度条底

    // 文字
    static let txt = Color(hex: 0x1e293b)          // 主文字
    static let muted = Color(hex: 0x64748b)        // 次文字
    static let faint = Color(hex: 0x94a3b8)        // 弱文字

    // 语义色（网页版 --blue/--green/--amber/--red/--purple）
    static let blue = Color(hex: 0x3b82f6)
    static let green = Color(hex: 0x22c55e)
    static let amber = Color(hex: 0xf59e0b)
    static let red = Color(hex: 0xef4444)
    static let purple = Color(hex: 0x7c3aed)

    // 大按钮描边色（.cbig.lock / .cbig.unlock）
    static let lockBorder = Color(hex: 0xcbd5e1)

    // 导航胶囊渐变（.nav-btn：linear-gradient(135deg,#8b5cf6,#6366f1)）
    static var navGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x8b5cf6), Color(hex: 0x6366f1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 卡片：白底 + 圆角 20 + 阴影 0 2px 10px rgba(15,23,42,.04) + 1px 边框
    static let cardRadius: CGFloat = 20
    static let cardShadow = Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.04)
}

// MARK: - 登录页暗色主题（与网页版首页 :root 变量一一对应）

enum WebLoginTheme {
    static let bg0 = Color(hex: 0x05070d)
    static let card = Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.07)
    static let card2 = Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.12)
    static let border = Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.15)
    static let txt = Color(hex: 0xe2e8f0)
    static let muted = Color(hex: 0x7d8aa3)
    static let faint = Color(hex: 0x4b5871)

    // 主色：珊瑚红 → 红（网页版 --cyan: #ff5a52 / --blue: #ef4444）
    static let cyan = Color(hex: 0xff5a52)
    static let blue = Color(hex: 0xef4444)
    static let green = Color(hex: 0x34d399)
    static let amber = Color(hex: 0xfbbf24)
    static let indigo = Color(hex: 0x6366f1)

    // logo 徽标：linear-gradient(135deg,#ff5a52,#ef4444 60%,#dc2626)
    static var logoGradient: LinearGradient {
        LinearGradient(
            colors: [cyan, blue, Color(hex: 0xdc2626)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 主按钮：linear-gradient(135deg,#fb923c,#ef4444 70%,#b91c1c)
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xfb923c), blue, Color(hex: 0xb91c1c)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Color hex 扩展

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - 网页版卡片修饰符

/// 控制台白卡：白底 + 1px 边框 + 圆角 20 + 轻阴影（.card）
struct WebCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                    .strokeBorder(WebTheme.border, lineWidth: 1)
            )
            .shadow(color: WebTheme.cardShadow, radius: 10, x: 0, y: 2)
    }
}

extension View {
    /// 应用网页版控制台卡片样式
    func webCard() -> some View {
        modifier(WebCardStyle())
    }
}

// MARK: - 等宽数字（.num: font-variant-numeric: tabular-nums）

extension View {
    /// 网页版 .num 数字字体：等宽数字 + 圆体
    func webNum() -> some View {
        font(.system(.body, design: .rounded, weight: .bold))
            .monospacedDigit()
    }
}

// MARK: - 网页版动效

/// 车图浮动（car-float：translateY ±6px 循环）+ 阴影呼吸（carShadow：scaleX/opacity 循环）
struct CarFloatModifier: ViewModifier {
    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .offset(y: floating ? -6 : 6)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: floating)
            .onAppear { floating = true }
    }
}

extension View {
    func carFloat() -> some View {
        modifier(CarFloatModifier())
    }
}

/// 状态圆点脉冲（pulse-dot 2s infinite）
struct PulseDotModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.35 : 1.0)
            .scaleEffect(pulse ? 1.35 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

extension View {
    func pulseDot() -> some View {
        modifier(PulseDotModifier())
    }
}

/// 樱花花瓣飘落（网页版 card-snow petalSnow 15s linear infinite 的轻量版）
struct SakuraPetal: Identifiable {
    let id = UUID()
    var x: CGFloat          // 水平位置（0~1）
    var size: CGFloat       // 花瓣尺寸
    var delay: Double       // 延迟
    var duration: Double    // 下落时长
    var drift: CGFloat      // 水平漂移幅度
    var opacity: Double
}

/// 卡片顶部花瓣层：8 片花瓣循环飘落（花瓣形 = 旋转的小椭圆）
struct SakuraOverlay: View {
    var count = 8
    var tint: Color = Color(red: 1.0, green: 0.72, blue: 0.80)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(petals(in: geo.size)) { petal in
                    Circle()
                        .fill(tint.opacity(petal.opacity))
                        .frame(width: petal.size, height: petal.size * 0.75)
                        .position(
                            x: geo.size.width * petal.x + (petal.drift * geo.size.width),
                            y: geo.size.height + 20
                        )
                        .modifier(
                            PetalFallModifier(
                                travel: geo.size.height + 40,
                                delay: petal.delay,
                                duration: petal.duration,
                                drift: petal.drift * geo.size.width
                            )
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func petals(in size: CGSize) -> [SakuraPetal] {
        (0..<count).map { i in
            SakuraPetal(
                x: CGFloat.random(in: 0.05...0.95),
                size: CGFloat.random(in: 3.5...6.5),
                delay: Double(i) * 1.9 + Double.random(in: 0...1.2),
                duration: Double.random(in: 5.5...9.5),
                drift: CGFloat.random(in: -0.06...0.06),
                opacity: Double.random(in: 0.5...0.85)
            )
        }
    }
}

/// 单片花瓣的下落动画
private struct PetalFallModifier: ViewModifier {
    let travel: CGFloat
    let delay: Double
    let duration: Double
    let drift: CGFloat

    @State private var falling = false

    func body(content: Content) -> some View {
        content
            .offset(x: falling ? drift : 0, y: falling ? -travel : 0)
            .opacity(falling ? 0.9 : 0)
            .animation(
                .linear(duration: duration)
                .repeatForever(autoreverses: false)
                .delay(delay),
                value: falling
            )
            .onAppear { falling = true }
    }
}

// MARK: - 页面背景（网页版 body 光晕的 SwiftUI 等价）

/// 控制台浅色背景：#edf0f4 + 右上蓝光晕 + 左中绿光晕
struct WebConsoleBackground: View {
    var body: some View {
        ZStack {
            WebTheme.bg0
            RadialGradient(
                colors: [WebTheme.blue.opacity(0.06), .clear],
                center: .init(x: 0.8, y: -0.05),
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [WebTheme.green.opacity(0.05), .clear],
                center: .init(x: 0.0, y: 0.3),
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}

/// 登录页暗色背景：#05070d + 珊瑚红光晕 + 红光晕 + 底部靛蓝光晕
struct WebLoginBackground: View {
    var body: some View {
        ZStack {
            WebLoginTheme.bg0
            RadialGradient(
                colors: [WebLoginTheme.cyan.opacity(0.10), .clear],
                center: .init(x: 0.85, y: -0.05),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [WebLoginTheme.blue.opacity(0.11), .clear],
                center: .init(x: -0.10, y: 0.25),
                startRadius: 0,
                endRadius: 340
            )
            RadialGradient(
                colors: [WebLoginTheme.indigo.opacity(0.08), .clear],
                center: .init(x: 0.5, y: 1.15),
                startRadius: 0,
                endRadius: 250
            )
        }
        .ignoresSafeArea()
    }
}
