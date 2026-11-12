import SwiftUI
import UIKit

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

// MARK: - 中文点阵（1.2.0）

/// 把任意文字（中文/英文/数字）离屏渲染成位图，按 16×16 网格采样生成点阵。
/// 无需手写字模，所有界面中文标签都能点阵化；结果按文本缓存。
enum DotCnGlyphCache {
    static let rowsPerChar = 16
    static let colsPerChar = 16

    private static let lock = NSLock()
    private static var cache: [String: [[[Bool]]]] = [:]

    /// 返回整串每个字的点阵（ [[[Bool]]] = [字][行][列] ）
    static func grids(for text: String) -> [[[Bool]]] {
        lock.lock()
        if let hit = cache[text] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let built = text.map { sampleCharacter($0) }
        lock.lock()
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[text] = built
        lock.unlock()
        return built
    }

    /// 单字采样：渲染到 128×128 RGBA 位图，每格中心取 2×2 子样本多数表决
    private static func sampleCharacter(_ ch: Character) -> [[Bool]] {
        let px = 128
        guard let context = CGContext(
            data: nil,
            width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: px * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Array(repeating: Array(repeating: false, count: colsPerChar), count: rowsPerChar)
        }
        // 黑底白字，取 alpha 通道
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: px, height: px))
        UIGraphicsPushContext(context)
        let font = UIFont.systemFont(ofSize: 108, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let s = String(ch) as NSString
        let sz = s.size(withAttributes: attrs)
        s.draw(at: CGPoint(x: (CGFloat(px) - sz.width) / 2,
                           y: (CGFloat(px) - sz.height) / 2), withAttributes: attrs)
        UIGraphicsPopContext()

        guard let data = context.makeImage()?.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return Array(repeating: Array(repeating: false, count: colsPerChar), count: rowsPerChar)
        }
        // 注意：CoreGraphics 位图坐标 y 轴朝下渲染出的文字是倒的，
        // 这里按行读取时翻转 y（grid 第 0 行 = 位图最后一行）
        var grid = Array(repeating: Array(repeating: false, count: colsPerChar), count: rowsPerChar)
        let cellW = CGFloat(px) / CGFloat(colsPerChar)
        let cellH = CGFloat(px) / CGFloat(rowsPerChar)
        for r in 0..<rowsPerChar {
            for c in 0..<colsPerChar {
                var onCount = 0
                for sy in 0..<2 {
                    for sx in 0..<2 {
                        let x = Int(cellW * (CGFloat(c) + 0.25 + 0.5 * CGFloat(sx)))
                        let ySrc = Int(cellH * (CGFloat(r) + 0.25 + 0.5 * CGFloat(sy)))
                        // 翻转 y：UIKit 文字绘制在 CGContext 中 y 向下，
                        // 我们的行 0 应对应位图顶部行 → 直接用 ySrc 即可（文字自身经 draw(at:) 已正向绘制）
                        let idx = (ySrc * px + x) * 4 + 3
                        guard idx >= 0, idx < CFDataGetLength(data) else { continue }
                        if bytes[idx] > 100 { onCount += 1 }
                    }
                }
                grid[r][c] = onCount >= 2
            }
        }
        return grid
    }
}

/// 中文点阵文本视图：视觉与 DotMatrixText 完全同风格（同 gapRatio / 圆角点）。
/// `size` 为字高（pt）；任意文字可用，标签、按钮、长句都走这里。
/// 传 `wrapWidth` 时按该宽度自动折行（所有字符等宽，折行计算精确）。
struct DotCnText: View {
    let text: String
    var size: CGFloat = 12
    var color: Color = Mono.paperInk
    var gapRatio: CGFloat = 0.22
    /// 提供时按此宽度折行（多行绘制）
    var wrapWidth: CGFloat? = nil
    /// 折行时的水平对齐
    var wrapAlignment: HorizontalAlignment = .center

    private var unit: CGFloat { size / CGFloat(DotCnGlyphCache.rowsPerChar) }
    private var step: CGFloat { unit * (1 + gapRatio) }
    private var dot: CGFloat { unit * (1 - gapRatio * 0.45) }
    private var charWidth: CGFloat { CGFloat(DotCnGlyphCache.colsPerChar) * step }
    private var charGap: CGFloat { step * 0.55 }

    private var chars: [Character] { Array(text) }
    private var grids: [[[Bool]]] { DotCnGlyphCache.grids(for: text) }

    private var singleLineWidth: CGFloat {
        CGFloat(chars.count) * charWidth + CGFloat(max(0, chars.count - 1)) * charGap
    }
    private var lineH: CGFloat { CGFloat(DotCnGlyphCache.rowsPerChar) * step }

    /// 折行布局：返回每行 [字符下标]
    private var lines: [[Int]] {
        guard let wrapWidth, wrapWidth > charWidth else { return [Array(0..<chars.count)] }
        var result: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for i in 0..<chars.count {
            let w = charWidth + (current.isEmpty ? 0 : charGap)
            if x + w > wrapWidth, !current.isEmpty {
                result.append(current)
                current = []
                x = 0
                x = charWidth
            } else {
                x += w
            }
            current.append(i)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private var totalWidth: CGFloat { wrapWidth ?? singleLineWidth }
    private var totalHeight: CGFloat { CGFloat(lines.count) * lineH }

    var body: some View {
        Canvas { context, _ in
            let layout = lines
            let lineAdvance = lineH + step * 0.5
            for (li, line) in layout.enumerated() {
                let lineWidth = CGFloat(line.count) * charWidth + CGFloat(max(0, line.count - 1)) * charGap
                let originX: CGFloat = {
                    if let wrapWidth {
                        switch wrapAlignment {
                        case .leading: return 0
                        case .trailing: return wrapWidth - lineWidth
                        default: return (wrapWidth - lineWidth) / 2
                        }
                    }
                    return 0
                }()
                for (pos, charIdx) in line.enumerated() where charIdx < grids.count {
                    let grid = grids[charIdx]
                    let baseX = originX + CGFloat(pos) * (charWidth + charGap)
                    let baseY = CGFloat(li) * lineAdvance
                    for (row, rowBits) in grid.enumerated() {
                        for (col, on) in rowBits.enumerated() where on {
                            let rect = CGRect(
                                x: baseX + CGFloat(col) * step,
                                y: baseY + CGFloat(row) * step,
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
        }
        .frame(width: max(1, totalWidth), height: totalHeight)
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
