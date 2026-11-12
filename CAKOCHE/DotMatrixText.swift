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

// MARK: - 中文点阵（1.2.0）

/// 把任意文字（中文/英文/数字）离屏渲染成位图，按 12×12 网格采样生成点阵。
/// 1.2.1：改用「透明底 + 只读 alpha」——此前填不透明黑底再读 alpha，
/// 黑底 alpha 也是 255，导致所有格子被判成点亮，中文糊成马赛克。
/// 结果按文本缓存。
enum DotCnGlyphCache {
    static let rowsPerChar = 12
    static let colsPerChar = 12
    private static let px = 144

    /// 自探测位图内存行序：在用户坐标 y=0 画一个标记，
    /// 看它落在内存第 0 行还是最后一行，从而确定字形行序是否需要翻转。
    /// 避免依赖 CGBitmapContext 坐标系约定的记忆，真机上自行校准。
    private static let needsRowFlip: Bool = {
        let p = 8
        guard let c = CGContext(
            data: nil, width: p, height: p,
            bitsPerComponent: 8, bytesPerRow: p * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let raw = c.data else { return true }
        c.clear(CGRect(x: 0, y: 0, width: p, height: p))
        c.setFillColor(UIColor.white.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        let bpr = c.bytesPerRow
        let first = bytes[0 * bpr + 3]
        let last = bytes[(p - 1) * bpr + 3]
        // 用户 y=0 落在内存第 0 行 → 字形顶部（y 大）在内存行大 → grid 需翻转
        return first > 100 || last <= 100
    }()

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

    /// 单字采样：透明底绘制文字，只按 alpha 判断笔画是否被覆盖。
    /// 文字颜色无关（透明底 alpha=0，笔画 alpha=255），不依赖颜色空间/翻转约定。
    private static func sampleCharacter(_ ch: Character) -> [[Bool]] {
        let n = rowsPerChar
        let blank = Array(repeating: Array(repeating: false, count: n), count: n)
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: px * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return blank }

        // 关键：整张位图清成全透明，未绘制处 alpha = 0
        ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

        let font = UIFont.systemFont(ofSize: 112, weight: .medium)
        let attr = NSAttributedString(
            string: String(ch),
            attributes: [.font: font, .foregroundColor: UIColor.white]
        )
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let advance = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let glyphH = ascent + descent
        let scale = min(CGFloat(px) * 0.88 / max(1, advance),
                        CGFloat(px) * 0.88 / max(1, glyphH))
        ctx.saveGState()
        ctx.translateBy(x: (CGFloat(px) - advance * scale) / 2,
                        y: (CGFloat(px) - glyphH * scale) / 2 + descent * scale)
        ctx.scaleBy(x: scale, y: scale)
        CTLineDraw(line, ctx)   // CoreText 字形 y 向上，方向确定
        ctx.restoreGState()

        guard let raw = ctx.data else { return blank }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        let totalBytes = px * bpr
        let cell = CGFloat(px) / CGFloat(n)

        // CGBitmapContext 内存第 0 行 = y=0 = 字形底部；
        // grid 第 0 行是视觉顶部，故行序翻转。
        var grid = Array(repeating: Array(repeating: false, count: n), count: n)
        for r in 0..<n {
            for c in 0..<n {
                var on = 0
                for sy in 0..<3 {
                    for sx in 0..<3 {
                        let fx = cell * (CGFloat(c) + 0.2 + 0.3 * CGFloat(sx))
                        let fyTop = cell * (CGFloat(r) + 0.2 + 0.3 * CGFloat(sy))
                        let ySrc = needsRowFlip ? (px - 1 - Int(fyTop)) : Int(fyTop)
                        let x = Int(fx)
                        guard ySrc >= 0, ySrc < px, x >= 0, x < px else { continue }
                        let idx = ySrc * bpr + x * 4 + 3   // alpha 通道
                        guard idx >= 0, idx + 3 < totalBytes else { continue }
                        if bytes[idx] > 100 { on += 1 }
                    }
                }
                grid[r][c] = on >= 4
            }
        }

        // 兜底：若几乎全亮，判定采样异常，宁可留空也不再糊成实心块
        let lit = grid.reduce(0) { $0 + $1.filter { $0 }.count }
        if lit > n * n * 7 / 10 { return blank }
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
    /// 折行时的水平对齐（自动折行的长说明句默认左对齐）
    var wrapAlignment: HorizontalAlignment = .leading

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
    private var lineAdvance: CGFloat { lineH + step * 0.5 }

    /// 1.2.1：未显式指定 wrapWidth 时，超过安全宽度（小屏可用区）自动折行，
    /// 避免长句单行绘制被屏幕右缘裁掉。
    private var effectiveWrap: CGFloat? {
        if let wrapWidth { return wrapWidth }
        return singleLineWidth > 330 ? 330 : nil
    }

    /// 折行布局：返回每行 [字符下标]
    private var lines: [[Int]] {
        guard let wrap = effectiveWrap, wrap > charWidth else { return [Array(0..<chars.count)] }
        var result: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for i in 0..<chars.count {
            let w = charWidth + (current.isEmpty ? 0 : charGap)
            if x + w > wrap, !current.isEmpty {
                result.append(current)
                current = []
                x = charWidth
            } else {
                x += w
            }
            current.append(i)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private var totalWidth: CGFloat { effectiveWrap ?? singleLineWidth }
    /// 行距大于行高，末行底部也要算进去，否则多行最后一行被裁
    private var totalHeight: CGFloat {
        CGFloat(max(0, lines.count - 1)) * lineAdvance + lineH
    }

    var body: some View {
        Canvas { context, _ in
            let layout = lines
            for (li, line) in layout.enumerated() {
                let lineWidth = CGFloat(line.count) * charWidth + CGFloat(max(0, line.count - 1)) * charGap
                let originX: CGFloat = {
                    if let wrap = effectiveWrap {
                        switch wrapAlignment {
                        case .leading: return 0
                        case .trailing: return wrap - lineWidth
                        default: return (wrap - lineWidth) / 2
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
