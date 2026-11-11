import SwiftUI
import CarCore

/// 空调页：座舱气流示意 + 0.5℃ 步进 + COOL / STOP / HEAT 三段。
/// 指令是真下发（开放平台 newAC 通道），不是源作品的预览动画。
struct CakocheClimatePage: View {
    @ObservedObject var control: CakocheControl
    @State private var temp: Double = 22.0
    @State private var mode = 1          // 0 COOL / 1 STOP / 2 HEAT
    @State private var pulse = false

    private let modeNames = ["COOL", "STOP", "HEAT"]

    private var tempText: String { String(format: "%.1f", temp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                DotMatrixText(text: "CLIMATE", size: 20, color: Mono.paperInk)
                Text("座舱空调 · 指令直接下发至车辆")
                    .font(.system(size: 11))
                    .foregroundStyle(Mono.paperDim)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)

            // 座舱俯视 + 气流波纹（STOP 时静止，COOL/HEAT 时缓慢呼吸）
            ZStack {
                RoundedRectangle(cornerRadius: 90, style: .continuous)
                    .stroke(Mono.paperHair, lineWidth: 1)
                    .frame(width: 186, height: 236)
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .stroke(
                            mode == 1 ? Mono.paperHair
                                : (mode == 0 ? Mono.paperInk : Mono.red).opacity(0.32),
                            lineWidth: 1
                        )
                        .frame(width: 44 + CGFloat(i) * 44, height: 110 + CGFloat(i) * 44)
                        .scaleEffect(pulse ? 1.05 : 0.95)
                        .opacity(pulse ? 0.9 : 0.4)
                        .animation(
                            .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.28),
                            value: pulse
                        )
                }
                VStack(spacing: 8) {
                    Image(systemName: mode == 2 ? "flame" : (mode == 0 ? "snowflake" : "power"))
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(mode == 1 ? Mono.paperDim : Mono.paperInk)
                    DotMatrixText(text: modeNames[mode], size: 10, color: Mono.paperDim)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .onAppear { pulse = true }

            HStack(alignment: .bottom, spacing: 14) {
                DotMatrixText(text: tempText, size: 46, color: Mono.paperInk)
                VStack(alignment: .leading, spacing: 4) {
                    DotMatrixText(text: "DEG C", size: 9, color: Mono.paperDim)
                    Text("0.5℃ 步进").font(.system(size: 10)).foregroundStyle(Mono.paperDim)
                }
                .padding(.bottom, 6)
                Spacer()
                VStack(spacing: 10) {
                    stepButton("plus") { temp = min(32, temp + 0.5) }
                    stepButton("minus") { temp = max(16, temp - 0.5) }
                }
            }
            .padding(.horizontal, 22)

            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { i in
                    Button {
                        mode = i
                        Task { await applyMode(i) }
                    } label: {
                        VStack(spacing: 7) {
                            DotMatrixText(text: modeNames[i], size: 9,
                                          color: mode == i ? Mono.paper : Mono.paperDim)
                            Rectangle()
                                .fill(mode == i ? Mono.red : Color.clear)
                                .frame(width: 16, height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(mode == i ? Mono.paperInk : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(modeNames[i])
                    .accessibilityAddTraits(mode == i ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            if let r = control.receipt {
                HStack(spacing: 8) {
                    Image(systemName: r.ok ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(r.ok ? Mono.paperInk : Mono.red)
                    Text("\(r.command) · \(r.detail) · \(r.timeText)")
                        .font(.system(size: 11))
                        .foregroundStyle(Mono.paperDim)
                        .lineLimit(1)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
            }

            Text("车机空调以 1℃ 为单位设定；界面支持 0.5℃ 微调，下发时自动取整（16~32）。")
                .font(.system(size: 10))
                .foregroundStyle(Mono.paperDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Mono.paperInk)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Mono.paperHair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "升高 0.5 度" : "降低 0.5 度")
    }

    @MainActor
    private func applyMode(_ selected: Int) async {
        let rounded = Int(temp.rounded())
        switch selected {
        case 0, 2:
            await control.run(.openAir, temperature: rounded)
        case 1:
            await control.run(.closeAir)
        default:
            break
        }
    }
}
