import Foundation
import CoreBluetooth

// =============================================================
// 蓝牙车钥匙 — 可配置项持久化
// 所有协议参数（UUID、指令帧、RSSI 阈值、密码、绑定设备）均存 UserDefaults，
// 用户可在「蓝牙钥匙 → 设置」内改写。默认值来自逆向还原。
// =============================================================

struct CarKeyConfig: Codable, Equatable {
    // ---- 主 GATT 服务 ----
    var serviceUUID: String = "970fafad-f144-357f-7888-d5754aa78400"
    var writeUUID: String   = "970fafad-f144-357f-7888-d5754aa78401"
    var notifyUUID: String  = "970fafad-f144-357f-7888-d5754aa78401" // 同一特征写+通知

    // ---- HID / 串口服务（Nordic BLE-UART）----
    var hidServiceUUID: String = "0000fff0-0000-1000-8000-00805f9b34fb"
    var hidWriteUUID: String    = "0000fff1-0000-1000-8000-00805f9b34fb"
    var hidNotifyUUID: String   = "0000fff2-0000-1000-8000-00805f9b34fb"

    // ---- 指令帧（动作 rawValue -> hex）----
    var frames: [String: String]

    // ---- RSSI / 距离参数 ----
    var unlockRSSI: Int = -65   // 大于此值（更近）触发解锁
    var lockRSSI: Int   = -85   // 小于此值（更远）触发上锁
    var measurePower: Int = -59 // 1 米参考 RSSI（用于距离估算）
    var pathLoss: Double = 2.2  // 路径损耗指数
    var autoUnlock: Bool = false
    var autoLock: Bool = false

    // ---- 安全 ----
    var password: String = ""

    // ---- 绑定设备 ----
    var bondedUUID: String = ""  // peripheral.identifier.uuidString
    var bondedName: String = ""

    init() {
        var f: [String: String] = [:]
        for a in CarKeyAction.allCases { f[a.rawValue] = a.defaultFrame }
        frames = f
    }

    var frameFor: (_ action: CarKeyAction) -> String {
        { action in frames[action.rawValue] ?? action.defaultFrame }
    }
}

final class CarKeyStore: ObservableObject {
    static let shared = CarKeyStore()

    @Published var config: CarKeyConfig {
        didSet { save() }
    }

    private let key = "carkey.config.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(CarKeyConfig.self, from: data) {
            config = c
        } else {
            config = CarKeyConfig()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func resetToDefaults() {
        config = CarKeyConfig()
    }

    // MARK: - 便捷访问

    func cbuuid(_ s: String) -> CBUUID? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, UUID(uuidString: t) != nil || t.count >= 4 else { return nil }
        return CBUUID(string: t)
    }

    /// 估算距离（米）：d = 10^((measurePower - rssi) / (10 * pathLoss))
    func distanceMeters(rssi: Int) -> Double {
        let ratio = Double(config.measurePower - rssi) / (10.0 * config.pathLoss)
        return pow(10.0, ratio)
    }
}
