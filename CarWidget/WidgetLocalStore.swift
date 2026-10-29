import Foundation
import CarCore

/// 小组件本地存储（免签/巨魔等无 App Group 环境的兜底数据通道）。
///
/// 背景：部分安装方式（巨魔商店、部分免签工具）不给 App 注入描述文件，
/// App Group / 钥匙串共享组在系统层面不存在，小组件进程读不到主 App
/// 共享出来的任何数据（诊断表现为三通道全 ✗，而 App 自身一切正常）。
///
/// 解法：登录走站主自有后端（手机号 + 控车码），小组件可以**自己登录**，
/// 凭据与车况快照直接存小组件进程自己的沙盒（UserDefaults.standard），
/// 完全不依赖任何共享权限。主屏与锁屏小组件同属一个扩展进程，
/// 共享同一份 UserDefaults.standard —— 绑定一次，全部小组件生效。
enum WidgetLocalStore {

    private static let credentialsKey = "widget.local.credentials"
    private static let snapshotKey = "widget.local.snapshot"
    private static let defaults = UserDefaults.standard

    // MARK: 凭据

    static func loadCredentials() -> Credentials? {
        guard let data = defaults.data(forKey: credentialsKey) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func saveCredentials(_ credentials: Credentials?) {
        if let credentials, let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: credentialsKey)
        } else {
            defaults.removeObject(forKey: credentialsKey)
        }
    }

    // MARK: 车况快照

    static func loadSnapshot() -> StatusSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(StatusSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: StatusSnapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeItem(forKey: snapshotKey)
        }
    }
}
