// SW³ TextFellow — ULID Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import SW3TTextEngine

@Test func ulidUniqueness() {
    let a = ULID()
    let b = ULID()
    #expect(a != b)
}

@Test func ulidStringIs26Characters() {
    let id = ULID()
    #expect(id.ulidString.count == 26)
}

@Test func ulidLexicographicOrderMatchesChronological() throws {
    let a = ULID()
    // ULIDs created later should sort after earlier ones
    // (within the same millisecond, randomness determines order,
    // but across milliseconds, timestamp dominates)
    Thread.sleep(forTimeInterval: 0.002) // 2ms gap
    let b = ULID()
    #expect(a < b)
}

@Test func ulidTimestampIsReasonable() {
    let id = ULID()
    let now = Date()
    let ulidDate = id.date
    // ULID timestamp should be within 1 second of now
    #expect(abs(now.timeIntervalSince(ulidDate)) < 1.0)
}

@Test func ulidComparable() {
    let a = ULID(high: 1, low: 0)
    let b = ULID(high: 2, low: 0)
    let c = ULID(high: 1, low: 1)
    #expect(a < b)
    #expect(a < c)
}

@Test func ulidHashable() {
    let a = ULID(high: 42, low: 99)
    let b = ULID(high: 42, low: 99)
    #expect(a == b)

    var set: Set<ULID> = [a]
    set.insert(b)
    #expect(set.count == 1) // same value, should dedup
}
