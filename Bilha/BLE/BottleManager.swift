import CoreBluetooth
import Foundation
import Observation

struct FoundPluma: Identifiable, Equatable {
    let id: UUID
    let name: String
    var rssi: Int
}

enum BottleState: Equatable {
    case bluetoothOff
    case idle
    case scanning
    case connecting
    case reading
    case failed(String)
}

/// Keeps the list of bottles and reads one at a time: connect, switch on
/// notifications, send the same commands as the Galp app, then disconnect.
@MainActor
@Observable
final class BottleManager: NSObject {
    // MARK: Public state
    private(set) var bottles: [Bottle] = BottleStore.load()
    /// State of the current (or last) reading.
    private(set) var state: BottleState = .idle
    /// Bottle the current (or last) reading is for.
    private(set) var activeID: UUID?
    private(set) var log: [String] = []
    /// Plumas seen nearby while adding a bottle, closest first.
    private(set) var found: [FoundPluma] = []
    private(set) var isDiscovering = false

    func bottle(_ id: UUID) -> Bottle? { bottles.first { $0.id == id } }

    /// Is this bottle being read right now?
    func isBusy(_ id: UUID) -> Bool {
        activeID == id && [.scanning, .connecting, .reading].contains(state)
    }

    var isBusy: Bool { [.scanning, .connecting, .reading].contains(state) }

    /// Error from the last reading of this bottle, if it failed.
    func error(for id: UUID) -> String? {
        guard activeID == id, case .failed(let msg) = state else { return nil }
        return msg
    }

    // MARK: Private
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var notifyChars: [CBCharacteristic] = []
    @ObservationIgnored private var servicesLeft = 0
    @ObservationIgnored private var notifyLeft = 0
    @ObservationIgnored private var gotReply = false
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRead: UUID?
    @ObservationIgnored private var seenWhileSearching: Set<UUID> = []
    @ObservationIgnored private var candidates: [UUID: (peripheral: CBPeripheral, name: String, rssi: Int)] = [:]
    @ObservationIgnored private var pickTask: Task<Void, Never>?
    @ObservationIgnored private var wantsDiscovery = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Bottles

    /// Starts listing the Plumas nearby (names starting with "Pluma--").
    func startDiscovery() {
        found = []
        guard !isBusy else { return }
        guard central.state == .poweredOn else { wantsDiscovery = true; return }
        isDiscovering = true
        addLog("Looking for Plumas nearby")
        // Duplicates on, so the signal strength updates as the phone moves.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopDiscovery() {
        wantsDiscovery = false
        guard isDiscovering else { return }
        isDiscovering = false
        central.stopScan()
    }

    /// Adds a Pluma found nearby and reads it straight away.
    @discardableResult
    func addBottle(_ pluma: FoundPluma) -> UUID {
        stopDiscovery()
        if let existing = bottles.first(where: { $0.deviceName?.caseInsensitiveCompare(pluma.name) == .orderedSame }) {
            read(existing.id)
            return existing.id
        }
        let b = Bottle(deviceName: pluma.name, peripheralID: pluma.id)
        bottles.append(b)
        BottleStore.save(bottles)
        addLog("Added \(pluma.name)")
        read(b.id)
        return b.id
    }

    func remove(_ id: UUID) {
        if activeID == id {
            if isBusy { central.stopScan(); disconnect() }
            activeID = nil
            state = .idle
        }
        bottles.removeAll { $0.id == id }
        BottleStore.save(bottles)
    }

    func rename(_ id: UUID, to label: String) {
        update(id) { $0.label = label.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setGalpPercent(_ value: Int?, for reading: BottleReading, in id: UUID) {
        update(id) { b in
            guard let i = b.readings.firstIndex(where: { $0.id == reading.id }) else { return }
            b.readings[i].galpPercent = value
        }
    }

    func deleteReadings(at offsets: IndexSet, in id: UUID) {
        update(id) { $0.readings.remove(atOffsets: offsets) }
    }

    private func update(_ id: UUID, _ change: (inout Bottle) -> Void) {
        guard let i = bottles.firstIndex(where: { $0.id == id }) else { return }
        change(&bottles[i])
        BottleStore.save(bottles)
    }

    // MARK: - Reading

    /// One reading, like the Galp app: connect, set the clock, read, disconnect.
    func read(_ id: UUID) {
        guard let b = bottle(id), !isBusy else { return }
        stopDiscovery()
        activeID = id
        guard central.state == .poweredOn else { state = .bluetoothOff; pendingRead = id; return }
        resetSession()
        if let pid = b.peripheralID, let p = central.retrievePeripherals(withIdentifiers: [pid]).first {
            connect(to: p)
        } else {
            // Name not known yet (bottles from the QR test version): look for
            // the closest Pluma (or the name already learnt for this bottle).
            state = .scanning
            seenWhileSearching = []
            candidates = [:]
            pickTask?.cancel()
            addLog("Looking for \(b.deviceName ?? "the closest Pluma")")
            // Duplicates on, so the signal strength updates as the phone gets closer.
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.state == .scanning, self.activeID == id else { return }
                self.central.stopScan()
                self.fail(L("Couldn't find a Pluma right next to the iPhone. Put the iPhone against the bottle and try again. The Bluetooth log lists the devices it saw."))
            }
        }
    }

    private func use(_ p: CBPeripheral, name: String, for id: UUID) {
        central.stopScan()
        pickTask?.cancel()
        pickTask = nil
        addLog("Found \(name)")
        update(id) {
            $0.deviceName = name
            $0.peripheralID = p.identifier
        }
        connect(to: p)
    }

    private func connect(to p: CBPeripheral) {
        timeoutTask?.cancel()
        peripheral = p
        p.delegate = self
        state = .connecting
        addLog("Connecting to \(p.name ?? p.identifier.uuidString)")
        central.connect(p)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.state == .connecting else { return }
            self.fail(L("The bottle didn't answer. Bring the phone closer and try again."))
        }
    }

    func disconnect() {
        timeoutTask?.cancel()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    // MARK: - Session

    private func resetSession() {
        timeoutTask?.cancel()
        writeChar = nil
        notifyChars = []
        servicesLeft = 0
        notifyLeft = 0
        gotReply = false
    }

    /// The Galp app's reading: set the clock (0x55 + time), then ask for a
    /// reading (0x03 + time) and wait for the 0x03 reply.
    private func startReading() {
        state = .reading
        gotReply = false
        send(PlumaProtocol.frame(.syncClock), label: "set clock")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.state == .reading, !self.gotReply else { return }
            self.send(PlumaProtocol.frame(.read), label: "read")
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.state == .reading, !self.gotReply else { return }
            self.fail(L("The bottle didn't send a reading. Try again."))
        }
    }

    private func send(_ bytes: [UInt8], label: String) {
        guard let p = peripheral, let c = writeChar else { return }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        addLog("→ \(label): \(PlumaProtocol.hex(bytes))")
        p.writeValue(Data(bytes), for: c, type: type)
    }

    private func handle(_ bytes: [UInt8]) {
        guard !gotReply, let reading = PlumaProtocol.reading(from: bytes) else { return }
        gotReply = true
        timeoutTask?.cancel()
        var draft = BottleReading()
        draft.raw = reading.hex
        if let id = activeID {
            update(id) { $0.readings.insert(draft, at: 0) }
        }
        addLog("Reading: \(reading.hex)")
        state = .idle
        disconnect()   // like the Galp app, don't keep the bottle awake
    }

    private func fail(_ message: String) {
        pickTask?.cancel()
        pickTask = nil
        addLog("Error: \(message)")
        state = .failed(message)
        disconnect()
    }

    private func addLog(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        log.append("\(f.string(from: Date())) \(line)")
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - CBCentralManagerDelegate

extension BottleManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if state == .bluetoothOff { state = .idle }
                if let id = pendingRead { pendingRead = nil; read(id) }
                else if wantsDiscovery { wantsDiscovery = false; startDiscovery() }
            } else {
                state = .bluetoothOff
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let maker = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        MainActor.assumeIsolated {
            if isDiscovering {
                guard let name, PlumaProtocol.isPluma(name), RSSI.intValue < 0,
                      !bottles.contains(where: { $0.deviceName?.caseInsensitiveCompare(name) == .orderedSame }) else { return }
                if let i = found.firstIndex(where: { $0.id == peripheral.identifier }) {
                    found[i].rssi = RSSI.intValue
                } else {
                    found.append(FoundPluma(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
                    addLog("Seen: \(name) \(RSSI)dBm")
                }
                found.sort { $0.rssi > $1.rssi }
                return
            }
            guard state == .scanning, let id = activeID, let b = bottle(id) else { return }
            if seenWhileSearching.insert(peripheral.identifier).inserted {
                addLog("Seen: \(name ?? "(no name)") \(RSSI)dBm \(maker.isEmpty ? "" : "data=" + hex(maker))")
            }
            guard let name, PlumaProtocol.isPluma(name) else { return }
            if let known = b.deviceName {
                // Already learnt: only this exact bottle.
                guard name.caseInsensitiveCompare(known) == .orderedSame else { return }
                use(peripheral, name: name, for: id)
                return
            }
            // Skip bottles that already belong to another entry in the list.
            let taken = Set(bottles.filter { $0.id != id }.compactMap { $0.deviceName?.lowercased() })
            guard !taken.contains(name.lowercased()) else { return }
            candidates[peripheral.identifier] = (peripheral, name, RSSI.intValue)
            // Wait a moment so every Pluma nearby shows up, then take the closest.
            guard pickTask == nil else { return }
            pickTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard let self, !Task.isCancelled, self.state == .scanning, self.activeID == id else { return }
                self.pickTask = nil
                let list = self.candidates.values.map { (name: $0.name, rssi: $0.rssi) }
                guard let best = PlumaProtocol.closest(list),
                      let c = self.candidates.values.first(where: { $0.name == best }) else {
                    self.addLog("No Pluma close enough yet (needs -75 dBm or better)")
                    return
                }
                self.use(c.peripheral, name: c.name, for: id)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            addLog("Connected")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { fail(L("Couldn't connect: %@", error?.localizedDescription ?? L("unknown error"))) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            addLog("Disconnected")
            if state == .connecting || state == .reading {
                fail(L("The bottle disconnected before the reading finished."))
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BottleManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let services = peripheral.services ?? []
            servicesLeft = services.count
            if services.isEmpty { fail(L("The bottle has no services.")) }
            for s in services {
                addLog("Service \(s.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                addLog("  Char \(c.uuid.uuidString) props=0x\(String(c.properties.rawValue, radix: 16))")
                // The Pluma's command channel: write to it and listen on it.
                if c.uuid.uuidString.caseInsensitiveCompare(PlumaProtocol.characteristicUUID) == .orderedSame {
                    writeChar = c
                    notifyChars = [c]
                }
            }
            servicesLeft -= 1
            guard servicesLeft == 0 else { return }
            guard let c = writeChar else {
                fail(L("This doesn't look like a Pluma bottle (no command channel)."))
                return
            }
            addLog("Using \(c.uuid.uuidString)")
            notifyLeft = notifyChars.count
            for c in notifyChars { peripheral.setNotifyValue(true, for: c) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error { addLog("Notify \(characteristic.uuid.uuidString) failed: \(error.localizedDescription)") }
            notifyLeft -= 1
            guard notifyLeft == 0, state == .connecting else { return }
            startReading()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        MainActor.assumeIsolated {
            addLog("← \(PlumaProtocol.hex(bytes))")
            handle(bytes)
        }
    }
}
