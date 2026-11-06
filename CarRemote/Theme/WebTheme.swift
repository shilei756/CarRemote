import SwiftUI
import CarCore

// MARK: - 网页版设计规范（照搬 https://a9db267525c1cf6b2.app.workbuddy.host/ 控制台）

/// 控制台主题（与网页版 /user_info 的 :root CSS 变量一一对应）
/// 夜间模式取值来自网页版 `html.dark` 规则块（--bg0:#101318 等）
/// 神兽主题激活时整套配色切换为神兽调色板（网页版 html.glass.myth-* 规则块）
///
/// ⚠️ 测试分支（test/id-control-style）专属：本分支复刻「上汽大众 ID.CONTROL」浅色仪表风，
/// 强制全局浅色 + 红色主强调 + 点阵字体，与正式版（main）彻底隔离——正式版后续更新不涉及此分支。
enum WebTheme {
    /// 测试版：强制浅色（ID.CONTROL 浅色仪表风），忽略用户偏好与系统外观
    static var isDark: Bool { false }

    /// 测试版：关闭神兽主题，避免配色被覆盖
    static var myth: MythTheme? { nil }

    // 背景与卡片
    static var bg0: Color {
        if let myth { return Color(hex: myth.bgHex) }
        return isDark ? Color(hex: 0x060608) : Color(hex: 0xedf0f4)
    }
    static var card: Color {
        if myth != nil { return Color(hex: 0xffffff) }
        return isDark ? Color(hex: 0x101012) : Color(hex: 0xffffff)
    }
    static var card2: Color {
        if let myth { return Color(hex: myth.bgHex).opacity(0.55) }
        return isDark ? Color(hex: 0x191a1d) : Color(hex: 0xf1f4f8)
    }
    static var border: Color {
        if let myth { return Color(hex: myth.mainHex).opacity(0.22) }
        return isDark ? Color(hex: 0x2b2b30) : Color(hex: 0xe4e9f0)
    }
    static var track: Color {
        if let myth { return Color(hex: myth.mainHex).opacity(0.15) }
        return isDark ? Color(hex: 0x2a3038) : Color(hex: 0xe8edf3)
    }

    // 文字
    static var txt: Color {
        if let myth { return Color(hex: myth.txtHex) }
        return isDark ? Color(hex: 0xf2f2f5) : Color(hex: 0x1e293b)
    }
    static var muted: Color {
        if let myth { return Color(hex: myth.mutedHex) }
        return isDark ? Color(hex: 0x9b9ba2) : Color(hex: 0x64748b)
    }
    static var faint: Color {
        if let myth { return Color(hex: myth.faintHex) }
        return isDark ? Color(hex: 0x67676e) : Color(hex: 0x94a3b8)
    }

    // 语义色（网页版 --blue/--green/--amber/--red/--purple）
    // 神兽主题下主色染主题色（网页版：按键与图标随神兽换色）
    static var blue: Color {
        if let myth { return Color(hex: myth.mainHex) }
        // 测试版 ID.CONTROL 风格主强调色：大众 ID 红
        return Color(hex: 0xE3000F)
    }
    static let green = Color(hex: 0x22c55e)
    static let amber = Color(hex: 0xf59e0b)
    static let red = Color(hex: 0xef4444)
    static var purple: Color {
        if let myth { return Color(hex: myth.deepHex) }
        return Color(hex: 0xa78bfa)
    }

    // 大按钮描边色（.cbig.lock / .cbig.unlock）
    static var lockBorder: Color {
        if let myth { return Color(hex: myth.mainHex).opacity(0.45) }
        return isDark ? Color(hex: 0x33333a) : Color(hex: 0xcbd5e1)
    }

    // 导航胶囊渐变（.nav-btn：linear-gradient(135deg,#8b5cf6,#6366f1)）
    // 神兽主题下换为 深→主 的主题渐变
    static var navGradient: LinearGradient {
        if let myth {
            return LinearGradient(
                colors: [Color(hex: myth.deepHex), Color(hex: myth.mainHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(hex: 0xE3000F), Color(hex: 0xb3000b)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 卡片：白底 + 圆角 20 + 阴影 0 2px 10px rgba(15,23,42,.04) + 1px 边框
    static let cardRadius: CGFloat = 20
    static var cardShadow: Color {
        // 测试版纯黑底：深色阴影不可见，统一清零，保持 ID.CONTROL 扁平干净观感
        isDark ? Color.clear : Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.04)
    }
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

/// 控制台白卡：白底 + 1px 边框 + 圆角 + 轻阴影（.card），圆角可定制
struct WebCardStyle: ViewModifier {
    var radius: CGFloat = WebTheme.cardRadius

    func body(content: Content) -> some View {
        content
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(WebTheme.border, lineWidth: 1)
            )
            .shadow(color: WebTheme.cardShadow, radius: 10, x: 0, y: 2)
    }
}

extension View {
    /// 应用网页版控制台卡片样式
    func webCard(radius: CGFloat = WebTheme.cardRadius) -> some View {
        modifier(WebCardStyle(radius: radius))
    }
}

extension View {
    /// 控车栏样式：iOS 26 用液态玻璃（Liquid Glass），旧系统回退网页版白卡。
    /// 配合自定义壁纸时，玻璃栏会透出壁纸，质感最佳。
    /// 注意：glassEffect 默认形状是胶囊，控车栏本就是胶囊形，故不传形状。
    @ViewBuilder
    func controlBarStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self.webCard()
        }
    }

    /// 卡片液态玻璃：iOS 26 用 Liquid Glass 圆角矩形（整卡上玻璃，与控车栏同质感），
    /// 旧系统回退网页版白卡。矩形卡片必须显式指定圆角矩形，
    /// 否则 glassEffect 默认胶囊形会把卡片挤成胶囊。
    @ViewBuilder
    func glassCard(radius: CGFloat = WebTheme.cardRadius) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.webCard(radius: radius)
        }
    }
}

// MARK: - 等宽数字（.num: font-variant-numeric: tabular-nums）

extension View {
    /// 网页版 .num 数字字体：等宽数字 + 圆体（iOS 15 兼容见 Compatibility.swift）
    func webNum() -> some View {
        font(.webNumFont)
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
/// 神兽主题：底色换神兽 --bg0，光晕换主题色，右侧探出神兽水墨图腾（网页版 body::after + #mythWatermark）
/// 自定义壁纸：用户从相册上传的图片优先整页铺底（适配 iOS 26 液态玻璃控车栏）
struct WebConsoleBackground: View {
    /// 用户自定义壁纸（相册上传）；非空时整页铺该图，忽略默认渐变
    @State private var customImage: UIImage?

    init() {
        if let data = SharedStore.loadCustomWallpaper(), let img = UIImage(data: data) {
            _customImage = State(initialValue: img)
        }
    }

    var body: some View {
        ZStack {
            if let customImage {
                // 自定义壁纸：整页铺满，叠一层轻量压暗保证卡片/文字可读
                Image(uiImage: customImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [Color.black.opacity(0.16), Color.black.opacity(0.30)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else {
                WebTheme.bg0
                if let myth = WebTheme.myth {
                    // 神兽主题：主题色光晕（网页版：右上主色雾 + 左下鎏金雾）
                    RadialGradient(
                        colors: [Color(hex: myth.mainHex).opacity(0.16), .clear],
                        center: .init(x: 0.88, y: 0.06),
                        startRadius: 0,
                        endRadius: 300
                    )
                    RadialGradient(
                        colors: [Color(hex: myth.goldHex).opacity(0.12), .clear],
                        center: .init(x: 0.04, y: 0.94),
                        startRadius: 0,
                        endRadius: 280
                    )
                    // 神兽图腾：右上探出（网页版 #mythWatermark）
                    Image(myth.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 340)
                        .rotationEffect(.degrees(-6))
                        .opacity(0.16)
                        .position(x: UIScreen.main.bounds.width * 0.78, y: 130)
                        .allowsHitTesting(false)
                } else {
                    // 测试版 ID.CONTROL 浅色氛围：浅灰底（bg0）+ 顶部中央一抹极淡红色微光（车模后方），底部再补一层更淡辉光
                    RadialGradient(
                        colors: [WebTheme.blue.opacity(0.06), .clear],
                        center: .init(x: 0.5, y: 0.12),
                        startRadius: 0,
                        endRadius: 360
                    )
                    RadialGradient(
                        colors: [WebTheme.blue.opacity(0.03), .clear],
                        center: .init(x: 0.5, y: 1.05),
                        startRadius: 0,
                        endRadius: 300
                    )
                }
            }
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
