import AK47InspectorCore
import Darwin
import Foundation

@main
struct AK47Inspect {
  static func main() {
    do {
      let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
      if options.showHelp {
        print(Options.usage)
        return
      }

      let collections = try HIDEnumerator.enumerate()
      if options.json {
        print(try JSONOutput.render(collections))
      } else {
        print(TableOutput.render(collections))
      }
    } catch {
      writeStandardError("ak47-inspect: \(error.localizedDescription)\n")
      exit(EXIT_FAILURE)
    }
  }

  private static func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}

private struct Options {
  let json: Bool
  let showHelp: Bool

  static let usage = """
    Usage: ak47-inspect [--json] [--help]

      --json  Emit a JSON array instead of a table.
      --help  Show this help text.

    The command only enumerates IOHID registry properties for VID 0x0C45,
    PID 0x800A. It does not read or write HID reports.
    """

  init(arguments: [String]) throws {
    var json = false
    var showHelp = false

    for argument in arguments {
      switch argument {
      case "--json":
        json = true
      case "--help", "-h":
        showHelp = true
      default:
        throw CLIError.unknownArgument(argument)
      }
    }

    self.json = json
    self.showHelp = showHelp
  }
}

private enum CLIError: Error, LocalizedError {
  case unknownArgument(String)

  var errorDescription: String? {
    switch self {
    case .unknownArgument(let argument):
      return "unknown argument '\(argument)'; use --help for usage"
    }
  }
}

private enum JSONOutput {
  static func render(_ collections: [HIDCollectionRecord]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(collections)
    return String(decoding: data, as: UTF8.self)
  }
}

private enum TableOutput {
  private static let headers = [
    "Product",
    "Manufacturer",
    "Transport",
    "bcdDevice",
    "Location",
    "Usage Page",
    "Usage",
    "Input",
    "Output",
    "Feature",
    "Role",
  ]

  static func render(_ collections: [HIDCollectionRecord]) -> String {
    let heading = "AK47 HID collections (VID 0x0C45 / PID 0x800A)"
    guard !collections.isEmpty else {
      return "\(heading)\nNo matching collections found."
    }

    let rows = collections.map { collection in
      [
        clean(collection.product),
        clean(collection.manufacturer),
        clean(collection.transport),
        hex(collection.versionNumber, width: 4),
        hex(collection.locationID, width: 8),
        hex(collection.usagePage, width: 4),
        hex(collection.usage, width: 4),
        decimal(collection.maxInputReportSize),
        decimal(collection.maxOutputReportSize),
        decimal(collection.maxFeatureReportSize),
        collection.role.rawValue,
      ]
    }

    let widths = headers.indices.map { index in
      ([headers[index]] + rows.map { $0[index] }).map(\.count).max() ?? 0
    }
    let headerLine = format(headers, widths: widths)
    let divider = widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-")
    let body = rows.map { format($0, widths: widths) }.joined(separator: "\n")

    return """
      \(heading)
      Report sizes are bytes.
      \(headerLine)
      \(divider)
      \(body)
      """
  }

  private static func format(_ cells: [String], widths: [Int]) -> String {
    cells.indices.map { index in
      cells[index] + String(repeating: " ", count: widths[index] - cells[index].count)
    }.joined(separator: " | ")
  }

  private static func clean(_ value: String?) -> String {
    guard let value else { return "-" }
    return
      value
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
  }

  private static func decimal(_ value: UInt64?) -> String {
    value.map(String.init) ?? "-"
  }

  private static func hex(_ value: UInt64?, width: Int) -> String {
    guard let value else { return "-" }
    return String(format: "0x%0*llX", width, value)
  }
}
