import Foundation

/// Bluetooth protocol of the Galp Pluma bottle, worked out from a
/// PacketLogger capture of a real Galp-app reading (19/11/2026). See
/// PROTOCOLO-BLE.md.
///
/// Service D973F2E0-…, characteristic D973F2E1-… (write-with-response + notify).
/// Every frame is `command + Unix time (4 bytes, big-endian) + checksum`,
/// where checksum = (sum of the other bytes + 0xAA) & 0xFF.
enum PlumaProtocol {
    static let serviceUUID = "D973F2E0-B19E-11E2-9E96-0800200C9A66"
    static let characteristicUUID = "D973F2E1-B19E-11E2-9E96-0800200C9A66"

    /// Commands the Galp app sends, each followed by the current time.
    enum Command: UInt8 {
        case syncClock = 0x55   // sets the bottle's clock to the given time
        case read = 0x03        // asks for a reading; the reply echoes 0x03
    }

    static let namePrefix = "Pluma--"
    static func isPluma(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(namePrefix.lowercased())
    }

    /// Closest candidate, if it's close enough to be the bottle next to the phone.
    /// Used only for bottles added by the early QR version (no stored name).
    static func closest(_ candidates: [(name: String, rssi: Int)], minimumRSSI: Int = -75) -> String? {
        candidates.filter { $0.rssi >= minimumRSSI && $0.rssi < 0 }.max { $0.rssi < $1.rssi }?.name
    }

    /// checksum = (sum of bytes + 0xAA) & 0xFF
    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8((bytes.reduce(0) { $0 + Int($1) } + 0xAA) & 0xFF)
    }

    /// `command + time(4, big-endian) + checksum`.
    static func frame(_ command: Command, time: Date = Date()) -> [UInt8] {
        let t = UInt32(max(0, time.timeIntervalSince1970))
        var body: [UInt8] = [command.rawValue,
                             UInt8(t >> 24 & 0xFF), UInt8(t >> 16 & 0xFF),
                             UInt8(t >> 8 & 0xFF), UInt8(t & 0xFF)]
        body.append(checksum(body))
        return body
    }

    static func isChecksumValid(_ frame: [UInt8]) -> Bool {
        guard frame.count >= 2 else { return false }
        return checksum(Array(frame.dropLast())) == frame.last
    }

    /// Reply to the read command: `03 01 <data bytes> <checksum>`.
    struct Reading: Equatable {
        let raw: [UInt8]
        var isOK: Bool { raw.count >= 3 && raw[0] == Command.read.rawValue && raw[1] == 0x01 }
        /// The payload bytes between the `03 01` header and the checksum.
        var payload: [UInt8] { raw.count >= 3 ? Array(raw[2..<(raw.count - 1)]) : [] }
        var hex: String { raw.map { String(format: "%02X", $0) }.joined(separator: " ") }
    }

    static func reading(from bytes: [UInt8]) -> Reading? {
        guard bytes.first == Command.read.rawValue, isChecksumValid(bytes) else { return nil }
        return Reading(raw: bytes)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
