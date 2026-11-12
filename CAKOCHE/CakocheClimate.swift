import SwiftUI
import CarCore

/// 空调页：座舱气流示意 + 0.5℃ 步进 + 制冷 / 关闭 / 制热 三段。
/// 指令是真下发：1.2.4 起恒定走网站「新版空调通道」（newAC / 开放平台），
/// 授权由站主网站统一判定。1.2.0：全点阵化 + 所有下发二次确认。
struct CakocheClimatePage: View {
    @ObservedObject var control: CakocheControl
    @State private var temp: Double = 22.0
    @State private var mode = 0          // 0 制冷 / 1 关闭 / 2 制热
    @State private var pulse = false
    /// 1.2.0：二次确认（模式名 + 下发温度）
    @State private var confirmMode: Int?
    /// 1.2.4：网站授权入口
    @State private var showACAuth = false

    private let modeNames = ["制冷", "关闭", "制热"]
    private let modeSymbols = ["snowflake", "power", "flame"]

    private var tempText: String { String(format: "%.1f", temp) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    DotCnText(text: "空 调", size: 16, color: Mono.paperInk)
                    DotCnText(text: "新版空调通道 · 授权由网站统一校验", size: 8, color: Mono.paperDim)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)

                // 座舱俯视 + 气流波纹（关闭时静止，制冷/制热时缓慢呼吸）
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
                    VStack(spacing: 10) {
                        Image(systemName: modeSymbols[mode])
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(mode == 1 ? Mono.paperDim : Mono.paperInk)
                        DotCnText(text: modeNames[mode], size: 10, color: Mono.paperDim)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .onAppear { pulse = true }

                HStack(alignment: .bottom, spacing: 14) {
                    DotMatrixText(text: tempText, size: 46, color: Mono.paperInk)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        DotCnText(text: "摄氏度", size: 9, color: Mono.paperDim)
                        DotCnText(text: "0.5℃ 步进", size: 8, color: Mono.paperDim)
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
                            // 1.2.0：所有空调下发都需二次确认
                            confirmMode = i
                        } label: {
                            VStack(spacing: 7) {
                                DotCnText(text: modeNames[i], size: 10,
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
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: r.ok ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(r.ok ? Mono.paperInk : Mono.red)
                            .padding(.top, 3)
                        DotCnText(text: "\(r.command) · \(r.detail) · \(r.timeText)", size: 8,
                                  color: Mono.paperDim, wrapAlignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }

                DotCnText(text: "车机空调以 1℃ 为单位设定；界面支持 0.5℃ 微调，下发时自动取整（16~32）。",
                          size: 8, color: Mono.paperDim, wrapAlignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)

                // MARK: 1.2.4 授权入口（新版通道需网站先授权）
                Button { showACAuth = true } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Mono.paperInk)
                        DotCnText(text: "新版空调授权 · 扫码开通 / 同步网站凭证",
                                  size: 9, color: Mono.paperInk, wrapAlignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Mono.paperHair)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .overlay(Rectangle().stroke(Mono.paperHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .accessibilityLabel("新版空调授权，点击开通或同步网站授权")
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showACAuth) {
            CakocheACAuthSheet()
        }
        // 1.2.0：二次确认弹窗
        .alert("确认下发空调指令", isPresented: Binding(
            get: { confirmMode != nil },
            set: { if !$0 { confirmMode = nil } }
        )) {
            Button("取消", role: .cancel) { confirmMode = nil }
            Button("确认下发", role: .destructive) {
                if let selected = confirmMode {
                    Task { await applyMode(selected) }
                }
                confirmMode = nil
            }
        } message: {
            Text("将下发「\(confirmMode.map { modeNames[$0] } ?? "")」（\(Int(temp.rounded()))℃）到车机空调。")
        }
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
