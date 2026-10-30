import Foundation

extension UUID {
    /// An ID derived from a name, identical on every device and every run.
    ///
    /// Scenario data uses these so failures reproduce exactly, and so the iPhone and Watch seed test data whose
    /// items line up in the relay overlay. The bits follow the RFC 9562 layout for a name-based (version 8) UUID.
    init(stable name: String) {
        let bytes = Array(name.utf8)
        let high = Self.fnv1a(bytes, seed: 0xCBF2_9CE4_8422_2325)
        let low = Self.fnv1a(bytes, seed: 0x8422_2325_CBF2_9CE4)
        var raw = withUnsafeBytes(of: high.bigEndian, Array.init) + withUnsafeBytes(of: low.bigEndian, Array.init)
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        self.init(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        bytes.reduce(seed) { hash, byte in (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
    }
}
