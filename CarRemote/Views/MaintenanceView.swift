import SwiftUI
import CarCore

/// 维保记录与提醒（本地记录）
struct MaintenanceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: MaintenanceViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: MaintenanceViewModel(appState: appState))
    }

    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !viewModel.upcoming.isEmpty {
                        upcomingCard
                    }
                    if viewModel.records.isEmpty {
                        EmptyStateView(
                            systemImage: "wrench.and.screwdriver",
                            title: "还没有维保记录",
                            message: "记录每次保养，到期自动提醒"
                        )
                    } else {
                        recordsList
                    }
                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(WebConsoleBackground())
            .navigationTitle("维保提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加维保记录")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddMaintenanceSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - 临近提醒

    private var upcomingCard: some View {
        SectionCard(title: "保养提醒") {
            VStack(spacing: 10) {
                // 注意：这里必须用 enumerated() 双参数闭包的写法。
                // 直接用 ForEach(viewModel.upcoming, id: \.id) { record in }
                // 会让 Swift 的类型检查器错选 Binding 重载
                // （报 cannot convert [MaintenanceRecord] to Binding<C>），
                // 与下方 recordsList 中的写法保持一致。
                ForEach(Array(viewModel.upcoming.enumerated()), id: \.element.id) { _, record in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.item)
                                .font(.subheadline.bold())
                            Text(reminderText(record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func reminderText(_ record: MaintenanceRecord) -> String {
        var parts: [String] = []
        if let remaining = record.remainingKm(currentOdometerKm: viewModel.currentOdometerKm ?? 0) {
            if remaining < 0 {
                parts.append("已超期 \(CarStatus.format(abs(remaining))) km")
            } else {
                parts.append("还剩 \(CarStatus.format(remaining)) km")
            }
        }
        if let nextDate = record.nextDate {
            let days = Int(nextDate.timeIntervalSinceNow / 86400)
            if days < 0 {
                parts.append("已超期 \(abs(days)) 天")
            } else {
                parts.append("还剩 \(days) 天")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 记录列表

    private var recordsList: some View {
        SectionCard(title: "维保记录") {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider().padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.item)
                                .font(.subheadline.bold())
                            Text("\(dateText(record.date)) · \(CarStatus.format(record.odometerKm)) km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let next = record.nextOdometerKm, next > 0 {
                                Text("下次提醒：\(CarStatus.format(next)) km")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if let nextDate = record.nextDate {
                                Text("下次提醒：\(dateText(nextDate))")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let cost = record.cost {
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

/// 添加维保记录
struct AddMaintenanceSheet: View {
    @ObservedObject var viewModel: MaintenanceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var odometerText = ""
    @State private var item = ""
    @State private var costText = ""
    @State private var note = ""
    @State private var nextOdometerText = ""
    @State private var hasNextDate = false
    @State private var nextDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("保养信息") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("项目")
                        Spacer()
                        TextField("如：更换机油机滤", text: $item)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("里程表")
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
                Section("下次提醒（可选）") {
                    HStack {
                        Text("里程")
                        Spacer()
                        TextField("km", text: $nextOdometerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("按日期提醒", isOn: $hasNextDate)
                    if hasNextDate {
                        DatePicker("提醒日期", selection: $nextDate, displayedComponents: .date)
                    }
                }
                Section("备注（可选）") {
                    TextField("备注", text: $note)
                }
            }
            .navigationTitle("记一笔维保")
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
        !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Double(odometerText) != nil
    }

    private func save() {
        guard let odometer = Double(odometerText) else { return }
        let record = MaintenanceRecord(
            date: date,
            odometerKm: odometer,
            item: item.trimmingCharacters(in: .whitespacesAndNewlines),
            cost: Double(costText),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            nextOdometerKm: Double(nextOdometerText),
            nextDate: hasNextDate ? nextDate : nil
        )
        viewModel.add(record)
        dismiss()
    }
}
