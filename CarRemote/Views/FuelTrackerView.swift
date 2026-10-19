import SwiftUI
import CarCore

/// 油耗统计（本地记录）
struct FuelTrackerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: FuelViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: FuelViewModel(appState: appState))
    }

    @State private var showAddSheet = false
    @State private var editingRecord: FuelRecord?

    var body: some View {
        NavStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    if viewModel.records.isEmpty {
                        EmptyStateView(
                            systemImage: "fuelpump",
                            title: "还没有加油记录",
                            message: "每次加油后记一笔，自动帮你算油耗"
                        )
                    } else {
                        recordsList
                    }
                    algorithmCard
                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(WebConsoleBackground())
            .inlineTitle("油耗统计")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加加油记录")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddFuelSheet(viewModel: viewModel)
            }
            .sheet(item: $editingRecord) { record in
                AddFuelSheet(viewModel: viewModel, editing: record)
            }
        }
    }

    // MARK: - 汇总（照搬网页版 fuelPage：最新油耗大数字 + 3 列统计网格）

    private var summaryCard: some View {
        VStack(spacing: 12) {
            // 最新油耗大数字卡（网页版 fuelLatest 3xl 粗体）
            SectionCard(sakura: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        CardTitleText(text: "最新油耗")
                        Spacer()
                        if viewModel.lastConsumption != nil {
                            Text("L/100km")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WebTheme.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(WebTheme.blue.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(viewModel.lastConsumption.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        if let odo = viewModel.currentOdometerKm {
                            Text("当前里程 \(CarStatus.format(odo)) km")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 统计网格（网页版 grid-cols-3 + fuel-stat-value 17px/800）
            SectionCard(title: "油耗统计", sakura: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 14
                ) {
                    fuelStat(value: viewModel.averageConsumption.map { String(format: "%.1f", $0) } ?? "--", label: "平均油耗", unit: "L/100km")
                    fuelStat(value: String(format: "%.1f", viewModel.totalLiters), label: "累计加油", unit: "L")
                    fuelStat(value: String(format: "%.0f", viewModel.totalSpend), label: "累计油费", unit: "元")
                    fuelStat(value: "\(viewModel.records.count)", label: "加油次数", unit: "次")
                    fuelStat(
                        value: viewModel.averageConsumption.map { String(format: "%.2f", $0 * 7.8) } ?? "--",
                        label: "每公里成本",
                        unit: "元"
                    )
                    fuelStat(
                        value: viewModel.totalLiters > 0 ? String(format: "%.1f", viewModel.totalSpend / viewModel.totalLiters) : "--",
                        label: "平均油价",
                        unit: "元/L"
                    )
                }
            }
        }
    }

    /// 网页版 fuel-stat-value：17px/800 等宽数字 + 小标签
    private func fuelStat(value: String, label: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WebTheme.txt)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(WebTheme.muted)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(WebTheme.faint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 记录列表（网页版记录行：日期粗体 + 里程/油量 + 油耗徽章）

    private var recordsList: some View {
        SectionCard(title: "加油记录", sakura: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider()
                            .overlay(WebTheme.border)
                            .padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(dateText(record.date))
                                .font(.system(size: 13.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            // 点名字旁的笔进入编辑（输错可改，也可删）
                            Button {
                                editingRecord = record
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(WebTheme.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("编辑这条加油记录")
                        }
                            Text("\(CarStatus.format(record.odometerKm)) km · \(CarStatus.format(record.liters)) L\(record.isFull ? " · 加满" : "")")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.muted)
                            if let consumption = record.consumption(since: index > 0 ? viewModel.records[index - 1] : nil) {
                                // 网页版 fuel-tag 徽章
                                Text("\(String(format: "%.1f", consumption)) L/100km")
                                    .font(.system(size: 10, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(WebTheme.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(WebTheme.green.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                        Spacer()
                        if let price = record.pricePerLiter {
                            Text("\(String(format: "%.2f", price)) 元/L")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                        } else if let cost = record.totalCost {
                            Text("\(String(format: "%.0f", cost)) 元")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                        }
                        Button {
                            viewModel.delete(record)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除这条加油记录")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - 算法与用法说明（网页版同款"满箱法"）

    private var algorithmCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("油耗算法与用法", systemImage: "function")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            Text("算法：满箱法。两次都「加满」时，这两次加油量之和 ÷ 期间行驶里程 × 100 = 该段油耗（L/100km）。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("用法：每次加油都记一笔——输入当时的里程表读数和加油升数（尽量选「加满」）；第二次加满后自动算出这段的真实油耗。没加满的记录只累计油量，不参与油耗计算。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("填错了？点记录日期旁的 ✏️ 修改，或点右侧 🗑 删除重录。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(WebTheme.border.opacity(0.6), lineWidth: 1)
        )
    }
}

/// 添加 / 编辑加油记录（editing 非空 = 编辑模式）
struct AddFuelSheet: View {
    @ObservedObject var viewModel: FuelViewModel
    var editing: FuelRecord?
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litersText = ""
    @State private var priceText = ""
    @State private var isFull = true
    @State private var note = ""

    var body: some View {
        NavStack {
            Form {
                Section("加油信息") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("里程表")
                        Spacer()
                        TextField("km", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("加油量")
                        Spacer()
                        TextField("L", text: $litersText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("加满", isOn: $isFull)
                }
                Section("费用（可选）") {
                    HStack {
                        Text("单价")
                        Spacer()
                        TextField("元/L", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("备注（可选）") {
                    TextField("加油站 / 备注", text: $note)
                }
            }
            .inlineTitle(editing != nil ? "修改加油记录" : "记一笔油耗")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: CompatToolbarPlacement.topLeading) {
                    Button(editing != nil ? "保存修改" : "保存") { save() }
                        .disabled(!canSave)
                        .font(.system(size: 17, weight: .bold))
                }
            }
        }
        .onAppear {
            if let record = editing {
                date = record.date
                odometerText = String(record.odometerKm)
                litersText = String(record.liters)
                priceText = record.pricePerLiter.map { String($0) } ?? ""
                isFull = record.isFull
                note = record.note
            }
        }
    }

    private var canSave: Bool {
        Double(odometerText) != nil && Double(litersText) != nil
    }

    private func save() {
        guard let odometer = Double(odometerText), let liters = Double(litersText) else { return }
        let price = Double(priceText)
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var record = editing {
            // 编辑：保留原 id
            record.date = date
            record.odometerKm = odometer
            record.liters = liters
            record.pricePerLiter = price
            record.totalCost = price.map { $0 * liters }
            record.isFull = isFull
            record.note = noteText
            viewModel.update(record)
        } else {
            let record = FuelRecord(
                date: date,
                odometerKm: odometer,
                liters: liters,
                pricePerLiter: price,
                totalCost: price.map { $0 * liters },
                isFull: isFull,
                note: noteText
            )
            viewModel.add(record)
        }
        dismiss()
    }
}
