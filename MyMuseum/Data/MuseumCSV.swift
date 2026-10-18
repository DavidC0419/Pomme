//
//  MuseumCSV.swift
//  Pomme
//
//  藏品 CSV 导出与导入模块 (Museum CSV Export & Import Engine)
//  支持 UTF-8 BOM、GBK、UTF-16 编码兼容，内置模糊与精确匹配算法。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSV 文件文档类型封装
struct MuseumCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw MuseumCSVError.invalidFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - CSV 解析错误类型
enum MuseumCSVError: LocalizedError {
    case invalidFile
    case missingHeaders
    case noDataRows

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "The selected file is empty or unreadable."
        case .missingHeaders: return "CSV must include a product_name column."
        case .noDataRows: return "The CSV file does not contain any device records below the header."
        }
    }
}

// MARK: - CSV 核心解析与序列化引擎
enum MuseumCSV {
    // 固定的英文表头，保证跨语言系统的兼容性
    static let headers = [
        "id", "product_name", "category", "custom_name", "model",
        "product_identifier", "internal_model", "region", "serial_number", "color",
        "release_year", "processor", "memory", "storage", "graphics", "screen_size",
        "system", "os_version", "jailbreak", "account", "battery", "last_charged",
        "repairs", "purchase_date", "purchase_source", "warranty_status", "price", "notes",
        "is_in_use",
        // 可选字段：若为空，匹配器会自动从图鉴推导
        "catalog_id"
    ]

    /// 导出藏品为 CSV 格式二进制数据
    static func export(_ items: [CollectionItem]) -> Data {
        let rows = items.map { item in
            [item.id, item.resolvedProductName, item.category, item.customName, item.model,
             item.productIdentifier, item.modelVersion, item.regionVersion,
             item.serialNumber, item.color, item.releaseYear, item.processor, item.memory,
             item.storage, item.graphics, item.screenSize, item.system, item.osVersion,
             item.jailbreak, item.account, item.battery, item.lastCharged, item.repairs,
             item.purchaseDate, item.purchaseSource, item.warrantyStatus, item.price, item.notes,
             item.isDailyDriver ? "true" : "false",
             item.catalogID]
                .map { escape($0 ?? "") }
        }
        return makeData(rows: [headers.map(escape)] + rows)
    }

    /// 生成空白模板 CSV
    static func blankTemplate() -> Data {
        makeData(rows: [headers.map(escape)])
    }

    /// CSV 导入结果结构体
    struct ImportResult {
        var items: [CollectionItem] = []
        var matchedCount = 0
        var unmatchedNames: [String] = []
        var totalRowsParsed = 0
        var diagnosticMessage: String?
    }

    /// 字符编码探测与安全解码 (支持 UTF-8 BOM, UTF-16, GBK / GB18030)
    private static func decodeText(from data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let str = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return str }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let str = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return str }
        }
        if let str = String(data: data, encoding: .utf8) {
            var result = str
            if result.first == "\u{FEFF}" { result.removeFirst() }
            return result
        }
        let gbkEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(gbkEncoding)
        if let str = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
            return str
        }
        var str = String(decoding: data, as: UTF8.self)
        if str.first == "\u{FEFF}" { str.removeFirst() }
        return str
    }

    /// 表头中英文标准化映射
    private static func normalizeHeader(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "product_name", "product", "name", "设备名称", "产品名称", "型号名称", "品名", "设备", "名称":
            return "product_name"
        case "category", "分类", "类别", "类型":
            return "category"
        case "model", "型号", "设备型号":
            return "model"
        case "product_identifier", "identifier", "机型标识符", "型号标识符", "标识符", "model identifier", "model_identifier":
            return "product_identifier"
        case "catalog_id", "catalogid", "图鉴id":
            return "catalog_id"
        case "custom_name", "自定义名称", "备注名称":
            return "custom_name"
        case "internal_model", "内部型号", "model ver", "modelver", "model version", "model_version", "版本号", "版本代码":
            return "internal_model"
        case "serial_number", "sn", "序列号":
            return "serial_number"
        case "color", "颜色", "配色":
            return "color"
        case "release_year", "year", "年份", "发布年份":
            return "release_year"
        case "processor", "cpu", "处理器", "芯片":
            return "processor"
        case "memory", "ram", "运行内存", "内存":
            return "memory"
        case "storage", "rom", "存储", "容量":
            return "storage"
        case "price", "价格", "购买价格":
            return "price"
        case "notes", "备注":
            return "notes"
        case "is_in_use", "in_use", "常用", "常用设备", "在用":
            return "is_in_use"
        case "battery", "电池", "电池健康", "电池健康/状态/循环", "电量":
            return "battery"
        case "last_charged", "补电日期", "上次补电", "充电日期", "补电":
            return "last_charged"
        default:
            return key
        }
    }

    /// 解析并导入 CSV 数据为 CollectionItem 列表
    static func importing(_ data: Data, filename: String = "CSV") throws -> ImportResult {
        let text = decodeText(from: data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !text.isEmpty else { throw MuseumCSVError.invalidFile }

        var delimiter: Character = ","
        if let firstLine = text.split(separator: "\n").first {
            let commaCount = firstLine.filter { $0 == "," }.count
            let semiCount = firstLine.filter { $0 == ";" }.count
            if semiCount > commaCount { delimiter = ";" }
        }

        let rows = parse(text, delimiter: delimiter)
        guard let headerRow = rows.first else { throw MuseumCSVError.invalidFile }
        let rawHeader = headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let header = rawHeader.map { normalizeHeader($0) }
        guard header.contains("product_name") else {
            throw MuseumCSVError.missingHeaders
        }

        var result = ImportResult()
        result.totalRowsParsed = rows.count

        for row in rows.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            func value(_ key: String) -> String? {
                guard let index = header.firstIndex(of: key), index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }

            let suppliedName = value("product_name") ?? ""
            guard !suppliedName.isEmpty else { continue }
            let match = CatalogImportMatcher.shared.match(CatalogMatchQuery(
                catalogID: value("catalog_id"),
                productName: suppliedName,
                productIdentifier: value("product_identifier"),
                internalModel: value("internal_model"),
                model: value("model"),
                releaseYear: value("release_year"),
                notes: value("notes"),
                customName: value("custom_name")
            ))
            let product = match.flatMap { CatalogImportMatcher.productsByID[$0.candidate.catalogID] }
            if match != nil { result.matchedCount += 1 } else { result.unmatchedNames.append(suppliedName) }
            let suppliedID = match?.candidate.catalogID ?? value("catalog_id")
            let stableID = value("id") ?? UUID().uuidString
            let canonicalName = product?.name ?? suppliedName
            let item = CollectionItem(
                id: stableID,
                name: canonicalName,
                category: product?.category ?? value("category") ?? "Other",
                productName: canonicalName,
                customName: value("custom_name"),
                model: value("model") ?? product?.model,
                catalogID: suppliedID,
                serialNumber: value("serial_number"),
                modelVersion: value("internal_model"),
                regionVersion: value("region"),
                productIdentifier: value("product_identifier"),
                battery: value("battery"),
                lastCharged: value("last_charged"),
                screenSize: value("screen_size"),
                processor: value("processor") ?? product?.processor,
                memory: value("memory"),
                storage: value("storage"),
                graphics: value("graphics"),
                color: value("color"),
                system: value("system"),
                osVersion: value("os_version"),
                jailbreak: value("jailbreak"),
                account: value("account"),
                releaseYear: value("release_year") ?? product?.year,
                repairs: value("repairs"),
                purchaseDate: value("purchase_date"),
                purchaseSource: value("purchase_source"),
                warrantyStatus: value("warranty_status"),
                price: value("price"),
                notes: value("notes"),
                isInUse: {
                    let raw = value("is_in_use")?.lowercased()
                    return (raw == "true" || raw == "1" || raw == "yes" || raw == "是")
                }()
            )
            result.items.append(item)
        }

        if result.items.isEmpty {
            let headerStr = rawHeader.joined(separator: ", ")
            result.diagnosticMessage = String(
                format: appLocalized("File \"%@\" (%ld bytes, %ld lines parsed).\nHeaders: [%@]\nNo product data rows found below header. Please check that product names are filled under the product_name column."),
                filename, data.count, rows.count, headerStr
            )
        }
        return result
    }

    nonisolated private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func makeData(rows: [[String]]) -> Data {
        let csv = rows.map { $0.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
    }

    private static func parse(_ rawText: String, delimiter: Character = ",") -> [[String]] {
        let text = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\""); index += 1
                    } else if index + 1 == characters.count || characters[index + 1] == delimiter || characters[index + 1] == "\n" {
                        quoted = false
                    } else {
                        field.append("\"")
                    }
                } else { field.append(character) }
            } else if character == "\"", field.isEmpty {
                quoted = true
            } else if character == "\"" {
                field.append(character)
            } else if character == delimiter {
                row.append(field); field = ""
            } else if character == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field); rows.append(row)
        }
        return rows
    }
}
