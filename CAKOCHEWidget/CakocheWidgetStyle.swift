import SwiftUI
import UIKit

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

enum WidgetDotCnCache {
    static let rowsPerChar = 16
    static let colsPerChar = 16

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
        let px = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
            UIColor.white.setFill()
            let font = UIFont.systemFont(ofSize: 108, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let s = String(ch) as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (CGFloat(px) - sz.width) / 2,
                               y: (CGFloat(px) - sz.height) / 2), withAttributes: attrs)
        }
        guard let data = img.cgImage?.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return Array(repeating: Array(repeating: false, count: colsPerChar), count: rowsPerChar)
        }
        var grid = Array(repeating: Array(repeating: false, count: colsPerChar), count: rowsPerChar)
        let cellW = CGFloat(px) / CGFloat(colsPerChar)
        let cellH = CGFloat(px) / CGFloat(rowsPerChar)
        for r in 0..<rowsPerChar {
            for c in 0..<colsPerChar {
                var onCount = 0
                for sy in 0..<2 {
                    for sx in 0..<2 {
                        let x = Int(cellW * (CGFloat(c) + 0.25 + 0.5 * CGFloat(sx)))
                        let y = Int(cellH * (CGFloat(r) + 0.25 + 0.5 * CGFloat(sy)))
                        let idx = (y * px + x) * 4 + 3
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

/// 中文点阵文本（小组件版）：任意文字可用
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

    private var totalWidth: CGFloat {
        CGFloat(chars.count) * charWidth + CGFloat(max(0, chars.count - 1)) * charGap
    }
    private var totalHeight: CGFloat { CGFloat(WidgetDotCnCache.rowsPerChar) * step }

    var body: some View {
        Canvas { context, _ in
            for (idx, grid) in grids.enumerated() {
                let baseX = CGFloat(idx) * (charWidth + charGap)
                for (row, rowBits) in grid.enumerated() {
                    for (col, on) in rowBits.enumerated() where on {
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
