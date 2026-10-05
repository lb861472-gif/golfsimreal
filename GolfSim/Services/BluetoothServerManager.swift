import Foundation
import CoreBluetooth
import Combine

/// Bandwidth-optimized BLE peripheral: samples stay on-device at 100 Hz.
/// Only a finalized impact payload is notified to centrals.
final class BluetoothServerManager: NSObject, ObservableObject {
    static let shared = BluetoothServerManager()

    static let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-567812345678")
    static let characteristicUUID = CBUUID(string: "87654321-4321-6789-4321-678943218765")

    @Published var isAdvertising = false
    @Published var subscriberCount = 0
    @Published var lastPacketJSON: String = ""
    @Published var stateText = "Idle"

    private var peripheral: CBPeripheralManager!
    private var impactCharacteristic: CBMutableCharacteristic?
    private let queue = DispatchQueue(label: "golfsim.ble", qos: .userInitiated)

    private override init() {
        super.init()
        peripheral = CBPeripheralManager(delegate: self, queue: queue, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: "golfsim.ble.peripheral"
        ])
    }

    func startAdvertisingIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.peripheral.state == .poweredOn {
                self.configureAndAdvertise()
            }
        }
    }

    func stopAdvertising() {
        queue.async { [weak self] in
            self?.peripheral.stopAdvertising()
            DispatchQueue.main.async { self?.isAdvertising = false; self?.stateText = "Stopped" }
        }
    }

    func broadcastImpact(_ metrics: SwingMetrics) {
        guard !metrics.isPractice else { return }
        let payload: [String: Any] = [
            "type": "impact",
            "id": metrics.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: metrics.timestamp),
            "peakAccelerationG": metrics.peakAccelerationG,
            "peakGyro": metrics.peakGyro,
            "clubheadSpeedMph": metrics.clubheadSpeedMph,
            "launchAngleDeg": metrics.launchAngleDeg,
            "launchDirectionDeg": metrics.launchDirectionDeg,
            "smashQuality": metrics.smashQuality,
            "club": metrics.club.rawValue,
            "carryEstimateYards": metrics.carryEstimateYards
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let characteristic = impactCharacteristic else { return }

        let json = String(data: data, encoding: .utf8) ?? ""
        DispatchQueue.main.async { self.lastPacketJSON = json }

        queue.async { [weak self] in
            guard let self else { return }
            let ok = self.peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
            if !ok {
                DispatchQueue.main.async { self.stateText = "Notify queue full — retrying" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.broadcastImpact(metrics)
                }
            }
        }
    }

    private func configureAndAdvertise() {
        if peripheral.isAdvertising {
            DispatchQueue.main.async { self.isAdvertising = true; self.stateText = "Advertising" }
            return
        }

        peripheral.removeAllServices()

        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        impactCharacteristic = characteristic

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheral.add(service)

        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "GolfSim Controller"
        ])
    }
}

extension BluetoothServerManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let text: String
        switch peripheral.state {
        case .poweredOn:
            text = "Bluetooth on"
            configureAndAdvertise()
        case .poweredOff: text = "Bluetooth off"
        case .unauthorized: text = "Bluetooth unauthorized"
        case .unsupported: text = "Bluetooth unsupported"
        case .resetting: text = "Bluetooth resetting"
        default: text = "Bluetooth unknown"
        }
        DispatchQueue.main.async { self.stateText = text }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        DispatchQueue.main.async {
            self.isAdvertising = error == nil
            self.stateText = error?.localizedDescription ?? "Advertising GolfSim Controller"
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            DispatchQueue.main.async { self.stateText = "GATT error: \(error.localizedDescription)" }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        DispatchQueue.main.async { self.subscriberCount += 1 }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        DispatchQueue.main.async { self.subscriberCount = max(0, self.subscriberCount - 1) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if let data = lastPacketJSON.data(using: .utf8), request.offset <= data.count {
            request.value = data.subdata(in: request.offset..<data.count)
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .invalidOffset)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        DispatchQueue.main.async { self.stateText = "Restored BLE state" }
    }
}
