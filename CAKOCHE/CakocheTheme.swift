import SwiftUI

/// CAKOCHE 视觉语言：低饱和黑白灰 + 唯一红色强调，极致留白，无卡片无边框。
/// 与正式版 WebTheme 完全隔离，不引用任何系统语义色，深浅由本文件单独定义。
enum Mono {
    /// 首页 / 空调页纸白底
    static let paper = Color(red: 0.957, green: 0.957, blue: 0.945)
    static let paperInk = Color(white: 0.07)
    static let paperDim = Color(white: 0.48)
    static let paperHair = Color(white: 0.84)

    /// 控车抽屉反相黑底
    static let night = Color(white: 0.045)
    static let nightInk = Color(white: 0.965)
    static let nightDim = Color(white: 0.42)
    static let nightHair = Color(white: 0.19)

    /// 唯一强调色
    static let red = Color(red: 0.88, green: 0.14, blue: 0.18)
    static let ok = Color(white: 0.28)

    /// 点阵数字字号档位
    static func unit(for size: CGFloat) -> CGFloat { max(2, size / 7) }
}

/// 极简细线分隔（1px 发丝线，替代卡片边框）
struct Hairline: View {
    var color: Color = Mono.paperHair
    var body: some View {
        Rectangle().fill(color).frame(height: 0.5)
    }
}
