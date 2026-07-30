import Foundation
import CoreBluetooth

/// ============================================================
/// BlueDebug iOS BLE Bridge
/// 基于 CoreBluetooth 封装 BLE 连接、特征通知、GATT 操作
/// 适配 iOS 14 ~ iOS 18
/// ============================================================

class BleBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    static let shared = BleBridge()

    private var centralManager: CBCentralManager?
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var discoveredServices: [String: [CBService]] = [:]

    // 扫描回调
    var scanResultHandler: ((String, String, Int) -> Void)?
    var connectHandler: ((String, Bool) -> Void)?
    var notifyHandler: ((String, String, Data) -> Void)?

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - 扫描

    func startScan(timeout: TimeInterval = 10) {
        guard centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.centralManager?.stopScan()
        }
    }

    func stopScan() {
        centralManager?.stopScan()
    }

    // MARK: - 连接

    func connect(mac: String) {
        // iOS 无法直接通过 MAC 连接，需要通过 UUID
        // 实际使用中通过扫描结果保存的 peripheral 对象连接
        // TODO: 实现 UUID 映射机制
    }

    func disconnect(mac: String) {
        if let peripheral = connectedPeripherals[mac] {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    func disconnectAll() {
        for (_, peripheral) in connectedPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BlueDebug] Bluetooth powered on")
        case .poweredOff:
            print("[BlueDebug] Bluetooth powered off")
        case .unauthorized:
            print("[BlueDebug] Bluetooth unauthorized - check permissions")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssiRSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown"
        let mac = peripheral.identifier.uuidString
        scanResultHandler?(mac, name, rssiRSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        let mac = peripheral.identifier.uuidString
        connectedPeripherals[mac] = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        print("[BlueDebug] Connected to \(mac)")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let mac = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: mac)
        print("[BlueDebug] Disconnected from \(mac)")
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard error == nil else {
            print("[BlueDebug] Discover services error: \(error!)")
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else { return }
        let mac = peripheral.identifier.uuidString
        var services = discoveredServices[mac] ?? []
        services.append(service)
        discoveredServices[mac] = services
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let mac = peripheral.identifier.uuidString
        notifyHandler?(mac, characteristic.uuid.uuidString, value)
    }

    // MARK: - 便捷方法

    func writeCharacteristic(mac: String, serviceUuid: String,
                             charUuid: String, data: Data) {
        guard let peripheral = connectedPeripherals[mac] else { return }
        for service in peripheral.services ?? [] {
            if service.uuid.uuidString.lowercased() == serviceUuid.lowercased() {
                for char in service.characteristics ?? [] {
                    if char.uuid.uuidString.lowercased() == charUuid.lowercased() {
                        peripheral.writeValue(data, for: char,
                                              type: .withResponse)
                        return
                    }
                }
            }
        }
    }

    func readCharacteristic(mac: String, serviceUuid: String, charUuid: String) {
        guard let peripheral = connectedPeripherals[mac] else { return }
        for service in peripheral.services ?? [] {
            if service.uuid.uuidString.lowercased() == serviceUuid.lowercased() {
                for char in service.characteristics ?? [] {
                    if char.uuid.uuidString.lowercased() == charUuid.lowercased() {
                        peripheral.readValue(for: char)
                        return
                    }
                }
            }
        }
    }

    func setNotify(mac: String, serviceUuid: String, charUuid: String,
                   enable: Bool) {
        guard let peripheral = connectedPeripherals[mac] else { return }
        for service in peripheral.services ?? [] {
            if service.uuid.uuidString.lowercased() == serviceUuid.lowercased() {
                for char in service.characteristics ?? [] {
                    if char.uuid.uuidString.lowercased() == charUuid.lowercased() {
                        peripheral.setNotifyValue(enable, for: char)
                        return
                    }
                }
            }
        }
    }
}
