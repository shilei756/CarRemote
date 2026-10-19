import SwiftUI
import CarCore

/// 自定义布局（对齐网页版排序编辑）：
/// - 快捷控车：4 个大按钮的顺序
/// - 更多控车：指令网格顺序
/// - 更多功能：磁贴顺序
/// 全部支持拖动排序，右上角保存 / 左上角恢复默认。
struct LayoutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DashboardViewModel

    @State private var quick: [CarCommand] = []
    @State private var more: [CarCommand] = []
    @State private var tools: [MoreTool] = []

    var body: some View {
        NavStack {
            Form {
                Section {
                    ForEach(quick, id: \.self) { command in
                        commandRow(command)
                    }
                    .onMove { from, to in
                        quick.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("快捷控车按钮（4 个）")
                } footer: {
                    Text("首页最上面一排的大按钮顺序")
                }

                Section {
                    ForEach(more, id: \.self) { command in
                        commandRow(command)
                    }
                    .onMove { from, to in
                        more.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("更多控车指令")
                } footer: {
                    Text("「更多控车」网格里的指令顺序")
                }

                Section {
                    ForEach(tools, id: \.self) { tool in
                        HStack(spacing: 12) {
                            Image(systemName: tool.sfSymbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: UInt(tool.colorHex)))
                                .frame(width: 26)
                            Text(tool.displayName)
                                .font(.system(size: 14))
                            Spacer()
                        }
                    }
                    .onMove { from, to in
                        tools.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("更多功能磁贴")
                } footer: {
                    Text("拖动右侧「≡」调整顺序，卡片会按此顺序排列")
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
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("保存") {
                        viewModel.saveLayout(quick: quick, more: more, tools: tools)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14))
                }
            }
        }
        .onAppear { reload() }
    }

    private func commandRow(_ command: CarCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.sfSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: command == .unlockDoor || command == .lockDoor ? 0x2f7bff : 0x8b5cf6))
                .frame(width: 26)
            Text(command.displayName)
                .font(.system(size: 14))
            Spacer()
        }
    }

    private func reload() {
        let settings = SharedStore.loadSettings()
        quick = settings.orderedQuickCommands
        more = settings.orderedMoreCommands
        tools = settings.orderedMoreTools
    }
}
