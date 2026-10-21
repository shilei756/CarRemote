import Foundation
import CoreBluetooth
import Combine

// =============================================================
// 蓝牙车钥匙 — CoreBluetooth 管理器
// 复刻 APK 的 BLE 通信链路（com.jance.mainhidbluetooth.BleControl）：
//   扫描 → connectGatt → 发现双服务 → 开启两个通知通道
//   → write(hexString) 经 hex→字节后写入特征值 → 周期读 RSSI 做距离判定
// 经典蓝牙(SPP/HID profile)路径 iOS 不支持，未移植。
// =============================================================

final class BLECarKeyManager: NSObject, ObservableObject {
    static let shared = BLECarKeyManager()

    @Published var bluetoothState: CBManagerState = .unknown
    @Published var connectionState: CarKeyConnectionState = .disconnected
    @Published var discovered: [CarKeyDevice] = []
    @Published var connectedName: String = ""
    @Published var connectedUUID: String = ""
    @Published var rssi: Int = 0
    @Published var distance: Double = 0
    @Published var pkeState: CarKeyPKEState = .unknown
    @Published var lastResponse: String = ""
    @Published var logs: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var hidWriteChar: CBCharacteristic?
    private var hidNotifyChar: CBCharacteristic?
    private var rssiTimer: Timer?
    private var scanTimer: Timer?

    private var store: CarKeyStore { CarKeyStore.shared }
    private let logLimit = 200

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: "carkey.central.v1"
            ]
        )
    }

    // MARK: - 对内状态写入（统一走主线程）

    private func set(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
    }

    private func log(_ msg: String) {
        set {
            let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.append("[\(t)] \(msg)")
            if self.logs.count > self.logLimit { self.logs.removeFirst(self.logs.count - self.logLimit) }
        }
    }

    // MARK: - 扫描

    func startScan() {
        guard bluetoothState == .poweredOn else { log("蓝牙未开启"); return }
        guard peripheral == nil else { log("已连接设备，先断开再扫描"); return }
        set { self.discovered.removeAll() }
        set { self.connectionState = .scanning }
        log("开始扫描…")
        var services: [CBUUID]? = nil
        if let s = store.cbuuid(store.config.serviceUUID) { services = [s] }
        central.scanForPeripherals(withServices: services,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        // 扫描 20s 后自动停止（避免一直耗电）
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }

    func stopScan() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        scanTimer?.invalidate(); scanTimer = nil
        set { if self.connectionState == .scanning { self.connectionState = .disconnected } }
        log("停止扫描")
    }

    // MARK: - 连接

    func connect(_ device: CarKeyDevice) {
        guard bluetoothState == .poweredOn else { log("蓝牙未开启"); return }
        guard let p = central.retrievePeripherals(withIdentifiers: [device.id]).first else {
            log("找不到设备 \(device.name)，请重新扫描"); return
        }
        peripheral = p
        p.delegate = self
        set { self.connectionState = .connecting; self.connectedName = device.name }
        log("连接 \(device.name) …")
        central.connect(p, options: nil)
    }

    /// 连接已绑定的设备（启动/后台恢复时）
    func connectBonded() {
        let uuid = store.config.bondedUUID
        guard !uuid.isEmpty, let id = UUID(uuidString: uuid) else { return }
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        set { self.connectionState = .connecting; self.connectedName = self.store.config.bondedName }
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        teardown()
        log("已断开")
    }

    private func teardown() {
        rssiTimer?.invalidate(); rssiTimer = nil
        writeChar = nil; notifyChar = nil; hidWriteChar = nil; hidNotifyChar = nil
        peripheral?.delegate = nil; peripheral = nil
        set {
            self.connectionState = .disconnected
            self.rssi = 0; self.distance = 0
            self.pkeState = .unknown
            self.connectedUUID = ""
        }
    }

    func bondCurrent() {
        guard let p = peripheral else { log("未连接，无法绑定"); return }
        store.config.bondedUUID = p.identifier.uuidString
        store.config.bondedName = p.name ?? connectedName
        store.save()
        log("已绑定 \(store.config.bondedName)")
    }

    // MARK: - 发送指令

    /// 发送一个动作指令（默认帧可被设置覆盖）
    func send(_ action: CarKeyAction) {
        let frame = store.config.frames[action.rawValue] ?? action.defaultFrame
        sendRaw(frame, label: action.title)
    }

    /// 发送原始 hex 帧
    func sendRaw(_ hex: String, label: String = "指令") {
        guard let p = peripheral else { log("未连接，无法发送"); return }
        guard let data = BLECarKeyManager.hexToData(hex), !data.isEmpty else {
            log("\(label) 指令帧非法：\(hex)"); return
        }
        let target: CBCharacteristic? = writeChar ?? hidWriteChar
        guard let char = target else { log("特征值未就绪，请等待服务发现完成"); return }
        p.writeValue(data, for: char, type: .withResponse)
        log("→ \(label) [\(hex.uppercased())]")
    }

    // MARK: - hex 工具

    static func hexToData(_ hex: String) -> Data? {
        let s = hex.replacingOccurrences(of: " ", with: "")
        guard s.count % 2 == 0, !s.isEmpty else { return nil }
        var data = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            guard let v = UInt8(String(s[i..<j]), radix: 16) else { return nil }
            data.append(v); i = j
        }
        return data
    }

    static func dataToHex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECarKeyManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        set { self.bluetoothState = s }
        if s == .poweredOn {
            log("蓝牙已开启")
            connectBonded()
        } else {
            log("蓝牙状态：\(s.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "未知设备"
        let id = peripheral.identifier
        set {
            if let idx = self.discovered.firstIndex(where: { $0.id == id }) {
                self.discovered[idx].rssi = RSSI.intValue
            } else {
                let bonded = (self.store.config.bondedUUID == id.uuidString)
                self.discovered.append(CarKeyDevice(id: id, name: name, rssi: RSSI.intValue, isBonded: bonded))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        set {
            self.connectionState = .connected
            self.connectedName = peripheral.name ?? self.connectedName
            self.connectedUUID = peripheral.identifier.uuidString
        }
        log("已连接 \(peripheral.name ?? "")")
        let services: [CBUUID] = [
            store.cbuuid(store.config.serviceUUID),
            store.cbuuid(store.config.hidServiceUUID)
        ].compactMap { $0 }
        peripheral.discoverServices(services.isEmpty ? nil : services)
        // 启动 RSSI 周期读取
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            peripheral.readRSSI()
        }
    }

    func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        set { self.connectionState = .failed }
        log("连接失败：\(error?.localizedDescription ?? "未知")")
    }

    func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        log("设备断开：\(error?.localizedDescription ?? "正常")")
        set { self.teardown() }
    }

    // iOS 后台恢复
    func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String: Any]) {
        if let peris = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in peris {
                self.peripheral = p
                p.delegate = self
                if p.state == .connected {
                    set { self.connectionState = .connected; self.connectedName = p.name ?? "" }
                    p.discoverServices(nil)
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECarKeyManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { log("发现服务失败：\(error!.localizedDescription)"); return }
        let cfg = store.config
        for service in peripheral.services ?? [] {
            let uuid = service.uuid.uuidString.lowercased()
            if uuid == cfg.serviceUUID.lowercased() {
                let chars = [cfg.writeUUID, cfg.notifyUUID].compactMap { store.cbuuid($0) }
                peripheral.discoverCharacteristics(chars, for: service)
            } else if uuid == cfg.hidServiceUUID.lowercased() {
                let chars = [cfg.hidWriteUUID, cfg.hidNotifyUUID].compactMap { store.cbuuid($0) }
                peripheral.discoverCharacteristics(chars, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard error == nil else { log("发现特征失败：\(error!.localizedDescription)"); return }
        let cfg = store.config
        let suuid = service.uuid.uuidString.lowercased()
        for c in service.characteristics ?? [] {
            let cuuid = c.uuid.uuidString.lowercased()
            if suuid == cfg.serviceUUID.lowercased() {
                if cuuid == cfg.writeUUID.lowercased() { set { self.writeChar = c } }
                if cuuid == cfg.notifyUUID.lowercased() { set { self.notifyChar = c } }
            } else if suuid == cfg.hidServiceUUID.lowercased() {
                if cuuid == cfg.hidWriteUUID.lowercased() { set { self.hidWriteChar = c } }
                if cuuid == cfg.hidNotifyUUID.lowercased() { set { self.hidNotifyChar = c } }
            }
        }
        // 开通知
        if let n = notifyChar, n.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: n)
        }
        if let n = hidNotifyChar, n.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: n)
        }
        log("服务/特征就绪，可发送指令")
    }

    func peripheral(_ peripheral: CBPeripheral,
                                didWriteValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let e = error { log("写入失败：\(e.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        if let e = error { log("通知订阅失败：\(e.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard error == nil, let v = characteristic.value else { return }
        let hex = BLECarKeyManager.dataToHex(v)
        set { self.lastResponse = hex }
        log("← 回包 [\(hex)]")
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        let r = RSSI.intValue
        let d = store.distanceMeters(rssi: r)
        set { self.rssi = r; self.distance = d }
        // 无钥匙进入：靠近解锁 / 远离上锁
        let cfg = store.config
        if cfg.autoUnlock && r > cfg.unlockRSSI && pkeState != .unlocked {
            set { self.pkeState = .unlocked }
            send(.unlock)
        } else if cfg.autoLock && r < cfg.lockRSSI && pkeState != .locked {
            set { self.pkeState = .locked }
            send(.lock)
        }
    }
}
