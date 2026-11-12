import SwiftUI
import UIKit
import CoreText

/// CAKOCHE 小组件专用配色：与 App 内 Mono 完全一致（低饱和黑白 + 唯一红）。
/// 小组件进程不编译 CAKOCHE/ 目录，这里独立定义一份，值保持同步。
enum WMono {
    static let ink = Color(white: 0.965)
    static let dim = Color(white: 0.42)
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

// MARK: - 中文点阵（与 App 内 DotCnText 同实现，小组件进程独立编译）
// 1.2.1：透明底 + 只读 alpha，修复不透明黑底导致的全亮马赛克；16×16 → 12×12。
enum WidgetDotCnCache {
    static let rowsPerChar = 12
    static let colsPerChar = 12
    private static let px = 144

    /// 自探测位图内存行序，避免中文上下颠倒（真机自行校准）
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
        return first > 100 || last <= 100
    }()

    private static let lock = NSLock()
    private static var cache: [String: [[[Bool]]]] = [:]

    static func grids(for text: String) -> [[[Bool]]] {
        lock.lock()
        if let hit = cache[text] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let built = text.map { sampleCharacter($0) }
        lock.lock()
        if cache.count > 200 { cache.removeAll(keepingCapacity: true) }
        cache[text] = built
        lock.unlock()
        return built
    }

    private static func sampleCharacter(_ ch: Character) -> [[Bool]] {
        let n = rowsPerChar
        let blank = Array(repeating: Array(repeating: false, count: n), count: n)
        guard let ctx = CGContext(
            data: nil, width: px, height: px,
            bitsPerComponent: 8, bytesPerRow: px * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return blank }

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
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        guard let raw = ctx.data else { return blank }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        let totalBytes = px * bpr
        let cell = CGFloat(px) / CGFloat(n)

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
                        let idx = ySrc * bpr + x * 4 + 3
                        guard idx >= 0, idx + 3 < totalBytes else { continue }
                        if bytes[idx] > 100 { on += 1 }
                    }
                }
                grid[r][c] = on >= 4
            }
        }

        let lit = grid.reduce(0) { $0 + $1.filter { $0 }.count }
        if lit > n * n * 7 / 10 { return blank }
        return grid
    }
}

/// 中文点阵文本（小组件版）：任意文字可用；超过小号组件安全宽度自动折行
struct WidgetDotCnText: View {
    let text: String
    var size: CGFloat = 9
    var color: Color = WMono.dim
    var gapRatio: CGFloat = 0.22

    private var unit: CGFloat { size / CGFloat(WidgetDotCnCache.rowsPerChar) }
    private var step: CGFloat { unit * (1 + gapRatio) }
    private var dot: CGFloat { unit * (1 - gapRatio * 0.45) }
    private var charWidth: CGFloat { CGFloat(WidgetDotCnCache.colsPerChar) * step }
    private var charGap: CGFloat { step * 0.55 }

    private var chars: [Character] { Array(text) }
    private var grids: [[[Bool]]] { WidgetDotCnCache.grids(for: text) }

    private var singleLineWidth: CGFloat {
        CGFloat(chars.count) * charWidth + CGFloat(max(0, chars.count - 1)) * charGap
    }
    private var lineH: CGFloat { CGFloat(WidgetDotCnCache.rowsPerChar) * step }
    private var lineAdvance: CGFloat { lineH + step * 0.5 }
    /// 小号小组件可用宽约 132pt，超出即折行，避免被裁
    private var effectiveWrap: CGFloat? { singleLineWidth > 132 ? 132 : nil }

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
    private var totalHeight: CGFloat {
        CGFloat(max(0, lines.count - 1)) * lineAdvance + lineH
    }

    var body: some View {
        Canvas { context, _ in
            let layout = lines
            for (li, line) in layout.enumerated() {
                for (pos, charIdx) in line.enumerated() where charIdx < grids.count {
                    let grid = grids[charIdx]
                    let baseX = CGFloat(pos) * (charWidth + charGap)
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
