import SwiftUI
import UIKit
import CoreText

/// CAKOCHE 小组件专用配色：与 App 内 Mono 完全一致（低饱和黑白 + 唯一红）。
/// 小组件进程不编译 CAKOCHE/ 目录，这里独立定义一份，值保持同步。
enum WMono {
    static let ink = Color(white: 0.965)
    /// 1.2.2：黑底上提亮，中文点阵更清晰
    static let dim = Color(white: 0.62)
    static let hair = Color(white: 0.19)
    static let red = Color(red: 0.88, green: 0.14, blue: 0.18)
}

// MARK: - 5×7 点阵字模（与 App 内 DotGlyph 同表，小组件独立编译一份）

enum WidgetDotGlyph {
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
            "-": ["00000","00000","00000","11111","00000","00000","00000"],
            ".": ["00000","00000","00000","00000","00000","01100","01100"],
            ":": ["00000","01100","01100","00000","01100","01100","00000"],
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

/// 点阵数字视图（仅数字与符号；中文用 WidgetDotCnText）
struct WidgetDotText: View {
    let text: String
    var size: CGFloat = 24
    var color: Color = WMono.ink
    var gapRatio: CGFloat = 0.22

    private var unit: CGFloat { size / CGFloat(WidgetDotGlyph.rows) }
    private var step: CGFloat { unit * (1 + gapRatio) }
    private var dot: CGFloat { unit * (1 - gapRatio * 0.45) }
    private var charWidth: CGFloat { CGFloat(WidgetDotGlyph.cols) * step }
    private var charGap: CGFloat { step * 1.1 }

    private var chars: [Character] { Array(text) }

    private var totalWidth: CGFloat {
        CGFloat(chars.count) * charWidth + CGFloat(max(0, chars.count - 1)) * charGap
    }
    /// 1.2.0：绘制实际高度 = 7 行 × step（约 1.22 倍 size），frame 同步修正不再裁点
    private var totalHeight: CGFloat { CGFloat(WidgetDotGlyph.rows) * step }

    var body: some View {
        Canvas { context, _ in
            for (idx, ch) in chars.enumerated() {
                let glyph = WidgetDotGlyph.glyph(ch)
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

// MARK: - 中文点阵字体（1.2.3，与 App 内 CakocheFont 同机制，小组件独立编译）

enum CakocheWidgetFont {
    static let name = "Zpix"

    /// 小组件空间紧张，不放大字号，按 0.5pt 规整保证锐利
    static func pointSize(_ dotHeight: CGFloat) -> CGFloat {
        (max(9, dotHeight * 1.15) * 2).rounded() / 2
    }

    static func cn(_ dotHeight: CGFloat) -> Font {
        .custom(name, size: pointSize(dotHeight))
    }
}

/// 中文点阵文本（小组件版）：Zpix 像素字体 + 原生布局。
/// 限 2 行 + 最小缩放 0.8，保证小/中/大号组件都不遮挡、不溢出。
struct WidgetDotCnText: View {
    let text: String
    var size: CGFloat = 9
    var color: Color = WMono.dim
    /// 兼容旧签名
    var gapRatio: CGFloat = 0.10

    var body: some View {
        Text(text)
            .font(CakocheWidgetFont.cn(size))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(text))
    }
}
