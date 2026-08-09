import Foundation
import XCTest

@testable import KeyCanvasTraceCore

final class OfflineHIDTraceCodecTests: XCTestCase {
  func testDecodeValidStrictDocument() throws {
    let trace = try OfflineHIDTraceCodec.decode(
      Data(
        rootJSON(events: [
          eventJSON(index: 0, offsetMicros: 0, bytesHex: "00aaff"),
          eventJSON(
            index: 1,
            offsetMicros: 125,
            direction: "device-to-host",
            transfer: "interrupt",
            reportID: 4,
            bytesHex: ""
          ),
        ]).utf8))

    XCTAssertEqual(trace.schemaVersion, 1)
    XCTAssertEqual(trace.label, "synthetic test")
    XCTAssertEqual(trace.provenance.origin, .synthetic)
    XCTAssertTrue(trace.provenance.authorizedUse)
    XCTAssertEqual(trace.events[0].bytes, [0x00, 0xAA, 0xFF])
    XCTAssertEqual(trace.events[1].offsetMicros, 125)
  }

  func testInputModelsAreNotEncodable() throws {
    let trace = try JSONDecoder().decode(
      OfflineHIDTrace.self,
      from: Data(rootJSON(events: [eventJSON(index: 0, bytesHex: "00")]).utf8)
    )

    XCTAssertNil((trace as Any) as? any Encodable)
    XCTAssertNil((trace.events[0] as Any) as? any Encodable)
  }

  func testRejectsUnknownKeysAtEveryObjectBoundary() {
    assertDecodeFails(
      rootJSON(extraRoot: ",\"extra\":true"),
      containing: "unknown key(s): extra"
    )
    assertDecodeFails(
      rootJSON(provenanceJSON: safeProvenanceJSON(dropLast: true) + ",\"extra\":true}"),
      containing: "unknown key(s): extra"
    )
    assertDecodeFails(
      rootJSON(events: [eventJSON(index: 0, extra: ",\"extra\":true")]),
      containing: "unknown key(s): extra"
    )
  }

  func testRequiresStrictProvenanceBooleans() {
    for field in [
      "authorizedUse",
      "identifiersRemoved",
      "absoluteTimestampsRemoved",
      "firmwareTrafficExcluded",
    ] {
      let provenance = safeProvenanceJSON().replacingOccurrences(
        of: "\"\(field)\":true",
        with: "\"\(field)\":false"
      )
      assertDecodeFails(
        rootJSON(provenanceJSON: provenance),
        containing: "unsafeProvenance(field: \"\(field)\")"
      )
    }
  }

  func testAcceptsBothAuthorizedOriginsAndRejectsUnknownOrigin() throws {
    for origin in ["synthetic", "authorized-private-observation"] {
      let data = Data(rootJSON(provenanceJSON: safeProvenanceJSON(origin: origin)).utf8)
      XCTAssertNoThrow(try OfflineHIDTraceCodec.decode(data))
    }

    assertDecodeFails(
      rootJSON(provenanceJSON: safeProvenanceJSON(origin: "downloaded")),
      containing: "Cannot initialize OfflineHIDTraceOrigin"
    )
  }

  func testDirectJSONDecoderCannotBypassWholeTraceValidation() {
    let invalidIndex = rootJSON(events: [
      eventJSON(index: 0),
      eventJSON(index: 2, offsetMicros: 1),
    ])
    XCTAssertThrowsError(
      try JSONDecoder().decode(OfflineHIDTrace.self, from: Data(invalidIndex.utf8))
    ) { error in
      XCTAssertEqual(
        error as? OfflineHIDTraceError,
        .nonSequentialIndex(expected: 1, actual: 2)
      )
    }

    let unsafe = rootJSON(
      provenanceJSON: safeProvenanceJSON().replacingOccurrences(
        of: "\"authorizedUse\":true",
        with: "\"authorizedUse\":false"
      )
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(OfflineHIDTrace.self, from: Data(unsafe.utf8))
    )
  }

  func testFirstPresentTimestampMustBeZeroEvenAfterMissingValues() {
    let json = rootJSON(events: [
      eventJSON(index: 0, offsetMicros: nil),
      eventJSON(index: 1, offsetMicros: 1),
    ])

    assertDecodeFails(json, containing: "firstTimestampMustBeZero(actual: 1)")
  }

  func testTimestampRangeAndMonotonicity() throws {
    let valid = rootJSON(events: [
      eventJSON(index: 0, offsetMicros: 0),
      eventJSON(index: 1, offsetMicros: nil),
      eventJSON(index: 2, offsetMicros: 0),
      eventJSON(index: 3, offsetMicros: 3_600_000_000),
    ])
    XCTAssertNoThrow(try OfflineHIDTraceCodec.decode(Data(valid.utf8)))

    assertDecodeFails(
      rootJSON(events: [
        eventJSON(index: 0, offsetMicros: 0),
        eventJSON(index: 1, offsetMicros: 3_600_000_001),
      ]),
      containing: "timestampOutOfRange"
    )
    assertDecodeFails(
      rootJSON(events: [
        eventJSON(index: 0, offsetMicros: 0),
        eventJSON(index: 1, offsetMicros: 10),
        eventJSON(index: 2, offsetMicros: 9),
      ]),
      containing: "nonMonotonicTimestamp"
    )
  }

  func testRejectsOddUppercaseAndNonHexPayloads() {
    for value in ["0", "0x", "gg", "00 11", "AA"] {
      assertDecodeFails(
        rootJSON(events: [eventJSON(index: 0, bytesHex: value)]),
        containing: "invalidHex"
      )
    }
  }

  func testRejectsPayloadLargerThan4096Bytes() {
    let hex = String(repeating: "00", count: 4_097)
    assertDecodeFails(
      rootJSON(events: [eventJSON(index: 0, bytesHex: hex)]),
      containing: "payloadTooLarge"
    )
  }

  func testRejectsTotalPayloadLargerThanTwoMegabytes() {
    let bytes = [UInt8](repeating: 0, count: 4_096)
    let events = (0..<513).map { index in
      OfflineHIDTraceEvent(
        index: index,
        direction: .hostToDevice,
        transfer: .control,
        reportID: 0,
        bytes: bytes
      )
    }
    let trace = OfflineHIDTrace(
      label: "large",
      provenance: safeProvenance(),
      events: events
    )

    XCTAssertThrowsError(try OfflineHIDTraceValidator.validate(trace)) { error in
      XCTAssertEqual(
        error as? OfflineHIDTraceError,
        .totalPayloadTooLarge(maximum: 2_097_152, actual: 2_101_248)
      )
    }
  }

  func testRejectsInputDocumentLargerThanTwoMegabytesBeforeParsing() {
    let data = Data(repeating: 0x20, count: 2_097_153)

    XCTAssertThrowsError(try OfflineHIDTraceCodec.decode(data)) { error in
      XCTAssertEqual(
        error as? OfflineHIDTraceError,
        .documentTooLarge(maximum: 2_097_152, actual: 2_097_153)
      )
    }
  }

  func testRejectsMoreThanTenThousandEvents() {
    let events = (0...10_000).map { eventJSON(index: $0, bytesHex: "") }
    assertDecodeFails(rootJSON(events: events), containing: "tooManyEvents")
  }

  func testLabelSchemaEnumsAndReportIDAreStrict() throws {
    for label in ["   ", "line\nbreak", String(repeating: "a", count: 129)] {
      assertDecodeFails(rootJSON(label: label), containing: "invalidLabel")
    }

    XCTAssertNoThrow(
      try OfflineHIDTraceCodec.decode(
        Data(rootJSON(label: String(repeating: "한", count: 42)).utf8)
      )
    )
    assertDecodeFails(
      rootJSON(label: String(repeating: "한", count: 43)),
      containing: "invalidLabel"
    )
    assertDecodeFails(
      rootJSON(schemaVersion: 2),
      containing: "unsupportedSchemaVersion"
    )
    assertDecodeFails(
      rootJSON(events: [eventJSON(index: 0, direction: "sideways")]),
      containing: "OfflineHIDTraceDirection"
    )
    assertDecodeFails(
      rootJSON(events: [eventJSON(index: 0, transfer: "feature")]),
      containing: "OfflineHIDTransferKind"
    )

    let invalidReport = eventJSON(index: 0).replacingOccurrences(
      of: "\"reportID\":0",
      with: "\"reportID\":256"
    )
    XCTAssertThrowsError(
      try OfflineHIDTraceCodec.decode(Data(rootJSON(events: [invalidReport]).utf8))
    )
  }

  private func rootJSON(
    schemaVersion: Int = 1,
    label: String = "synthetic test",
    provenanceJSON: String? = nil,
    events: [String] = [],
    extraRoot: String = ""
  ) -> String {
    """
    {"schemaVersion":\(schemaVersion),"label":\(jsonString(label)),
     "provenance":\(provenanceJSON ?? safeProvenanceJSON()),
     "events":[\(events.joined(separator: ","))]\(extraRoot)}
    """
  }

  private func eventJSON(
    index: Int,
    offsetMicros: UInt64? = nil,
    direction: String = "host-to-device",
    transfer: String = "control",
    reportID: UInt8 = 0,
    bytesHex: String = "00",
    extra: String = ""
  ) -> String {
    let timestamp = offsetMicros.map { ",\"offsetMicros\":\($0)" } ?? ""
    return
      "{\"index\":\(index)\(timestamp),\"direction\":\"\(direction)\","
      + "\"transfer\":\"\(transfer)\",\"reportID\":\(reportID),"
      + "\"bytesHex\":\"\(bytesHex)\"\(extra)}"
  }

  private func safeProvenanceJSON(
    origin: String = "synthetic",
    dropLast: Bool = false
  ) -> String {
    let body =
      "{\"origin\":\"\(origin)\",\"authorizedUse\":true,"
      + "\"identifiersRemoved\":true,\"absoluteTimestampsRemoved\":true,"
      + "\"firmwareTrafficExcluded\":true}"
    return dropLast ? String(body.dropLast()) : body
  }

  private func safeProvenance() -> OfflineHIDTraceProvenance {
    OfflineHIDTraceProvenance(
      origin: .synthetic,
      authorizedUse: true,
      identifiersRemoved: true,
      absoluteTimestampsRemoved: true,
      firmwareTrafficExcluded: true
    )
  }

  private func jsonString(_ value: String) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  private func assertDecodeFails(
    _ json: String,
    containing expectedText: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try OfflineHIDTraceCodec.decode(Data(json.utf8)),
      file: file,
      line: line
    ) { error in
      XCTAssertTrue(
        String(describing: error).contains(expectedText),
        "expected error containing '\(expectedText)', got '\(error)'",
        file: file,
        line: line
      )
    }
  }
}
