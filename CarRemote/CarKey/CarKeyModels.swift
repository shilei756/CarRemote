import Foundation

// =============================================================
// 蓝牙车钥匙 — 数据模型
// 协议逆向自「蓝牙车钥匙_1.0.apk」(com.jance.mainhidbluetooth)：
//   · 双 GATT 服务：主服务 970fafad-…-78400 / 特征值 970fafad-…-78401（写+通知）
//                      HID/串口服务 0000fff0 / 特征 fff1(写) fff2(通知)
//   · 指令为 hex 帧，经 hexString→字节后写入特征值
//   · RSSI 距离判定实现无钥匙进入（靠近解锁 / 远离上锁）
// 说明：每个动作的「默认指令帧」是逆向出的 7X 序列样式，已在 App「蓝牙钥匙-设置」
//       内逐条可改；拿到实车验证后微调即可（沙箱无硬件无法端到端实测）。
// =============================================================

/// 车钥匙动作
public enum CarKeyAction: String, CaseIterable, Identifiable {
    case unlock       // 解锁
    case lock         // 上锁
    case start        // 启动 / 点火
    case trunk        // 后备箱
    case windowsUp    // 关窗
    case windowsDown  // 开窗
    case horn         // 鸣笛
    case find         // 寻车

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlock:       return "解锁"
        case .lock:         return "上锁"
        case .start:        return "启动"
        case .trunk:        return "后备箱"
        case .windowsUp:    return "关窗"
        case .windowsDown:  return "开窗"
        case .horn:         return "鸣笛"
        case .find:         return "寻车"
        }
    }

    var symbol: String {
        switch self {
        case .unlock:       return "lock.open.fill"
        case .lock:         return "lock.fill"
        case .start:        return "power.fill"
        case .trunk:        return "car.fill"
        case .windowsUp:    return "arrow.up.square.fill"
        case .windowsDown:  return "arrow.down.square.fill"
        case .horn:         return "speaker.wave.2.fill"
        case .find:         return "location.fill"
        }
    }

    /// 逆向出的默认指令帧（hex，偶数位）。仅作初值，设置内可覆盖。
    var defaultFrame: String {
        switch self {
        case .unlock:       return "7a67"
        case .lock:         return "7c67"
        case .start:        return "7f67"
        case .trunk:        return "71b7"
        case .windowsUp:    return "79b7"
        case .windowsDown:  return "74b7"
        case .horn:         return "78b7"
        case .find:         return "70c7"
        }
    }

    /// 危险动作（执行前二次确认）
    var isDangerous: Bool {
        self == .start || self == .horn
    }
}

/// 扫描到的蓝牙设备
public struct CarKeyDevice: Identifiable, Equatable {
    public let id: UUID          // peripheral.identifier
    public let name: String
    public var rssi: Int
    public var isBonded: Bool

    public init(id: UUID, name: String, rssi: Int, isBonded: Bool = false) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isBonded = isBonded
    }
}

/// 连接状态
public enum CarKeyConnectionState: String {
    case disconnected = "未连接"
    case scanning = "扫描中"
    case connecting = "连接中"
    case connected = "已连接"
    case failed = "连接失败"
}

/// PKE（无钥匙进入）状态
public enum CarKeyPKEState: String {
    case unknown = "未知"
    case unlocked = "已解锁"
    case locked = "已上锁"
}
