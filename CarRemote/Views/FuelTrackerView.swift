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

    // MARK: - 汇总

    private var summaryCard: some View {
        SectionCard(title: "油耗概览") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                StatusTile(
                    title: "平均油耗",
                    value: viewModel.averageConsumption.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "L/100km",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .green
                )
                StatusTile(
                    title: "最近油耗",
                    value: viewModel.lastConsumption.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "L/100km",
                    systemImage: "clock.arrow.circlepath"
                )
                StatusTile(
                    title: "累计油费",
                    value: String(format: "%.0f", viewModel.totalSpend),
                    unit: "元",
                    systemImage: "yensign.circle"
                )
                StatusTile(
                    title: "累计加油",
                    value: String(format: "%.1f", viewModel.totalLiters),
                    unit: "L",
                    systemImage: "fuelpump.fill"
                )
            }
            if let odo = viewModel.currentOdometerKm {
                Text("当前里程：\(CarStatus.format(odo)) km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 记录列表

    private var recordsList: some View {
        SectionCard(title: "加油记录（按里程排序）") {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider().padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateText(record.date))
                                .font(.subheadline.bold())
                            Text("\(CarStatus.format(record.odometerKm)) km · \(CarStatus.format(record.liters)) L\(record.isFull ? " · 加满" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let consumption = record.consumption(since: index > 0 ? viewModel.records[index - 1] : nil) {
                                Text("本段油耗 \(String(format: "%.1f", consumption)) L/100km")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let price = record.pricePerLiter {
                            Text("\(String(format: "%.2f", price)) 元/L")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let cost = record.totalCost {
                            Text("\(String(format: "%.0f", cost)) 元")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
