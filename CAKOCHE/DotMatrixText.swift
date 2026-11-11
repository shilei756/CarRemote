import SwiftUI

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
        .frame(width: max(1, totalWidth), height: size)
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
