//
//  ContentView.swift
//  DateReminder
//
//  Created by Dennis on 2026/3/20.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    @State private var showingAdd = false
    @State private var hasRequestedAuth = false
    @State private var exportDocument = DateReminderCSVDocument()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var editingItem: Item?
    @State private var deleteOffsets: IndexSet?
    @State private var showDeleteConfirm = false
    
    private var orderedItems: [Item] {
        items.sorted { (lhs, rhs) in
            (lhs.nextTriggerDate ?? .distantFuture) < (rhs.nextTriggerDate ?? .distantFuture)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if orderedItems.isEmpty {
                    ContentUnavailableView("还没有日期", systemImage: "calendar.badge.plus", description: Text("点右上角“+”新增一个日期"))
                } else {
                    ForEach(orderedItems) { item in
                        DateReminderRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingItem = item
                            }
                    }
                    .onDelete { offsets in
                        deleteOffsets = offsets
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("DateReminder")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("新增日期", systemImage: "plus")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    dataMenu
                }
                #else
                ToolbarItem(placement: .automatic) {
                    dataMenu
                }
                #endif
            }
        }
        .sheet(isPresented: $showingAdd) {
            DateReminderFormView(item: nil) { newItem in
                modelContext.insert(newItem)
                Task { await NotificationScheduler.shared.refreshNotifications(for: items) }
            }
        }
        .sheet(item: $editingItem) { item in
            DateReminderFormView(item: item) { updated in
                item.name = updated.name
                item.date = updated.date
                item.year = updated.year
                item.calendarType = updated.calendarType
                item.remind = updated.remind
                item.reminderHour = updated.reminderHour
                item.reminderMinute = updated.reminderMinute
                Task { await NotificationScheduler.shared.refreshNotifications(for: items) }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "DateReminder.csv"
        ) { _ in }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            switch result {
            case .success(let url):
                importCSV(from: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("好的", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("确认删除?", isPresented: $showDeleteConfirm, actions: {
            Button("删除", role: .destructive) {
                if let offsets = deleteOffsets { deleteItems(offsets: offsets) }
                deleteOffsets = nil
            }
            Button("取消", role: .cancel) {
                deleteOffsets = nil
            }
        }, message: {
            Text("删除后无法恢复该日期")
        })
        .task {
            guard !hasRequestedAuth else { return }
            hasRequestedAuth = true
            await NotificationScheduler.shared.requestAuthorization()
            await NotificationScheduler.shared.refreshNotifications(for: items)
        }
        .onChange(of: items) { _, _ in
            Task { await NotificationScheduler.shared.refreshNotifications(for: items) }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(orderedItems[index])
            }
        }
        Task { await NotificationScheduler.shared.refreshNotifications(for: items) }
    }
    
    private func importCSV(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                importError = "文件编码不是 UTF-8"
                return
            }
            let imported = DateReminderCSVCodec.import(from: text)
            guard !imported.isEmpty else {
                importError = "未解析到有效数据"
                return
            }
            withAnimation {
                imported.forEach { modelContext.insert($0) }
            }
            Task { await NotificationScheduler.shared.refreshNotifications(for: items) }
        } catch {
            importError = error.localizedDescription
        }
    }
    
    private var dataMenu: some View {
        Menu {
            Button {
                exportDocument = DateReminderCSVDocument(text: DateReminderCSVCodec.export(items: items))
                showExporter = true
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("导入 CSV", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("数据", systemImage: "doc.badge.plus")
        }
    }
}

private struct DateReminderRow: View {
    let item: Item
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(dateDescription(for: item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.calendarType.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let next = item.nextTriggerDate {
                    Text(daysLeftText(until: next))
                        .font(.subheadline.weight(.semibold))
                }
                if item.remind {
                    Label(item.reminderTimeText, systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private func dateDescription(for item: Item) -> String {
        let formatter = DateFormatter()
        formatter.calendar = item.calendarType == .lunar ? Calendar(identifier: .chinese) : Calendar.current
        
        let dateString: String
        if let year = item.year {
            if item.calendarType == .lunar {
                formatter.dateFormat = "MM月dd日"
                dateString = "\(year)年" + formatter.string(from: item.date)
            } else {
                formatter.dateFormat = "yyyy年MM月dd日"
                dateString = formatter.string(from: item.date)
            }
        } else {
            formatter.dateFormat = "MM月dd日"
            dateString = formatter.string(from: item.date)
        }
        
        var parts = [dateString]
        
        // 预览的下一个提醒日加上公历年份
        if let next = item.nextTriggerDate {
            let nextFormatter = DateFormatter()
            nextFormatter.dateFormat = "yyyy-MM-dd"
            if item.calendarType == .lunar {
                parts.append("下次阳历: " + nextFormatter.string(from: next))
            } else {
                parts.append("下次: " + nextFormatter.string(from: next))
            }
        }
        
        return parts.joined(separator: "  ")
    }
    
    private func daysLeftText(until date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 {
            return "今天"
        } else {
            return "还有\(days)天"
        }
    }
}

private struct DateReminderFormView: View {
    @Environment(\.dismiss) private var dismiss
    
    var item: Item?
    var onSave: (Item) -> Void
    
    @State private var name: String
    @State private var yearText: String
    @State private var monthText: String
    @State private var dayText: String
    @State private var calendarType: CalendarType
    @State private var remind: Bool
    @State private var reminderTime: Date
    
    init(item: Item?, onSave: @escaping (Item) -> Void) {
        self.item = item
        self.onSave = onSave
        let now = Date()
        if let item {
            let gregorian = Calendar.current
            let chinese = Calendar(identifier: .chinese)
            let sourceCal = item.calendarType == .lunar ? chinese : gregorian
            let monthDayComps = sourceCal.dateComponents([.month, .day], from: item.date)
            
            _name = State(initialValue: item.name)
            _yearText = State(initialValue: item.year.map { "\($0)" } ?? "")
            _monthText = State(initialValue: monthDayComps.month.map { "\($0)" } ?? "")
            _dayText = State(initialValue: monthDayComps.day.map { "\($0)" } ?? "")
            _calendarType = State(initialValue: item.calendarType)
            _remind = State(initialValue: item.remind)
            _reminderTime = State(initialValue: gregorian.date(from: DateComponents(hour: item.reminderHour, minute: item.reminderMinute)) ?? now)
        } else {
            _name = State(initialValue: "")
            _yearText = State(initialValue: "")
            _monthText = State(initialValue: "")
            _dayText = State(initialValue: "")
            _calendarType = State(initialValue: .solar)
            _remind = State(initialValue: true)
            _reminderTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 11, minute: 0)) ?? now)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("日历提醒信息") {
                    TextField("名称（如：结婚日期）", text: $name)
                    Picker("日期类型", selection: $calendarType) {
                        ForEach(CalendarType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        numericFieldWithSuffix(text: $yearText, width: 80, suffix: "年", placeholder: "可选")
                        numericFieldWithSuffix(text: $monthText, width: 50, suffix: "月", placeholder: "月")
                        numericFieldWithSuffix(text: $dayText, width: 50, suffix: "日", placeholder: "日")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Section("提醒") {
                    Toggle("需要提醒", isOn: $remind)
                    DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .disabled(!remind)
                }
            }
            .navigationTitle(item == nil ? "新增日历提醒" : "编辑日历提醒")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedDate() == nil)
                }
            }
        }
    }
    
    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        guard let result = parsedDate() else { return }
        let newItem = Item(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            date: result.date,
            year: result.year,
            calendarType: calendarType,
            remind: remind,
            reminderHour: comps.hour ?? 11,
            reminderMinute: comps.minute ?? 0
        )
        onSave(newItem)
        dismiss()
    }

    private func parsedDate() -> (date: Date, year: Int?)? {
        guard let month = Int(monthText), let day = Int(dayText),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        
        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        let trimmedYear = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredYear = Int(trimmedYear)
        let baseYear = enteredYear ?? currentYear
        
        let date: Date?
        if calendarType == .lunar {
            let chinese = Calendar(identifier: .chinese)
            let gregorian = Calendar.current
            guard let midYear = gregorian.date(from: DateComponents(year: baseYear, month: 7, day: 1)) else { return nil }
            let lunarYear = chinese.component(.year, from: midYear)
            var comps = DateComponents()
            comps.year = lunarYear
            comps.month = month
            comps.day = day
            date = chinese.date(from: comps)
        } else {
            var comps = DateComponents()
            comps.year = baseYear
            comps.month = month
            comps.day = day
            date = Calendar.current.date(from: comps)
        }
        
        guard let finalDate = date else { return nil }
        return (finalDate, enteredYear)
    }
}

// MARK: - CSV 导入导出
@ViewBuilder
private func numericFieldWithSuffix(text: Binding<String>, width: CGFloat, suffix: String, placeholder: String = "") -> some View {
#if os(iOS)
    HStack(spacing: 4) {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .frame(width: width, alignment: .leading)
            .multilineTextAlignment(.leading)
        Text(suffix)
            .foregroundColor(.secondary)
    }
#else
    HStack(spacing: 4) {
        TextField(placeholder, text: text)
            .frame(width: width, alignment: .leading)
            .multilineTextAlignment(.leading)
        Text(suffix)
            .foregroundColor(.secondary)
    }
#endif
}

// MARK: - CSV 导入导出

struct DateReminderCSVDocument: FileDocument {
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

enum DateReminderCSVCodec {
    private static let header = "name,date,calendarType,remind,reminderHour,reminderMinute,year"
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
                "\(item.reminderMinute)",
                item.year.map { "\($0)" } ?? ""
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
    
    static func `import`(from text: String) -> [Item] {
        let rows = text.split(separator: "\n")
        guard !rows.isEmpty else { return [] }
        let dataRows = rows.dropFirst()
        return dataRows.compactMap { line in
            let columns = parseCSVLine(String(line))
            guard columns.count >= 6,
                  let date = dateFormatter.date(from: columns[1]),
                  let calendarType = CalendarType(rawValue: columns[2]),
                  let remind = Bool(columns[3]),
                  let hour = Int(columns[4]),
                  let minute = Int(columns[5]) else { return nil }
            let year = columns.count > 6 ? Int(columns[6]) : nil
            return Item(
                name: columns[0],
                date: date,
                year: year,
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
        result = result.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
        return result
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
