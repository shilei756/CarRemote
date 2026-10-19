import SwiftUI

// MARK: - iOS 15 兼容层
// 主 App / CarCore 部署目标为 iOS 15.0，而代码大量使用 iOS 16/17 才有的
// SwiftUI API。这里用一层薄垫片统一收口：16/17+ 走原生 API，iOS 15 走
// 可用的旧 API（ NavigationView / navigationBarTitle / navigationBarTrailing ），
// 行为保持一致，只有极少数视觉细节随系统版本略有差异。
// 小组件（CarWidget）因使用 AppIntents 与 containerBackground，最低 iOS 17，
// 不经过本文件。

// MARK: 导航容器

/// iOS 15 兼容导航容器：iOS 16+ 用 NavigationStack，iOS 15 用 NavigationView(.stack)
struct NavStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

// MARK: 标题

extension View {
    /// 行内导航标题：16+ 用 navigationBarTitleDisplayMode，iOS 15 用
    /// 已废弃但仍可用的 navigationBarTitle(_:displayMode:)（仅警告，无副作用）
    func inlineTitle(_ title: String) -> some View {
        if #available(iOS 16.0, *) {
            return navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            return navigationBarTitle(title, displayMode: .inline)
        }
    }
}

// MARK: 滚动背景（Form 透明底）

extension View {
    /// 隐藏 Form 滚动背景：iOS 16+ 用 scrollContentBackground，iOS 15 保持默认（表单灰底）
    func hideScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            return scrollContentBackground(.hidden)
        } else {
            return self
        }
    }
}

// MARK:  Sheet 形态

extension View {
    /// 半高 sheet（medium）：iOS 16+ 生效，iOS 15 回退为全屏 sheet
    func compatMediumDetent() -> some View {
        if #available(iOS 16.0, *) {
            return presentationDetents([.medium])
        } else {
            return self
        }
    }

    /// medium + large 两档 sheet：iOS 16+ 生效，iOS 15 回退为全屏 sheet
    func compatMediumLargeDetents() -> some View {
        if #available(iOS 16.0, *) {
            return presentationDetents([.medium, .large])
        } else {
            return self
        }
    }

    /// 固定 260pt 高 sheet：iOS 16+ 生效，iOS 15 回退为全屏 sheet
    func compatHeight260Detent() -> some View {
        if #available(iOS 16.0, *) {
            return presentationDetents([.height(260)])
        } else {
            return self
        }
    }

    /// 显示 sheet 顶部拖拽指示条：iOS 16+ 生效
    func compatDragIndicator() -> some View {
        if #available(iOS 16.0, *) {
            return presentationDragIndicator(.visible)
        } else {
            return self
        }
    }
}

// MARK: 值变化回调

extension View {
    /// 兼容各系统的 onChange：
    /// iOS 17+ 用双参数版本（旧版已废弃），iOS 15/16 用单参数版本
    func compatOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            return onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            return onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}

// MARK: 工具栏位置

/// iOS 15 兼容的工具栏位置：iOS 17+ 用 topBar*，iOS 15/16 用
/// navigationBar*（同为 iOS 15 起可用，只是 17+ 已废弃）
enum CompatToolbarPlacement {
    static var topTrailing: ToolbarItemPlacement {
        if #available(iOS 17.0, *) { return .topBarTrailing }
        return .navigationBarTrailing
    }

    static var topLeading: ToolbarItemPlacement {
        if #available(iOS 17.0, *) { return .topBarLeading }
        return .navigationBarLeading
    }
}

// MARK: 字体

extension Font {
    /// 网页版 .num 数字字体：等宽数字 + 圆体加粗。
    /// `system(_:design:weight:)` 组合是 iOS 16+，iOS 15 用 `Font.bold()` 补粗（iOS 13+）
    static var webNumFont: Font {
        if #available(iOS 16.0, *) {
            return .system(.body, design: .rounded, weight: .bold)
        } else {
            return .system(.body, design: .rounded).bold()
        }
    }
}
