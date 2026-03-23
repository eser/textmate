// SW³ TextFellow — EditOperation & OperationLog Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import SW3TTextEngine

@Test func insertOperationInverse() {
    let op = EditOperation.insert(offset: 5, text: "hello", timestamp: 1)
    let inv = op.inverse
    if case .delete(let offset, let length, let deleted, _) = inv {
        #expect(offset == 5)
        #expect(length == 5)
        #expect(deleted == "hello")
    } else {
        Issue.record("Expected delete operation")
    }
}

@Test func deleteOperationInverse() {
    let op = EditOperation.delete(offset: 3, length: 4, deletedText: "test", timestamp: 2)
    let inv = op.inverse
    if case .insert(let offset, let text, _) = inv {
        #expect(offset == 3)
        #expect(text == "test")
    } else {
        Issue.record("Expected insert operation")
    }
}

@Test func operationLogRecordsInOrder() {
    let log = OperationLog()
    let ts1 = log.nextTimestamp()
    let ts2 = log.nextTimestamp()

    log.record(.insert(offset: 0, text: "A", timestamp: ts1))
    log.record(.insert(offset: 1, text: "B", timestamp: ts2))

    #expect(log.count == 2)
    #expect(log.operations[0].timestamp == 1)
    #expect(log.operations[1].timestamp == 2)
}

@Test func operationLogTimestampsAreMonotonic() {
    let log = OperationLog()
    let ts1 = log.nextTimestamp()
    let ts2 = log.nextTimestamp()
    let ts3 = log.nextTimestamp()

    #expect(ts1 < ts2)
    #expect(ts2 < ts3)
}
