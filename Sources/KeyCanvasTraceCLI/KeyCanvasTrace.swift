import CoreFoundation
import Darwin
import Foundation
import KeyCanvasTraceCore

@main
struct KeyCanvasTrace {
  static func main() {
    do {
      let command = try Command(arguments: Array(CommandLine.arguments.dropFirst()))
      switch command {
      case .help:
        print(Command.usage)
      case .summary(let path, let json):
        let trace = try TraceFile.load(path: path)
        let result = OfflineHIDTraceAnalyzer.summary(trace)
        if json {
          print(try JSONOutput.render(result))
        } else {
          print(try HumanOutput.renderSummary(result))
        }
      case .diff(let beforePath, let afterPath, let json):
        let before = try TraceFile.load(path: beforePath)
        let after = try TraceFile.load(path: afterPath)
        let result = OfflineHIDTraceAnalyzer.compare(before, after)
        if json {
          print(try JSONOutput.render(result))
        } else {
          print(try HumanOutput.renderDiff(result))
        }
      }
    } catch {
      writeStandardError("keycanvas-trace: \(error.localizedDescription)\n")
      writeStandardError("Use --help for usage.\n")
      exit(EXIT_FAILURE)
    }
  }

  private static func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}

private enum Command {
  case help
  case summary(path: String, json: Bool)
  case diff(beforePath: String, afterPath: String, json: Bool)

  static let usage = """
    Usage:
      keycanvas-trace summary TRACE [--json]
      keycanvas-trace diff BEFORE AFTER [--json]
      keycanvas-trace --help

    Commands:
      summary  Decode an offline HID trace and show aggregate metadata.
      diff     Compare two offline traces and show changed byte offsets.

    Options:
      --json   Emit the Core result as JSON.
      --help   Show this help text.

    TRACE files must be regular files no larger than 2 MB. This command performs
    offline analysis only and never opens or communicates with a HID device.
    """

  init(arguments: [String]) throws {
    guard let verb = arguments.first else {
      self = .help
      return
    }

    if verb == "--help" || verb == "-h" {
      guard arguments.count == 1 else {
        throw TraceCLIError.invalidArguments("--help does not accept other arguments")
      }
      self = .help
      return
    }

    var positionals: [String] = []
    var json = false
    for argument in arguments.dropFirst() {
      switch argument {
      case "--json":
        guard !json else {
          throw TraceCLIError.invalidArguments("--json may be specified only once")
        }
        json = true
      case "--help", "-h":
        throw TraceCLIError.invalidArguments("place --help before any command")
      default:
        if argument.hasPrefix("-") {
          throw TraceCLIError.unknownOption
        }
        positionals.append(argument)
      }
    }

    switch verb {
    case "summary":
      guard positionals.count == 1 else {
        throw TraceCLIError.invalidArguments("summary requires exactly one TRACE file")
      }
      self = .summary(path: positionals[0], json: json)
    case "diff":
      guard positionals.count == 2 else {
        throw TraceCLIError.invalidArguments("diff requires BEFORE and AFTER trace files")
      }
      self = .diff(beforePath: positionals[0], afterPath: positionals[1], json: json)
    default:
      throw TraceCLIError.unknownCommand
    }
  }
}

private enum TraceFile {
  static let maximumByteCount = 2 * 1_024 * 1_024
  private static let readChunkByteCount = 64 * 1_024

  static func load(path: String) throws -> OfflineHIDTrace {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    } catch {
      throw TraceCLIError.cannotOpenInput
    }
    defer { try? handle.close() }

    var fileStatus = stat()
    guard fstat(handle.fileDescriptor, &fileStatus) == 0 else {
      throw TraceCLIError.cannotInspectInput
    }
    guard (fileStatus.st_mode & S_IFMT) == S_IFREG else {
      throw TraceCLIError.inputIsNotRegularFile
    }
    guard fileStatus.st_size >= 0 else {
      throw TraceCLIError.cannotInspectInput
    }
    guard fileStatus.st_size <= off_t(maximumByteCount) else {
      throw TraceCLIError.inputTooLarge(maximumByteCount)
    }

    var data = Data()
    data.reserveCapacity(min(Int(fileStatus.st_size), maximumByteCount + 1))
    while data.count <= maximumByteCount {
      let remainingByteCount = maximumByteCount + 1 - data.count
      let nextByteCount = min(readChunkByteCount, remainingByteCount)
      let chunk: Data
      do {
        chunk = try handle.read(upToCount: nextByteCount) ?? Data()
      } catch {
        throw TraceCLIError.cannotReadInput
      }
      if chunk.isEmpty { break }
      data.append(chunk)
    }
    guard data.count <= maximumByteCount else {
      throw TraceCLIError.inputTooLarge(maximumByteCount)
    }

    do {
      return try OfflineHIDTraceCodec.decode(data)
    } catch {
      throw TraceCLIError.invalidTrace
    }
  }
}

private enum TraceCLIError: LocalizedError {
  case unknownCommand
  case unknownOption
  case invalidArguments(String)
  case cannotOpenInput
  case cannotInspectInput
  case inputIsNotRegularFile
  case inputTooLarge(Int)
  case cannotReadInput
  case invalidTrace

  var errorDescription: String? {
    switch self {
    case .unknownCommand:
      "unknown command"
    case .unknownOption:
      "unknown option"
    case .invalidArguments(let message):
      message
    case .cannotOpenInput:
      "cannot open the input file"
    case .cannotInspectInput:
      "cannot inspect the input file"
    case .inputIsNotRegularFile:
      "the input must be a regular file"
    case .inputTooLarge(let limit):
      "the input exceeds the \(limit)-byte limit"
    case .cannotReadInput:
      "cannot read the input file"
    case .invalidTrace:
      "the input is not a valid offline trace"
    }
  }
}

private enum JSONOutput {
  static func render<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

private enum HumanOutput {
  static func renderSummary<Value: Encodable>(_ value: Value) throws -> String {
    let object = try JSONObject.make(value)
    var lines = ["Offline HID trace summary"]
    appendSummary(object, path: [], depth: 0, to: &lines)
    if lines.count == 1 {
      lines.append("No summary fields were reported.")
    }
    return lines.joined(separator: "\n")
  }

  static func renderDiff<Value: Encodable>(_ value: Value) throws -> String {
    let object = try JSONObject.make(value)
    var lines = ["Offline HID trace difference"]

    appendDiffMetadata(object, to: &lines)
    if !appendEventDifferences(object, to: &lines) {
      let offsets = collectOffsets(object, path: [])
      if offsets.isEmpty {
        lines.append("Changed offsets: none")
      } else {
        lines.append("Changed offsets:")
        lines.append(contentsOf: offsets.map { "  \($0.path): \($0.value)" })
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func appendSummary(
    _ object: Any,
    path: [String],
    depth: Int,
    to lines: inout [String]
  ) {
    guard depth <= 4 else { return }

    if let dictionary = object as? [String: Any] {
      for key in dictionary.keys.sorted() {
        guard let child = dictionary[key], !isRawByteField(key) else { continue }
        let nextPath = path + [key]
        if let scalar = scalarDescription(child) {
          lines.append("\(displayPath(nextPath)): \(scalar)")
        } else if let array = child as? [Any] {
          if isOffsetField(key), let values = scalarArrayDescription(array) {
            lines.append("\(displayPath(nextPath)): \(values)")
          } else {
            lines.append("\(displayPath(nextPath)) count: \(array.count)")
            if array.count <= 256 {
              for (index, element) in array.enumerated() {
                appendSummary(
                  element,
                  path: nextPath + ["[\(index)]"],
                  depth: depth + 1,
                  to: &lines
                )
              }
            }
          }
        } else {
          appendSummary(child, path: nextPath, depth: depth + 1, to: &lines)
        }
      }
    } else if let array = object as? [Any] {
      lines.append("\(displayPath(path)) count: \(array.count)")
    }
  }

  private static func appendDiffMetadata(_ object: Any, to lines: inout [String]) {
    guard let dictionary = object as? [String: Any] else { return }
    for key in dictionary.keys.sorted() {
      guard let child = dictionary[key], isSafeDiffMetadata(key),
        let scalar = scalarDescription(child)
      else {
        continue
      }
      lines.append("\(displayPath([key])): \(scalar)")
    }
  }

  @discardableResult
  private static func appendEventDifferences(_ object: Any, to lines: inout [String]) -> Bool {
    guard let dictionary = object as? [String: Any],
      let differences = dictionary["eventDifferences"] as? [Any]
    else {
      return false
    }

    guard !differences.isEmpty else {
      lines.append("Changed events: none")
      return true
    }

    lines.append("Changed events:")
    for element in differences {
      guard let difference = element as? [String: Any] else { continue }
      let index = difference["index"].flatMap(scalarDescription) ?? "?"
      let kind = difference["kind"].flatMap(scalarDescription) ?? "changed"
      var details: [String] = []

      if let changes = difference["metadataChanges"] as? [Any],
        let rendered = scalarArrayDescription(changes), rendered != "none"
      {
        details.append("metadata: \(rendered)")
      }
      if let baselineLength = difference["baselinePayloadLength"].flatMap(scalarDescription),
        let candidateLength = difference["candidatePayloadLength"].flatMap(scalarDescription)
      {
        details.append("payload length: \(baselineLength) -> \(candidateLength)")
      }
      if let count = difference["byteDifferenceCount"].flatMap(scalarDescription) {
        details.append("byte changes: \(count)")
      }

      let offsets = (difference["byteDifferences"] as? [Any] ?? []).compactMap {
        change -> String? in
        guard let change = change as? [String: Any], let offset = change["offset"] else {
          return nil
        }
        return scalarDescription(offset)
      }
      details.append("offsets: \(offsets.isEmpty ? "none" : offsets.joined(separator: ", "))")

      let suffix = details.isEmpty ? "" : " — " + details.joined(separator: "; ")
      lines.append("  event \(index) [\(kind)]\(suffix)")
    }
    return true
  }

  private static func collectOffsets(
    _ object: Any,
    path: [String]
  ) -> [(path: String, value: String)] {
    if let dictionary = object as? [String: Any] {
      return dictionary.keys.sorted().flatMap { key -> [(String, String)] in
        guard let child = dictionary[key] else { return [] }
        let nextPath = path + [key]
        if isOffsetField(key) {
          if let scalar = scalarDescription(child) {
            return [(displayPath(nextPath), scalar)]
          }
          if let array = child as? [Any], let values = scalarArrayDescription(array) {
            return [(displayPath(nextPath), values)]
          }
        }
        return collectOffsets(child, path: nextPath)
      }
    }

    if let array = object as? [Any] {
      return array.enumerated().flatMap { index, child in
        collectOffsets(child, path: path + ["[\(index)]"])
      }
    }
    return []
  }

  private static func scalarDescription(_ value: Any) -> String? {
    switch value {
    case let string as String:
      return clean(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return number.boolValue ? "true" : "false"
      }
      return number.stringValue
    case _ as NSNull:
      return "null"
    default:
      return nil
    }
  }

  private static func scalarArrayDescription(_ values: [Any]) -> String? {
    guard values.count <= 4_096 else { return "\(values.count) offsets" }
    let descriptions = values.compactMap(scalarDescription)
    guard descriptions.count == values.count else { return nil }
    return descriptions.isEmpty ? "none" : descriptions.joined(separator: ", ")
  }

  private static func isRawByteField(_ key: String) -> Bool {
    let normalized = key.lowercased()
    let allowedCounts = [
      "bytecount", "bytescount", "totalpayloadbytes", "payloadlength", "reportlength",
    ]
    if allowedCounts.contains(normalized) { return false }
    return ["payload", "bytes", "raw", "data", "hex", "contents", "before", "after"]
      .contains(where: normalized.contains)
  }

  private static func isOffsetField(_ key: String) -> Bool {
    key.lowercased().contains("offset")
  }

  private static func isSafeDiffMetadata(_ key: String) -> Bool {
    let normalized = key.lowercased()
    guard !isRawByteField(key), !isOffsetField(key) else { return false }
    return [
      "count", "equal", "identical", "changed", "added", "removed", "difference", "truncated",
    ]
    .contains(where: normalized.contains)
  }

  private static func displayPath(_ components: [String]) -> String {
    components.joined(separator: ".")
  }

  private static func clean(_ string: String) -> String {
    string
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
  }
}

private enum JSONObject {
  static func make<Value: Encodable>(_ value: Value) throws -> Any {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }
}
