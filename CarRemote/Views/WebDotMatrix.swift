import SwiftUI
import UIKit

// =============================================================
// 网页同款点阵计量条（1.11.7，正式版专用）
//
// 油量 / 电压都用它：横排小方块点阵，点亮比例 = 数值占比，
// 「充电式脉冲」——一道高亮光带沿点亮区来回扫过（TimelineView + Canvas，
// 一次绘制全部点，几百个点也不会掉帧）。点击点阵弹出配色面板，
// 支持多色随机 / 预设单色 / 自定义任意颜色，颜色持久化到本地。
// 对齐网页版 /user_info 的油量点阵与电压点阵观感。
// =============================================================

// MARK: - 颜色 hex 互转（正式 target 自带，避免依赖 CAKOCHE 目录里的同名扩展）

private func dmColor(hex: String) -> Color {
    let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard s.count == 6 else { return Color(hex: 0x00C7BE) }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return Color(hex: UInt(v))
}

private func dmHex(_ color: Color) -> String {
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "00C7BE" }
    return String(format: "%02X%02X%02X",
                  Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}

// MARK: - 配色持久化（独立轻量存储，不侵入 AppSettings 的 Codable 迁移）

enum DotMatrixColorStore {
    private static let key = "carremote.dotMatrixColorHex"
    /// 空字符串 = 默认青色（网页版同款），单色 hex = 指定颜色
    static var hex: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - 预设配色（与网页版点阵取色一致的高饱和色板）

struct DotPreset: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

enum DotPresets {
    static let all: [DotPreset] = [
        DotPreset(name: "青", hex: "00C7BE"),
        DotPreset(name: "海蓝", hex: "0A84FF"),
        DotPreset(name: "草绿", hex: "34C759"),
        DotPreset(name: "琥珀", hex: "FFCC00"),
        DotPreset(name: "橙", hex: "FF9500"),
        DotPreset(name: "朱红", hex: "FF3B30"),
        DotPreset(name: "紫", hex: "BF5AF2"),
        DotPreset(name: "粉", hex: "FF375F")
    ]
}

// MARK: - 点阵计量条

struct WebDotMatrix: View {
    /// 0~1 的占比（油量 = 剩余/油箱；电压 = (V-10.5)/4.5）
    var fraction: Double
    /// 行数（网页版油量 2~3 行、电压 2 行）
    var rows: Int = 3
    /// 列数
    var cols: Int = 34
    var height: CGFloat = 22
    /// 点阵配色 hex（来自 DotMatrixColorStore.hex），空 = 默认青
    var colorHex: String

    @State private var showPicker = false

    private var baseColor: Color {
        colorHex.isEmpty ? Color(hex: 0x00C7BE) : dmColor(hex: colorHex)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let gap: CGFloat = 1.6
                let cw = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let ch = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
                guard cw > 0, ch > 0 else { return }
                let p = max(0, min(1, fraction))
                let litCells = Int((Double(cols * rows) * p).rounded())

                for r in 0..<rows {
                    for c in 0..<cols {
                        // 从下往上、从左往右填充（网页版电量条习惯）
                        let index = r * cols + c
                        let rect = CGRect(x: CGFloat(c) * (cw + gap),
                                          y: CGFloat(rows - 1 - r) * (ch + gap),
                                          width: cw, height: ch)
                        if index < litCells {
                            // 充电式脉冲：一道高亮光带沿列方向循环扫过
                            let wave = (sin(t * 2.2 - Double(c) * 0.38) + 1) / 2  // 0~1
                            let brightness = 0.55 + 0.45 * wave
                            let dot = baseColor.opacity(brightness)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: min(cw, ch) * 0.22),
                                     with: .color(dot))
                        } else {
                            ctx.fill(Path(roundedRect: rect, cornerRadius: min(cw, ch) * 0.22),
                                     with: .color(WebTheme.track))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture { showPicker = true }
        .accessibilityLabel("点阵计量 \(Int(fraction * 100))%，点击更换颜色")
        .sheet(isPresented: $showPicker) {
            DotColorPickerSheet()
        }
    }
}

// MARK: - 配色面板

struct DotColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = DotMatrixColorStore.hex
    @State private var customColor: Color = Color(hex: 0x0A84FF)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("点阵配色")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WebTheme.txt)
                    Text("默认青色，可选单色或自定义")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(WebTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            // 实时预览
            WebDotMatrix(fraction: 0.62, rows: 2, cols: 30, height: 26,
                         colorHex: current)
                .padding(.vertical, 4)

            // 默认青色
            Button {
                current = ""
                DotMatrixColorStore.hex = ""
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0x00C7BE))
                            .frame(width: 34, height: 34)
                        if current.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    Text("默认青色")
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.txt)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Text("预设单色")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WebTheme.muted)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(DotPresets.all) { preset in
                    Button {
                        current = preset.hex
                        DotMatrixColorStore.hex = preset.hex
                        dismiss()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(dmColor(hex: preset.hex))
                                .frame(height: 38)
                            if current.uppercased() == preset.hex.uppercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }

            // 自定义颜色
            HStack(spacing: 12) {
                ColorPicker("自定义颜色", selection: $customColor, supportsOpacity: false)
                    .font(.system(size: 13))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Button {
                    let h = dmHex(customColor)
                    current = h
                    DotMatrixColorStore.hex = h
                    dismiss()
                } label: {
                    Text("应用")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(WebTheme.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetentsCompat()
        .onAppear {
            if !current.isEmpty { customColor = dmColor(hex: current) }
        }
    }
}

// MARK: - detent 兼容垫片

extension View {
    @ViewBuilder
    func presentationDetentsCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium])
        } else {
            self
        }
    }
}
