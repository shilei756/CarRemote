import SwiftUI
import UIKit

// MARK: - 颜色十六进制互转

extension Color {
    /// "RRGGBB" / "#RRGGBB" → Color
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else {
            r = 0.07; g = 0.07; b = 0.07
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Color → "RRGGBB"（失败回落墨黑）
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "1C1C1E" }
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

// MARK: - 油量点阵配色选择

/// 预设配色（与 FuelDotBar 默认调色板同源，另加两款中性色）
struct FuelColorPreset: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
}

enum FuelColorPresets {
    static let all: [FuelColorPreset] = [
        FuelColorPreset(name: "朱红", hex: "FF3B30"),
        FuelColorPreset(name: "橙",   hex: "FF9500"),
        FuelColorPreset(name: "琥珀", hex: "FFCC00"),
        FuelColorPreset(name: "草绿", hex: "34C759"),
        FuelColorPreset(name: "青",   hex: "00C7BE"),
        FuelColorPreset(name: "海蓝", hex: "0A84FF"),
        FuelColorPreset(name: "靛蓝", hex: "5E5CE6"),
        FuelColorPreset(name: "紫",   hex: "BF5AF2"),
        FuelColorPreset(name: "玫红", hex: "FF375F"),
        FuelColorPreset(name: "橘",   hex: "FF6B22"),
        FuelColorPreset(name: "墨黑", hex: "1C1C1E"),
        FuelColorPreset(name: "石墨", hex: "6E6E73")
    ]
}

/// 油量点阵配色面板：默认「多色随机」，可切预设单色或自定义任意颜色。
/// 绑定 hex：空字符串 = 多色随机模式。
struct FuelColorPickerSheet: View {
    @Binding var hex: String
    @Environment(\.dismiss) private var dismiss
    @State private var custom: Color = Color(hex: "0A84FF")

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private var previewColor: Color? {
        hex.isEmpty ? nil : Color(hex: hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    DotCnText(text: "油量配色", size: 16, color: Mono.paperInk)
                    DotCnText(text: "默认多色随机，也可指定单色", size: 8, color: Mono.paperDim)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Mono.paperDim)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭配色面板")
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            // 实时预览
            VStack(alignment: .leading, spacing: 10) {
                FuelDotBar(progress: 0.62, rows: 6, color: previewColor)
                    .frame(height: 30)
                DotCnText(
                    text: hex.isEmpty ? "当前：多色随机" : "当前：自定义单色",
                    size: 8, color: Mono.paperDim
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)

            Hairline(color: Mono.paperHair).padding(.top, 18)

            // 多色随机
            Button {
                hex = ""
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: FuelDotBar.palette,
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 34, height: 34)
                        if hex.isEmpty {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 1)
                        }
                    }
                    DotCnText(text: "多色随机（默认）", size: 10, color: Mono.paperInk)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            DotCnText(text: "预设单色", size: 8, color: Mono.paperDim)
                .padding(.horizontal, 22)
                .padding(.top, 14)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(FuelColorPresets.all) { preset in
                    Button {
                        hex = preset.hex
                        dismiss()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(hex: preset.hex))
                                .frame(height: 38)
                            if hex.uppercased() == preset.hex.uppercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)

            // 自定义
            HStack(spacing: 12) {
                ColorPicker("自定义颜色", selection: $custom, supportsOpacity: false)
                    .font(.system(size: 12))
                    .foregroundStyle(Mono.paperInk)
                Spacer()
                Button {
                    hex = custom.hexString
                    dismiss()
                } label: {
                    Text("应用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Mono.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Mono.paperInk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .background(Mono.paper)
        .onAppear {
            if !hex.isEmpty { custom = Color(hex: hex) }
        }
    }
}
