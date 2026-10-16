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

    var body: some View {
        NavigationStack {
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
                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(WebConsoleBackground())
            .navigationTitle("油耗统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                            Text(dateText(record.date))
                                .font(.system(size: 13.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
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
}

/// 添加加油记录
struct AddFuelSheet: View {
    @ObservedObject var viewModel: FuelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litersText = ""
    @State private var priceText = ""
    @State private var isFull = true
    @State private var note = ""

    var body: some View {
        NavigationStack {
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
            .navigationTitle("记一笔油耗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .bold()
                }
            }
        }
    }

    private var canSave: Bool {
        Double(odometerText) != nil && Double(litersText) != nil
    }

    private func save() {
        guard let odometer = Double(odometerText), let liters = Double(litersText) else { return }
        let price = Double(priceText)
        let record = FuelRecord(
            date: date,
            odometerKm: odometer,
            liters: liters,
            pricePerLiter: price,
            totalCost: price.map { $0 * liters },
            isFull: isFull,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        viewModel.add(record)
        dismiss()
    }
}
