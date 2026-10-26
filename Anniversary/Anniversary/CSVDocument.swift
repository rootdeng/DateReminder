import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AnniversaryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }
    
    var text: String
    
    init(text: String = "") {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}

struct AnniversaryCSVCodec {
    private static let header = "name,date,calendarType,remind,reminderHour,reminderMinute"
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    static func export(items: [Item]) -> String {
        var lines = [header]
        for item in items {
            let dateString = dateFormatter.string(from: item.date)
            let row = [
                escape(item.name),
                dateString,
                item.calendarType.rawValue,
                item.remind ? "true" : "false",
                "\(item.reminderHour)",
                "\(item.reminderMinute)"
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
    
    static func `import`(from text: String) -> [Item] {
        let rows = text.split(separator: "\n")
        guard !rows.isEmpty else { return [] }
        let dataRows = rows.dropFirst() // skip header
        return dataRows.compactMap { line in
            let columns = parseCSVLine(String(line))
            guard columns.count == 6,
                  let date = dateFormatter.date(from: columns[1]),
                  let calendarType = CalendarType(rawValue: columns[2]),
                  let remind = Bool(columns[3]),
                  let hour = Int(columns[4]),
                  let minute = Int(columns[5]) else { return nil }
            return Item(
                name: columns[0],
                date: date,
                calendarType: calendarType,
                remind: remind,
                reminderHour: hour,
                reminderMinute: minute
            )
        }
    }
    
    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
    
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        
        for char in line {
            switch char {
            case "\"":
                insideQuotes.toggle()
            case "," where !insideQuotes:
                result.append(current)
                current = ""
            default:
                current.append(char)
            }
        }
        result.append(current)
        
        // unescape quotes
        result = result.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
        return result
    }
}
