import Foundation
import SwiftUI

/// 「更多功能」区域的磁贴项：支持自定义排序（与网页版一致）。
/// 白名单管理仍由管理员权限单独控制显示。
public enum MoreTool: String, Codable, CaseIterable, Sendable {
    case refreshStatus      // 查询车况
    case history            // 操作历史
    case messages           // 消息记录
    case trips              // 我的行程
    case acActivate         // 空调开通
    case vehicleStatus      // 车辆状态
    case panorama           // 360 全景
    case maintenance        // 智能维保
    case wallpaper          // 背景壁纸
    case customize          // 自定义布局（入口，排在最后）
    case whitelist          // 白名单管理（仅管理员）

    public var displayName: String {
        switch self {
        case .refreshStatus: return "查询车况"
        case .history: return "操作历史"
        case .messages: return "消息记录"
        case .trips: return "我的行程"
        case .acActivate: return "空调开通"
        case .vehicleStatus: return "车辆状态"
        case .panorama: return "360全景"
        case .maintenance: return "智能维保"
        case .wallpaper: return "背景壁纸"
        case .customize: return "自定义"
        case .whitelist: return "白名单管理"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .refreshStatus: return "arrow.triangle.2.circlepath"
        case .history: return "clock.arrow.circlepath"
        case .messages: return "bubble.left.and.text.bubble.right"
        case .trips: return "road.lanes"
        case .acActivate: return "qrcode"
        case .vehicleStatus: return "gauge.with.dots.needle.33percent"
        case .panorama: return "camera.rotate"
        case .maintenance: return "wrench.and.screwdriver"
        case .wallpaper: return "photo.on.rectangle.angled"
        case .customize: return "slider.horizontal.3"
        case .whitelist: return "person.2.shield"
        }
    }

    /// 磁贴主色（十六进制，避免 CarCore 依赖 UI 主题）
    public var colorHex: UInt32 {
        switch self {
        case .refreshStatus: return 0x2f7bff
        case .history: return 0xf59e0b
        case .messages: return 0x06b6d4
        case .trips: return 0x8b5cf6
        case .acActivate: return 0x22c55e
        case .vehicleStatus: return 0x2f7bff
        case .panorama: return 0x22c55e
        case .maintenance: return 0xea580c
        case .wallpaper: return 0xdb2777
        case .customize: return 0x64748b
        case .whitelist: return 0xef4444
        }
    }

    /// 默认顺序（白名单管理不参与排序，按权限插入）
    public static let defaultOrder: [MoreTool] = [
        .refreshStatus, .history, .messages, .trips,
        .acActivate, .vehicleStatus, .panorama, .maintenance,
        .wallpaper, .customize
    ]

    /// 可参与自定义排序的项
    public static var customizable: [MoreTool] { defaultOrder }
}
