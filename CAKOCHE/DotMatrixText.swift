import SwiftUI
import UIKit
import CoreText

/// 5×7 点阵字模。CAKOCHE 的识别符号：品牌字、数值、状态标签全部点阵化，
/// 中文仍用系统黑体（点阵中文字模体积过大，且可读性差）。
/// 用 Canvas 一次绘制，避免几百个 View 叠加导致滚动掉帧。
enum DotGlyph {
    static let rows = 7
    static let cols = 5

    static let table: [Character: [String]] = {
        let raw: [String: [String]] = [
            "0": ["01110","10001","10011","10101","11001","10001","01110"],
            "1": ["00100","01100","00100","00100","00100","00100","01110"],
            "2": ["01110","10001","00001","00010","00100","01000","11111"],
            "3": ["11111","00010","00100","00010","00001","10001","01110"],
            "4": ["00010","00110","01010","10010","11111","00010","00010"],
            "5": ["11111","10000","11110","00001","00001","10001","01110"],
            "6": ["00110","01000","10000","11110","10001","10001","01110"],
            "7": ["11111","00001","00010","00100","01000","01000","01000"],
            "8": ["01110","10001","10001","01110","10001","10001","01110"],
            "9": ["01110","10001","10001","01111","00001","00010","01100"],
            "A": ["01110","10001","10001","11111","10001","10001","10001"],
            "B": ["11110","10001","10001","11110","10001","10001","11110"],
            "C": ["01111","10000","10000","10000","10000","10000","01111"],
            "D": ["11110","10001","10001","10001","10001","10001","11110"],
            "E": ["11111","10000","10000","11110","10000","10000","11111"],
            "F": ["11111","10000","10000","11110","10000","10000","10000"],
            "G": ["01111","10000","10000","10111","10001","10001","01111"],
            "H": ["10001","10001","10001","11111","10001","10001","10001"],
            "I": ["01110","00100","00100","00100","00100","00100","01110"],
            "J": ["00111","00010","00010","00010","00010","10010","01100"],
            "K": ["10001","10010","10100","11000","10100","10010","10001"],
            "L": ["10000","10000","10000","10000","10000","10000","11111"],
            "M": ["10001","11011","10101","10101","10001","10001","10001"],
            "N": ["10001","11001","10101","10011","10001","10001","10001"],
            "O": ["01110","10001","10001","10001","10001","10001","01110"],
            "P": ["11110","10001","10001","11110","10000","10000","10000"],
            "Q": ["01110","10001","10001","10001","10101","10010","01101"],
            "R": ["11110","10001","10001","11110","10100","10010","10001"],
            "S": ["01111","10000","10000","01110","00001","00001","11110"],
            "T": ["11111","00100","00100","00100","00100","00100","00100"],
            "U": ["10001","10001","10001","10001","10001","10001","01110"],
            "V": ["10001","10001","10001","10001","10001","01010","00100"],
            "W": ["10001","10001","10001","10101","10101","11011","10001"],
            "X": ["10001","10001","01010","00100","01010","10001","10001"],
            "Y": ["10001","10001","01010","00100","00100","00100","00100"],
            "Z": ["11111","00001","00010","00100","01000","10000","11111"],
            "-": ["00000","00000","00000","11111","00000","00000","00000"],
            ".": ["00000","00000","00000","00000","00000","01100","01100"],
            ":": ["00000","01100","01100","00000","01100","01100","00000"],
            "/": ["00001","00010","00010","00100","01000","01000","10000"],
            "%": ["11001","11010","00010","00100","01000","01011","10011"],
            "+": ["00000","00100","00100","11111","00100","00100","00000"],
            " ": ["00000","00000","00000","00000","00000","00000","00000"]
        ]
        var out: [Character: [String]] = [:]
        for (k, v) in raw { out[Character(k)] = v }
        return out
    }()

    static func glyph(_ ch: Character) -> [String] {
        table[ch] ?? table[Character(String(ch).uppercased())] ?? table[" "]!
    }
}

/// 点阵文本视图。`size` 为字高（pt），点边长与间距按比例推导。
struct DotMatrixText: View {
    let text: String
    var size: CGFloat = 24
    var color: Color = Mono.paperInk
    /// 亮点之间的空隙比例（0 = 实心方块，越大越稀疏）
    var gapRatio: CGFloat = 0.22

    private var unit: CGFloat { size / CGFloat(DotGlyph.rows) }
    private var step: CGFloat { unit * (1 + gapRatio) }
    private var dot: CGFloat { unit * (1 - gapRatio * 0.45) }
    private var charWidth: CGFloat { CGFloat(DotGlyph.cols) * step }
    private var charGap: CGFloat { step * 1.1 }

    private var chars: [Character] { Array(text.uppercased()) }

    private var totalWidth: CGFloat {
        CGFloat(chars.count) * charWidth + CGFloat(max(0, chars.count - 1)) * charGap
    }
    /// 1.2.0：绘制实际高度是 7 行 × step（约 1.22 倍 size），
    /// 之前 frame 只给 size 导致最后一行点被裁掉（续航/温度数字上下缺点）。
    private var totalHeight: CGFloat {
        CGFloat(DotGlyph.rows) * step
    }

    var body: some View {
        Canvas { context, _ in
            for (idx, ch) in chars.enumerated() {
                let glyph = DotGlyph.glyph(ch)
                let baseX = CGFloat(idx) * (charWidth + charGap)
                for (row, line) in glyph.enumerated() {
                    for (col, bit) in line.enumerated() where bit == "1" {
                        let rect = CGRect(
                            x: baseX + CGFloat(col) * step,
                            y: CGFloat(row) * step,
                            width: dot,
                            height: dot
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: dot * 0.16),
                            with: .color(color)
                        )
                    }
                }
            }
        }
        .frame(width: max(1, totalWidth), height: totalHeight)
        .accessibilityLabel(Text(text))
    }
}

/// 方块进度条（截图里的分段电量条，CAKOCHE 用于续航 / 油量占比）
struct BlockBar: View {
    var progress: Double
    var blocks: Int = 24
    var color: Color = Mono.paperInk
    var dim: Color = Mono.paperHair

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = (geo.size.width - gap * CGFloat(blocks - 1)) / CGFloat(blocks)
            HStack(spacing: gap) {
                ForEach(0..<blocks, id: \.self) { i in
                    Rectangle()
                        .fill(Double(i) / Double(blocks) < max(0, min(1, progress)) ? color : dim)
                        .frame(width: max(1, w), height: geo.size.height)
                }
            }
        }
    }
}

// MARK: - 中文点阵字体（1.2.3 彻底重写）
//
// 【为什么要推翻重做】1.2.0~1.2.2 的中文是「把系统黑体离屏渲染到 144px，
// 再降采样成 12×12 二值点阵，用 Canvas 画点」。复杂汉字十几笔画塞进 144 格，
// 必然断笔、粘连、发虚；反复调采样阈值 / 点间隙 / 字号都只是治标。
// 且 Canvas + 手工 .frame(width:) 让长句在 HStack / 分页容器里被裁切
// （用户反馈「信息显示不全、字被遮挡」）。
//
// 【1.2.3 方案】改用专业像素点阵字体 Zpix（SIL OFL，为 12px 低分辨率逐像素设计）：
//   · 字形本身就是点阵，笔画根根分明，不存在「矢量降采样糊化」；
//   · 用 SwiftUI 原生 Text 布局，自动换行、自适应宽度，遮挡从根上消失；
//   · 字体子集覆盖 GB2312 全汉字 + ASCII + 常用符号，动态文案不缺字；
//   · 两个 bundle 各自打包 Zpix.ttf，Info.plist 的 UIAppFonts 注册。
// 数字 / 品牌字仍走 DotMatrixText（5×7 手工字模），与中文像素字同属点阵家族。

enum CakocheFont {
    static let name = "Zpix"

    /// 旧 `size` 语义是「点阵字高」；映射到 Zpix 的 pt 字号。
    /// 适度放大（用户要求「稍微加大一点点」）并按 0.5pt 规整，保证渲染锐利。
    static func pointSize(_ dotHeight: CGFloat) -> CGFloat {
        (max(11, dotHeight * 1.25) * 2).rounded() / 2
    }

    /// 直接按 PostScript 名取字体。UIAppFonts 在进程启动时同步注册，View 渲染时必然就绪；
    /// Font.custom 自带安全 fallback（字体缺失时系统字体兜底，绝不留白）。
    /// 不做 UIFont(name:) 探测——它在注册时机边界可能误判为 nil 而错误回退。
    static func cn(_ dotHeight: CGFloat) -> Font {
        .custom(name, size: pointSize(dotHeight))
    }
}

/// 中文点阵文本：Zpix 像素字体 + SwiftUI 原生布局。
/// 保留 1.2.x 调用签名（gapRatio / wrapWidth / wrapAlignment），调用点零改动。
struct DotCnText: View {
    let text: String
    var size: CGFloat = 12
    var color: Color = Mono.paperInk
    /// 兼容旧签名；字距现由字体自身保证，不再使用
    var gapRatio: CGFloat = 0.10
    /// 提供时作为最大宽度上限（长句折行用）；nil 时宽度由父容器决定
    var wrapWidth: CGFloat? = nil
    var wrapAlignment: HorizontalAlignment = .leading

    private var stackAlignment: Alignment {
        Alignment(horizontal: wrapAlignment, vertical: .top)
    }
    private var textAlignment: TextAlignment {
        if wrapAlignment == .trailing { return .trailing }
        if wrapAlignment == .center { return .center }
        return .leading
    }

    /// 基础文本（避免在 @ViewBuilder 的 body 里用 let + return）
    private var label: some View {
        Text(text)
            .font(CakocheFont.cn(size))
            .tracking(0.2)
            .foregroundStyle(color)
            .lineSpacing(2)
            .multilineTextAlignment(textAlignment)
            // 固定宽度容器（如「按钮 1」70pt）中自动缩字号，绝不截断
            .minimumScaleFactor(0.8)
            // 水平可被压缩 → 自动换行；垂直保持理想高度 → 长句末行不被裁
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        Group {
            if let w = wrapWidth {
                label.frame(maxWidth: w, alignment: stackAlignment)
            } else {
                label
            }
        }
        .accessibilityLabel(Text(text))
    }
}

/// 跃动油量条（1.2.0）：密集小方块网格，点亮比例 = 油量，
/// 点亮区每列高度随机波动、密度随机闪烁，呈现均衡器式的上下跃动效果。
struct FuelDotBar: View {
    var progress: Double
    var rows: Int = 7
    var color: Color = Mono.paperInk
    var dim: Color = Mono.paperHair
    /// 闪烁节奏（秒）
    var tickInterval: Double = 0.14

    private func hash(_ a: Int, _ b: Int, _ c: Int) -> Int {
        var h = a &* 2654435761 &+ b &* 40503 &+ c &* 97
        h ^= h >> 13; h = h &* 1274126177; h ^= h >> 16
        return abs(h)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
            Canvas { ctx, size in
                let t = Int(timeline.date.timeIntervalSinceReferenceDate / tickInterval)
                let cell = (size.height / CGFloat(rows)).rounded(.down)
                guard cell >= 1 else { return }
                let gap: CGFloat = 1
                let advance = cell + gap
                let cols = max(8, Int((size.width + gap) / advance))
                let p = max(0, min(1, progress))
                let litCols = Int(Double(cols) * p)
                for c in 0..<cols {
                    let lit = c < litCols
                    // 点亮列高度：整体满高，随机 0~2 行波动 + 前沿 2 列多波动 → 上下跃动
                    var jitter = 0
                    if lit {
                        let near = hash(c, 7, t / 3) % 100
                        if near < 14 { jitter = 1 }
                        if near < 4 { jitter = 2 }
                        if litCols - c <= 2 { jitter += hash(c, 11, t) % 2 }
                    }
                    let litRows = max(0, rows - jitter)
                    for r in 0..<rows {
                        let on: Bool
                        if !lit {
                            on = false
                        } else if r >= litRows {
                            on = hash(c, r, t) % 100 < 22   // 波动掉的行里零星散点闪烁
                        } else {
                            on = hash(c, r, t) % 100 < 86   // 点亮区随机闪烁
                        }
                        let rect = CGRect(x: CGFloat(c) * advance, y: CGFloat(r) * advance,
                                          width: cell, height: cell)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 0.22),
                                 with: .color(on ? color : dim))
                    }
                }
            }
        }
        .accessibilityLabel(Text("油量 \(Int(progress * 100))%"))
    }
}
