import SwiftUI
import UIKit
import WidgetKit
import CarCore

/// 我的页（1.2.0）：车模折叠选择、小组件 5 按钮自定义、网站授权信息、
/// 车辆位置、退出登录。全界面中文点阵化。
struct CakocheSettingsPage: View {
    @ObservedObject var control: CakocheControl
    @Binding var selectedID: String
    @EnvironmentObject private var appState: AppState

    @State private var modelsExpanded = false
    @State private var editingSlot: Int?
    @State private var widgetCommands: [String] = SharedStore.loadSettings().widgetCommands

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    DotCnText(text: "我 的", size: 16, color: Mono.paperInk)
                    DotCnText(text: "车辆 · 车型 · 小组件 · 授权", size: 8, color: Mono.paperDim)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 10)

                // MARK: 3D 车模（默认折叠）
                Button { withAnimation(.easeInOut(duration: 0.22)) { modelsExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        DotCnText(text: "3D 车模", size: 10, color: Mono.paperInk)
                        DotCnText(text: "全系 12 款", size: 8, color: Mono.paperDim)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(modelsExpanded ? 180 : 0))
                            .foregroundStyle(Mono.paperDim)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("车模选择，已\(modelsExpanded ? "展开" : "折叠")")
                if modelsExpanded {
                    ForEach(CakocheModels.all) { model in
                        Button {
                            selectedID = model.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    DotCnText(text: model.name, size: 10, color: Mono.paperInk)
                                    DotCnText(text: model.group + " · " + model.id.uppercased(),
                                              size: 7, color: Mono.paperDim)
                                }
                                Spacer()
                                if selectedID == model.id {
                                    Circle().fill(Mono.red).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(selectedID == model.id
                                        ? Mono.paperHair.opacity(0.35) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.name)
                        .accessibilityAddTraits(selectedID == model.id ? [.isSelected] : [])
                        Hairline(color: Mono.paperHair).padding(.leading, 22)
                    }
                }
                Hairline(color: Mono.paperHair)

                // MARK: 小组件按钮（1.2.0 新增：5 个槽位自定义）
                section("小组件按钮", "桌面小组件的 5 个控车按钮，点按更换指令")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<5, id: \.self) { slot in
                        Button { editingSlot = slot } label: {
                            HStack(spacing: 10) {
                                DotCnText(text: "按钮 \(slot + 1)", size: 8, color: Mono.paperDim)
                                    .frame(width: 70, alignment: .leading)
                                DotCnText(text: commandName(widgetCommands.indices.contains(slot)
                                                             ? widgetCommands[slot] : nil),
                                          size: 10, color: Mono.paperInk)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Mono.paperHair)
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("小组件按钮 \(slot + 1)，当前 \(commandName(widgetCommands.indices.contains(slot) ? widgetCommands[slot] : nil))")
                        Hairline(color: Mono.paperHair).padding(.leading, 22)
                    }
                }
                .padding(.top, 4)

                // MARK: 账号授权
                section("账号授权", "手机号与控车码由站主网站校验")
                VStack(alignment: .leading, spacing: 11) {
                    keyRow("手机号", maskedPhone)
                    keyRow("授权状态", "已授权 · 白名单")
                    keyRow("授权站点", hostText)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                // MARK: 车辆
                section("车辆", "位置与退出")
                Button { openMap() } label: {
                    HStack {
                        DotCnText(text: "在地图中查看车辆位置", size: 10, color: Mono.paperInk)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Mono.paperDim)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在地图中查看车辆位置")
                Hairline(color: Mono.paperHair).padding(.leading, 22)

                Button { appState.logout() } label: {
                    HStack {
                        DotCnText(text: "退 出 登 录", size: 10, color: Mono.red)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("退出登录")

                DotCnText(text: "CAKOCHE 1.2.1 · 与网站同一套白名单授权体系",
                          size: 8, color: Mono.paperDim)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: Binding(
            get: { editingSlot.map { SlotRef(index: $0) } },
            set: { editingSlot = $0?.index }
        )) { ref in
            CommandPicker(current: slotCommand(ref.index)) { picked in
                saveSlot(ref.index, picked)
            }
        }
    }

    struct SlotRef: Identifiable { let index: Int; var id: Int { index } }

    private func slotCommand(_ slot: Int) -> CarCommand? {
        widgetCommands.indices.contains(slot) ? CarCommand(rawValue: widgetCommands[slot]) : nil
    }

    private func commandName(_ raw: String?) -> String {
        raw.flatMap(CarCommand.init)?.displayName ?? "未设置"
    }

    private func saveSlot(_ slot: Int, _ command: CarCommand) {
        var commands = widgetCommands
        while commands.count < 5 { commands.append(CarModelStyle.defaultWidgetCommands[0]) }
        commands[slot] = command.rawValue
        widgetCommands = commands
        var settings = SharedStore.loadSettings()
        settings.widgetCommands = commands
        SharedStore.saveSettings(settings)
        // 小组件立即按新配置重绘
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func section(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DotCnText(text: title, size: 10, color: Mono.paperInk)
            DotCnText(text: subtitle, size: 8, color: Mono.paperDim)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private func keyRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            DotCnText(text: key, size: 8, color: Mono.paperDim)
                .frame(width: 78, alignment: .leading)
            DotCnText(text: value, size: 9, color: Mono.paperInk)
            Spacer()
        }
    }

    private var maskedPhone: String {
        guard let phone = appState.credentials?.phone, phone.count == 11 else { return "--" }
        return String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }

    private var hostText: String {
        URL(string: APIConfig.siteBaseURL)?.host ?? APIConfig.siteBaseURL
    }

    private func openMap() {
        guard let location = appState.status?.location else { return }
        let lat = location.latitude
        let lon = location.longitude
        let scheme = "iosamap://viewMap?sourceApplication=CAKOCHE&lat=\(lat)&lon=\(lon)&dev=0"
        if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: "https://uri.amap.com/marker?position=\(lon),\(lat)") {
            UIApplication.shared.open(web)
        }
    }
}

// MARK: - 指令选择弹层

/// 点按槽位后弹出：列出全部控车指令，点选即更新小组件按钮
struct CommandPicker: View {
    let current: CarCommand?
    let onPick: (CarCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    private let candidates: [CarCommand] = CarCommand.allCases

    var body: some View {
        // iOS 15 兼容：NavigationStack 需 iOS 16，这里用 NavigationView
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates, id: \.self) { command in
                        Button {
                            onPick(command)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.sfSymbol)
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(Mono.paperInk)
                                    .frame(width: 26)
                                DotCnText(text: command.displayName, size: 10, color: Mono.paperInk)
                                Spacer()
                                if current == command {
                                    Circle().fill(Mono.red).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 13)
                            .background(current == command
                                        ? Mono.paperHair.opacity(0.35) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        Hairline(color: Mono.paperHair).padding(.leading, 22)
                    }
                }
            }
            .background(Mono.paper)
            .navigationTitle("选择指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
