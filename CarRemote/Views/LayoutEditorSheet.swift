import SwiftUI
import CarCore

/// 自定义布局（对齐网页版排序编辑）：
/// - 快捷控车：4 个大按钮的顺序
/// - 更多控车：指令网格顺序
/// - 更多功能：磁贴顺序
/// 全部支持拖动排序，右上角保存 / 左上角恢复默认。
struct LayoutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// true = 由「我的」页 NavigationLink 推入（不自带 NavStack、不显示「完成」）
    var isPushed = false
    @ObservedObject var viewModel: DashboardViewModel

    @State private var quick: [CarCommand] = []
    @State private var more: [CarCommand] = []
    @State private var tools: [MoreTool] = []
    /// 被隐藏（屏蔽）项：不在主界面显示
    @State private var hiddenQuick: Set<String> = []
    @State private var hiddenMore: Set<String> = []
    @State private var hiddenTools: Set<String> = []

    var body: some View {
        Group {
            if isPushed {
                editor
            } else {
                NavStack { editor }
            }
        }
        .onAppear { reload() }
    }

    private var editor: some View {
        Form {
                Section {
                    ForEach(quick, id: \.self) { command in
                        commandRow(command, hidden: $hiddenQuick)
                    }
                    .onMove { from, to in
                        quick.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("快捷控车按钮（4 个）")
                } footer: {
                    Text("首页最上面一排的大按钮顺序；点「隐藏」可让它不在主界面出现。")
                }

                Section {
                    ForEach(more, id: \.self) { command in
                        commandRow(command, hidden: $hiddenMore)
                    }
                    .onMove { from, to in
                        more.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("更多控车指令")
                } footer: {
                    Text("「更多控车」网格里的指令顺序；不常用的可点「隐藏」。")
                }

                Section {
                    ForEach(tools, id: \.self) { tool in
                        toolRow(tool)
                    }
                    .onMove { from, to in
                        tools.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("更多功能磁贴")
                } footer: {
                    Text("拖动右侧「≡」调整顺序；不想用的磁贴点「隐藏」即可从主界面移除。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .inlineTitle("自定义布局")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topLeading) {
                    Button("恢复默认") {
                        viewModel.resetLayout()
                        reload()
                    }
                    .font(.system(size: 14))
                }
                ToolbarItem(placement: CompatToolbarPlacement.topLeading) {
                    Button("全部显示") {
                        hiddenQuick.removeAll()
                        hiddenMore.removeAll()
                        hiddenTools.removeAll()
                    }
                    .font(.system(size: 14))
                }
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("保存") {
                        viewModel.saveLayout(
                            quick: quick, more: more, tools: tools,
                            hiddenQuick: hiddenQuick, hiddenMore: hiddenMore, hiddenTools: hiddenTools
                        )
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                // 说明：ToolbarContentBuilder 在 iOS 15 不支持条件语句（buildIf 仅 iOS 16+），
                // 故「完成」按钮始终显示；推入模式下点「完成」等同关闭子页（pop），行为一致。
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14))
                }
            }
    }

    /// 控车指令行：图标 + 名称 + 右侧「显示/隐藏」开关（编辑模式下点按切换，不触发拖拽）
    private func commandRow(_ command: CarCommand, hidden: Binding<Set<String>>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.sfSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: command == .unlockDoor || command == .lockDoor ? 0x2f7bff : 0x8b5cf6))
                .frame(width: 26)
            Text(command.displayName)
                .font(.system(size: 14))
            Spacer()
            hideToggle(isHidden: hidden.wrappedValue.contains(command.rawValue)) {
                if hidden.wrappedValue.contains(command.rawValue) {
                    hidden.wrappedValue.remove(command.rawValue)
                } else {
                    hidden.wrappedValue.insert(command.rawValue)
                }
            }
        }
    }

    /// 更多功能磁贴行
    private func toolRow(_ tool: MoreTool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.sfSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(tool.colorHex)))
                .frame(width: 26)
            Text(tool.displayName)
                .font(.system(size: 14))
            Spacer()
            hideToggle(isHidden: hiddenTools.contains(tool.rawValue)) {
                if hiddenTools.contains(tool.rawValue) {
                    hiddenTools.remove(tool.rawValue)
                } else {
                    hiddenTools.insert(tool.rawValue)
                }
            }
        }
    }

    /// 「显示 / 隐藏」胶囊按钮（眼睛图标 + 文字），无障碍标签齐全
    private func hideToggle(isHidden: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isHidden ? "已隐藏" : "显示")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHidden ? WebTheme.faint : WebTheme.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((isHidden ? WebTheme.faint : WebTheme.green).opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHidden ? "已隐藏，点按恢复显示" : "当前显示，点按隐藏")
    }

    private func reload() {
        let settings = SharedStore.loadSettings()
        quick = settings.orderedQuickCommands
        more = settings.orderedMoreCommands
        tools = settings.orderedMoreTools
        hiddenQuick = settings.hiddenQuickCommands
        hiddenMore = settings.hiddenMoreCommands
        hiddenTools = settings.hiddenTools
    }
}
