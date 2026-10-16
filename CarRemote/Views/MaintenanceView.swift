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
                VStack(spacing: 12) {
                    overviewCard
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
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(WebConsoleBackground())
            .navigationTitle("智能维保")
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

    // MARK: - 概览卡（照搬网页版 mtOverview：总里程大数字 + 上次保养 + 下次徽章）

    private var overviewCard: some View {
        SectionCard(sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                // 总里程 + 上次保养（网页版 flex items-end gap-4）
                HStack(alignment: .bottom, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前总里程")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CarStatus.format(viewModel.currentOdometerKm))
                                .font(.system(size: 26, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Text("km")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                    Spacer()
                    if let last = viewModel.records.first {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("上次保养")
                                .font(.system(size: 10))
                                .foregroundStyle(WebTheme.muted)
                            Text("\(CarStatus.format(last.odometerKm)) km")
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Text(dateText(last.date))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                }

                // 下次提醒徽章（网页版 mtNextBadges）
                if !viewModel.upcoming.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(viewModel.upcoming.prefix(3).enumerated()), id: \.element.id) { _, record in
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.system(size: 9))
                                Text("\(record.item)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                Text(reminderShortText(record))
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(WebTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(WebTheme.amber.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func reminderShortText(_ record: MaintenanceRecord) -> String {
        if let remaining = record.remainingKm(currentOdometerKm: viewModel.currentOdometerKm ?? 0) {
            return remaining < 0 ? "超 \(CarStatus.format(abs(remaining)))km" : "剩 \(CarStatus.format(remaining))km"
        }
        if let nextDate = record.nextDate {
            let days = Int(nextDate.timeIntervalSinceNow / 86400)
            return days < 0 ? "超 \(abs(days))天" : "剩 \(days)天"
        }
        return ""
    }

    // MARK: - 临近提醒（网页版 amber 徽章行）

    private var upcomingCard: some View {
        SectionCard(title: "保养提醒", sakura: false) {
            VStack(spacing: 8) {
                // 注意：这里必须用 enumerated() 双参数闭包的写法。
                // 直接用 ForEach(viewModel.upcoming, id: \.id) { record in }
                // 会让 Swift 的类型检查器错选 Binding 重载
                // （报 cannot convert [MaintenanceRecord] to Binding<C>），
                // 与下方 recordsList 中的写法保持一致。
                ForEach(Array(viewModel.upcoming.enumerated()), id: \.element.id) { _, record in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.item)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WebTheme.txt)
                            Text(reminderText(record))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.muted)
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
                        Divider()
                            .overlay(WebTheme.border)
                            .padding(.vertical, 10)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.item)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(WebTheme.txt)
                            Text("\(dateText(record.date)) · \(CarStatus.format(record.odometerKm)) km")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.muted)
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(WebTheme.faint)
                            }
                            if let next = record.nextOdometerKm, next > 0 {
                                Text("下次提醒：\(CarStatus.format(next)) km")
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(WebTheme.amber)
                            }
                            if let nextDate = record.nextDate {
                                Text("下次提醒：\(dateText(nextDate))")
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(WebTheme.amber)
                            }
                        }
                        Spacer()
                        if let cost = record.cost {
                            Text("¥\(String(format: "%.0f", cost))")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                        }
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
            .scrollContentBackground(.hidden)
            .background(WebConsoleBackground())
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
