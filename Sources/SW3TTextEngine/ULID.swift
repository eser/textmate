// SW³ TextFellow — ULID (Universally Unique Lexicographically Sortable Identifier)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 128-bit identifier: 48-bit timestamp (ms) + 80-bit randomness.
// Lexicographically sortable by creation time.
// Crockford Base32 encoded (26 characters).
//
// Spec: https://github.com/ulid/spec

import Foundation

/// A ULID — Universally Unique Lexicographically Sortable Identifier.
///
/// ```
///  ULID Layout (128 bits):
///
///  ┌──────────────────────────────────────────────┐
///  │  Timestamp (48 bits)  │  Randomness (80 bits) │
///  │  milliseconds since   │  cryptographically    │
///  │  Unix epoch            │  random               │
///  └──────────────────────────────────────────────┘
///
///  String: 01ARZ3NDEKTSV4RRFFQ69G5FAV (26 chars, Crockford Base32)
///  Sort:   lexicographic order = chronological order
/// ```
public struct ULID: Sendable, Hashable, Comparable, Identifiable, CustomStringConvertible {
    /// The raw 128-bit value stored as two UInt64s.
    public let high: UInt64  // timestamp (48 bits) + random (16 bits)
    public let low: UInt64   // random (64 bits)

    public var id: ULID { self }

    /// Generate a new ULID with the current timestamp.
    public init() {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var randomBytes = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)

        // Pack timestamp (48 bits) + first 2 random bytes into high
        let high = (timestamp << 16) | (UInt64(randomBytes[0]) << 8) | UInt64(randomBytes[1])

        // Pack remaining 8 random bytes into low
        var low: UInt64 = 0
        for i in 2..<10 {
            low = (low << 8) | UInt64(randomBytes[i])
        }

        self.high = high
        self.low = low
    }

    /// Create a ULID from raw components.
    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// The timestamp component (milliseconds since Unix epoch).
    public var timestamp: UInt64 {
        high >> 16
    }

    /// The creation date.
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }

    // MARK: - Comparable

    public static func < (lhs: ULID, rhs: ULID) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        return lhs.low < rhs.low
    }

    // MARK: - String representation (Crockford Base32)

    private static let crockfordAlphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public var description: String {
        ulidString
    }

    /// The 26-character Crockford Base32 representation.
    public var ulidString: String {
        var result = [Character](repeating: "0", count: 26)
        let alphabet = Self.crockfordAlphabet

        // Timestamp portion (10 characters from 48-bit timestamp)
        var ts = timestamp
        for i in stride(from: 9, through: 0, by: -1) {
            result[i] = alphabet[Int(ts & 0x1F)]
            ts >>= 5
        }

        // Random portion — encode high's lower 16 bits + all 64 bits of low
        // Split into manageable chunks to avoid UInt128
        let randomHigh16 = high & 0xFFFF

        // Encode low (64 bits) as 13 base32 chars (65 bits capacity, 1 spare)
        var lowVal = low
        for i in stride(from: 25, through: 13, by: -1) {
            result[i] = alphabet[Int(lowVal & 0x1F)]
            lowVal >>= 5
        }

        // Encode remaining bits from randomHigh16 + leftover from low
        var combined = (randomHigh16 << (64 - 13 * 5)) | lowVal
        for i in stride(from: 12, through: 10, by: -1) {
            result[i] = alphabet[Int(combined & 0x1F)]
            combined >>= 5
        }

        return String(result)
    }

    // MARK: - Codable

    // Encode/decode as the 26-char string for JSON/TOML compatibility.
}

extension ULID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        // Simplified: store as high/low from string
        // Full Crockford Base32 decoding would go here
        // For now, create a new ULID (loses the original value in round-trip)
        self.init()
        // TODO: Implement proper Crockford Base32 decoding
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ulidString)
    }
}

