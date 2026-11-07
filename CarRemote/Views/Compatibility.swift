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

// MARK: 安全区辅助

/// 当前状态栏高度（全屏页面手动避让用，避免壁纸铺满时顶栏被状态栏遮挡）
func currentStatusBarHeight() -> CGFloat {
    if #available(iOS 13.0, *) {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .statusBarManager?
            .statusBarFrame.height ?? 0
    } else {
        return UIApplication.shared.statusBarFrame.height
    }
}

// MARK: 界面整体缩放（#7 界面大小）

/// 通过窗口 transform 整体等比缩放 App：scale < 1 时一页可显示更多内容。
/// scale = 1.0 为原始大小。取值夹在 0.5~1.5，默认由 AppSettings.uiScale 提供。
///
/// 关键修正：**不能同时设置 `window.frame` 与 `window.transform`**。
/// 当 transform 非 identity 时，frame 表示「变换后的包围盒」，把 frame 设成
/// screen/scale 会让 UIKit 反算出 bounds = screen/scale² —— 界面反而被放大并
/// 向右下溢出，右侧内容被裁、底部 TabBar 直接跑到屏幕外，用户再也无法切回
/// 设置页把大小改回来。
///
/// 正确做法：把 bounds 放大到 screen/scale（布局按更大的逻辑尺寸排布，所以一页
/// 能显示更多内容），再用 transform 缩回，并把 center 固定在屏幕中心，使缩放后
/// 的视觉包围盒恰好等于屏幕 —— 不偏移、不裁切、底部标签栏始终可见可点。
func applyUIScale(_ scale: CGFloat) {
    let clamped = min(max(scale, 0.5), 1.5)
    guard let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }) else { return }
    let screen = window.screen.bounds
    if abs(clamped - 1.0) < 0.001 {
        window.transform = .identity
        window.bounds = screen
    } else {
        window.bounds = CGRect(origin: .zero,
                               size: CGSize(width: screen.width / clamped,
                                            height: screen.height / clamped))
        window.transform = CGAffineTransform(scaleX: clamped, y: clamped)
    }
    // transform 以 center 为锚点，固定到屏幕中心才能避免整体右下偏移
    window.center = CGPoint(x: screen.midX, y: screen.midY)
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

// MARK: 车模舞台 ↔ 座舱视角 联动

/// 首页把 3D 车模舞台交给「座舱转场」托管时，用环境值下发当前是否车内视角。
/// - `.standalone`：车库页等独立使用，保留舞台自带全部控件与「外/内」滑块。
/// - `.managed(interior:)`：首页托管，「外/内」滑块交给座舱胶囊统一控制，
///   车模相机据 interior 在「车外展示 / 车内座舱」之间切换（复用 GLB 自带内饰几何）。
enum CarCockpitStageConfig: Equatable {
    case standalone
    case managed(interior: Bool)
}

private struct CarCockpitStageKey: EnvironmentKey {
    static let defaultValue: CarCockpitStageConfig = .standalone
}

extension EnvironmentValues {
    var carCockpitStage: CarCockpitStageConfig {
        get { self[CarCockpitStageKey.self] }
        set { self[CarCockpitStageKey.self] = newValue }
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
