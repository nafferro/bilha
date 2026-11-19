import Foundation

struct BottleEvent: Identifiable, Equatable, Codable {
    var id: Date { date }
    let date: Date
    let type: Int
}

/// One reading. The bottle replies `03 01 <data> <checksum>`; what the data
/// bytes mean isn't confirmed yet (see PROTOCOLO-BLE.md), so the raw reply is
/// kept and the Galp app's % is typed in by hand to work it out.
struct BottleReading: Identifiable, Equatable, Codable {
    var id: Date { date }
    var date = Date()
    /// Full reply from the bottle, hex (e.g. "03 01 00 00 00 00 00 8D 18 16 69").
    var raw: String?
    /// What the Galp app showed at the same time.
    var galpPercent: Int?

    /// Payload bytes (between the 03 01 header and the checksum).
    var payload: [Int] {
        let parts = (raw ?? "").split(separator: " ").compactMap { UInt8($0, radix: 16) }
        guard parts.count >= 3 else { return [] }
        return parts[2..<(parts.count - 1)].map(Int.init)
    }

    /// Temperature in °C — payload byte 6. Confirmed: 0x18 → 24 °C (19/11).
    var temperatureC: Int? {
        payload.count >= 7 ? Int(Int8(truncatingIfNeeded: payload[6])) : nil
    }

    /// Gas level %, from payload byte 7. Provisional: 0x16 (22) ↔ Galp 21% (19/11).
    var levelPercent: Int? {
        payload.count >= 8 ? payload[7] : nil
    }

    var csvLine: String {
        let f = ISO8601DateFormatter()
        return [f.string(from: date), levelPercent.map(String.init), temperatureC.map(String.init),
                galpPercent.map(String.init), raw]
            .map { $0 ?? "" }
            .joined(separator: ",")
    }

    static let csvHeader = "date,level_byte7,temperature_c,galp_percent,raw_reply"
}

/// One Pluma, added by Bluetooth.
struct Bottle: Identifiable, Equatable, Codable {
    var id = UUID()
    /// Bluetooth name, e.g. "Pluma--xxxxxxxxxxx". Nil only for bottles added
    /// by QR code in an early test version; they pick the closest Pluma once.
    var deviceName: String?
    /// Label the user can change, e.g. "Kitchen".
    var label: String?
    /// iOS identifier of the bottle, learnt at the first reading.
    var peripheralID: UUID?
    var readings: [BottleReading] = []
    var events: [BottleEvent] = []
    var addedOn = Date()

    var title: String { (label?.isEmpty == false ? label : nil) ?? deviceName ?? "Pluma" }
    var latest: BottleReading? { readings.first }

    var csv: String {
        ([BottleReading.csvHeader] + readings.map(\.csvLine)).joined(separator: "\n")
    }
}

/// Bottles kept on the phone.
enum BottleStore {
    private static let key = "bottles"

    static func load() -> [Bottle] {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Bottle].self, from: data) {
            return list
        }
        return migrateSingleBottle()
    }

    static func save(_ list: [Bottle]) {
        let trimmed = list.map { b -> Bottle in
            var b = b
            b.readings = Array(b.readings.prefix(200))
            return b
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// The first version kept one bottle in separate keys.
    private static func migrateSingleBottle() -> [Bottle] {
        let d = UserDefaults.standard
        guard let code = d.string(forKey: "bottleCode") else { return [] }
        _ = code
        var b = Bottle()
        b.peripheralID = d.string(forKey: "bottleIdentifier").flatMap(UUID.init(uuidString:))
        if let data = d.data(forKey: "readings"),
           let list = try? JSONDecoder().decode([BottleReading].self, from: data) {
            b.readings = list
        }
        save([b])
        ["bottleCode", "bottleIdentifier", "readings", "bottleName"].forEach(d.removeObject(forKey:))
        return [b]
    }
}
