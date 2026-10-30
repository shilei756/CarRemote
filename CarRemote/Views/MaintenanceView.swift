import SwiftUI
import CarCore

/// 智能维保（对照网页版模板：上次保养基准 + 行业标准周期的零部件状态网格）
struct MaintenanceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: MaintenanceViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: MaintenanceViewModel(appState: appState))
    }

    @State private var showEditLastService = false

    var body: some View {
        NavStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerCard
                    partsGrid
                    if !viewModel.records.isEmpty {
                        recordsCard
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(WebConsoleBackground())
            .inlineTitle("智能维保")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("修改上次保养") { showEditLastService = true }
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .sheet(isPresented: $showEditLastService) {
                EditLastServiceSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - 行业标准保养周期（km 区间 / 天数区间，与网页版模板一致）

    private struct PartSpec {
        let name: String
        let symbol: String
        let kmInterval: Double
        let dayInterval: Int
    }

    private let parts: [PartSpec] = [
        PartSpec(name: "机油及机油滤清器", symbol: "drop.fill", kmInterval: 5000, dayInterval: 183),
        PartSpec(name: "空调滤芯", symbol: "wind", kmInterval: 10000, dayInterval: 365),
        PartSpec(name: "空气滤清器滤芯", symbol: "wind", kmInterval: 10000, dayInterval: 365),
        PartSpec(name: "汽油滤清器", symbol: "arrow.down.circle", kmInterval: 20000, dayInterval: 731),
        PartSpec(name: "火花塞", symbol: "bolt.fill", kmInterval: 20000, dayInterval: 731),
        PartSpec(name: "制动液", symbol: "drop.triangle", kmInterval: 40000, dayInterval: 731),
        PartSpec(name: "发动机冷却液", symbol: "thermometer.medium", kmInterval: 40000, dayInterval: 731)
    ]

    // MARK: - 顶部：总里程 / 上次保养里程 / 上次保养日期 + 两徽章

    private var headerCard: some View {
        SectionCard(sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("总里程\(updatedSuffix)")
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.muted)

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentOdometerKm.map { CarStatus.format($0) } ?? "--")
                            .font(.system(size: 26, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("当前总里程")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastService.map { CarStatus.format($0.odometerKm) } ?? "--")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("上次保养里程")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastService.map { dateText($0.date) } ?? "--")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("上次保养日期")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                    }
                    Spacer(minLength: 0)
                }

                // 徽章行：距下次保养 X km · 剩余 X 天（取最紧的机油周期）
                if let last = lastService, let odo = viewModel.currentOdometerKm {
                    HStack(spacing: 8) {
                        let kmLeft = parts[0].kmInterval - (odo - last.odometerKm)
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 9))
                            Text(kmLeft >= 0 ? "距下次保养 \(CarStatus.format(kmLeft)) km" : "已超 \(CarStatus.format(-kmLeft)) km")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(WebTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WebTheme.green.opacity(0.10))
                        .clipShape(Capsule())

                        let daysLeft = parts[0].dayInterval - Int(Date().timeIntervalSince(last.date) / 86400)
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9))
                            Text(daysLeft >= 0 ? "剩余 \(daysLeft) 天" : "超期 \(abs(daysLeft)) 天")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(WebTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WebTheme.green.opacity(0.10))
                        .clipShape(Capsule())
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("点右上角「修改上次保养」录入保养里程与日期，零部件状态会按行业标准周期自动计算")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.amber)
                }
            }
        }
    }

    private var updatedSuffix: String {
        if let updated = appState.statusUpdatedAt {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return "（\(f.string(from: updated)) 更新）"
        }
        return "（暂未获取车况）"
    }

    /// 上次保养基准 = 最近一条维保记录
    private var lastService: MaintenanceRecord? {
        viewModel.records.first
    }

    // MARK: - 车辆零部件网格（网页版 2 列卡片：状态 + 剩余 km · 天 + 进度条）

    private var partsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("车辆零部件")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            Text("根据总里程/时间建议（行业标准周期）")
                .font(.system(size: 11))
                .foregroundStyle(WebTheme.muted)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    partCard(part)
                }
            }
        }
    }

    private func partCard(_ part: PartSpec) -> some View {
        let usageKm: Double? = {
            guard let last = lastService, let odo = viewModel.currentOdometerKm else { return nil }
            return odo - last.odometerKm
        }()
        let usageDays: Int? = lastService.map { Int(Date().timeIntervalSince($0.date) / 86400) }
        let kmLeft = usageKm.map { part.kmInterval - $0 }
        let daysLeft = usageDays.map { part.dayInterval - $0 }
        // 状态：任一维度到期 = 需要保养；任一维度剩余 < 15% = 即将保养；否则良好
        let due = (kmLeft.map { $0 <= 0 } ?? false) || (daysLeft.map { $0 <= 0 } ?? false)
        let soon = !due && ((kmLeft.map { $0 < part.kmInterval * 0.15 } ?? false) || (daysLeft.map { $0 < Int(Double(part.dayInterval) * 0.15) } ?? false))
        let color: Color = due ? WebTheme.red : (soon ? WebTheme.amber : WebTheme.green)
        let statusText = due ? "需要保养" : (soon ? "即将保养" : "状态良好")
        // 进度条：已用周期比例（km / 天 取较大者）
        let kmRatio = usageKm.map { min(max($0 / part.kmInterval, 0), 1) } ?? 0
        let dayRatio = usageDays.map { min(max(Double($0) / Double(part.dayInterval), 0), 1) } ?? 0
        let ratio = max(kmRatio, dayRatio)

        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: part.symbol)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(part.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WebTheme.txt)
                .lineLimit(1)
            Text(statusText + " ›")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(remainingText(kmLeft: kmLeft, daysLeft: daysLeft))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(WebTheme.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WebTheme.card2).frame(height: 4)
                    Capsule().fill(color.opacity(0.7)).frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(due ? WebTheme.red.opacity(0.35) : WebTheme.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func remainingText(kmLeft: Double?, daysLeft: Int?) -> String {
        var texts: [String] = []
        if let kmLeft {
            texts.append(kmLeft >= 0 ? "剩 \(CarStatus.format(kmLeft)) km" : "超 \(CarStatus.format(-kmLeft)) km")
        }
        if let daysLeft {
            texts.append(daysLeft >= 0 ? "\(daysLeft) 天" : "超 \(abs(daysLeft)) 天")
        }
        return texts.isEmpty ? "--" : texts.joined(separator: " · ")
    }

    // MARK: - 保养历史

    private var recordsCard: some View {
        SectionCard(title: "保养历史", sakura: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider()
                            .overlay(WebTheme.border)
                            .padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateText(record.date))
                                .font(.system(size: 13.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Text("\(record.item) · \(CarStatus.format(record.odometerKm)) km")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.muted)
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                        Spacer()
                        if let cost = record.cost {
                            Text("¥\(String(format: "%.0f", cost))")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                        }
                        Button {
                            viewModel.delete(at: IndexSet(integer: index))
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除这条保养记录")
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// 修改上次保养（录入保养里程与日期，作为零部件计算基准）
struct EditLastServiceSheet: View {
    @ObservedObject var viewModel: MaintenanceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var odometerText = ""
    @State private var costText = ""
    @State private var note = ""

    var body: some View {
        NavStack {
            Form {
                Section("上次保养") {
                    DatePicker("保养日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("保养时里程")
                        Spacer()
                        TextField("km", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("花费")
                        Spacer()
                        TextField("元（可选）", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("备注（可选）") {
                    TextField("如：4S 店常规保养", text: $note)
                }
                Section {
                    Text("保存后，各零部件按行业标准周期（机油 5000km/183 天、滤芯 10000km/365 天等）从此基准自动计算状态与剩余量。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .inlineTitle("修改上次保养")
            .hideScrollBackground()
            .background(WebConsoleBackground())
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: CompatToolbarPlacement.topLeading) {
                    Button("保存") { save() }
                        .disabled(Double(odometerText) == nil)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .onAppear {
                if let last = viewModel.records.first {
                    date = last.date
                    odometerText = String(Int(last.odometerKm))
                    costText = last.cost.map { String(Int($0)) } ?? ""
                    note = last.note
                }
            }
        }
    }

    private func save() {
        guard let odometer = Double(odometerText) else { return }
        let record = MaintenanceRecord(
            id: viewModel.records.first?.id ?? UUID().uuidString,
            date: date,
            odometerKm: odometer,
            item: viewModel.records.first?.item ?? "常规保养",
            cost: Double(costText),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            nextOdometerKm: nil,
            nextDate: nil
        )
        if viewModel.records.first != nil {
            viewModel.updateFirst(record)
        } else {
            viewModel.add(record)
        }
        dismiss()
    }
}
