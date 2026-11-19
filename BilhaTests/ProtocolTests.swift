import XCTest
@testable import Bilha

/// Frames taken from a PacketLogger capture of a real Galp-app
/// reading of a Pluma--xxxxxxxxxxx (19/11/2026).
final class ProtocolTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func testChecksum() {
        // From the capture: body + (sum + 0xAA) & 0xFF.
        XCTAssertEqual(PlumaProtocol.checksum(bytes("55 6a ff 6b 52")), 0x25)
        XCTAssertEqual(PlumaProtocol.checksum(bytes("03 6a ff 6b 52")), 0xd3)
        XCTAssertEqual(PlumaProtocol.checksum(bytes("55 6a ff 6b 8b")), 0x5e)
        // The reply's checksum validates too.
        XCTAssertTrue(PlumaProtocol.isChecksumValid(bytes("03 01 00 00 00 00 00 8d 18 16 69")))
        XCTAssertFalse(PlumaProtocol.isChecksumValid(bytes("03 01 00 00 00 00 00 8d 18 16 00")))
    }

    func testFrameMatchesTheGalpApp() {
        // 0x6aff6b52 = 1795124050 = 2026-11-19 21:34:10 UTC.
        let time = Date(timeIntervalSince1970: 0x6aff6b52)
        XCTAssertEqual(PlumaProtocol.frame(.syncClock, time: time), bytes("55 6a ff 6b 52 25"))
        XCTAssertEqual(PlumaProtocol.frame(.read, time: time), bytes("03 6a ff 6b 52 d3"))
    }

    func testReadingReply() {
        let r = PlumaProtocol.reading(from: bytes("03 01 00 00 00 00 00 8d 18 16 69"))
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.isOK)
        XCTAssertEqual(r!.payload, bytes("00 00 00 00 00 8d 18 16"))
        // 19/11: the Galp app showed 24 °C and 21% for this reply.
        var reading = BottleReading()
        reading.raw = r!.hex
        XCTAssertEqual(reading.temperatureC, 24)
        XCTAssertEqual(reading.levelPercent, 22)   // provisional, Galp showed 21%
        // A bad checksum or wrong command is rejected.
        XCTAssertNil(PlumaProtocol.reading(from: bytes("03 01 00 00 00 00 00 8d 18 16 00")))
        XCTAssertNil(PlumaProtocol.reading(from: bytes("55 6a ff 6b 52 25")))
    }

    /// From the log: the bottle was "Pluma--xxxxxxxxxxx" at -46 dBm.
    func testPicksTheClosestPluma() {
        XCTAssertTrue(PlumaProtocol.isPluma("Pluma--xxxxxxxxxxx"))
        XCTAssertTrue(PlumaProtocol.isPluma("pluma--xxxxxxxxxxx"))
        XCTAssertFalse(PlumaProtocol.isPluma("Plumage"))
        XCTAssertFalse(PlumaProtocol.isPluma("Fridge"))
        XCTAssertEqual(PlumaProtocol.closest([("Pluma--1", -82), ("Pluma--xxxxxxxxxxx", -46), ("Pluma--3", -70)]),
                       "Pluma--xxxxxxxxxxx")
        XCTAssertNil(PlumaProtocol.closest([("Pluma--1", -90)]))
    }

    func testBottleStorage() throws {
        var b = Bottle(deviceName: "Pluma--xxxxxxxxxxx")
        XCTAssertEqual(b.title, "Pluma--xxxxxxxxxxx")
        b.label = "Kitchen"
        XCTAssertEqual(b.title, "Kitchen")
        var r = BottleReading()
        r.raw = "03 01 00 00 00 00 00 8D 18 16 69"
        r.galpPercent = 60
        b.readings = [r]
        XCTAssertEqual(r.payload, [0, 0, 0, 0, 0, 0x8D, 0x18, 0x16])
        let back = try JSONDecoder().decode([Bottle].self, from: JSONEncoder().encode([b]))
        XCTAssertEqual(back, [b])
    }

    func testLanguageSwitch() {
        let d = UserDefaults.standard
        let old = d.string(forKey: AppLanguage.storageKey)
        defer { d.set(old, forKey: AppLanguage.storageKey) }
        d.set("pt", forKey: AppLanguage.storageKey)
        XCTAssertEqual(L("Read bottle"), "Ler garrafa")
        XCTAssertEqual(L("Remove %@?", "Cozinha"), "Remover Cozinha?")
        d.set("en", forKey: AppLanguage.storageKey)
        XCTAssertEqual(L("Read bottle"), "Read bottle")
    }
}
