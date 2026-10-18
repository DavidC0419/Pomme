import Foundation

/// One encyclopedia product the CSV importer can match against (built from the read-only catalog).
nonisolated struct CatalogMatchCandidate: Sendable {
    let catalogID: String
    let name: String
    let category: String
    let year: String
    let models: [String]        // A-numbers, uppercased
    let identifiers: [String]   // e.g. "macbookpro18,3", lowercased
    let aliases: [String]       // extra names (e.g. devices.json names), raw
}

/// The CSV values used for matching.
nonisolated struct CatalogMatchQuery: Sendable {
    var catalogID: String?
    var productName: String?
    var productIdentifier: String?
    var internalModel: String?
    var model: String?
    var releaseYear: String?
    var notes: String?
    var customName: String?
}

nonisolated enum CatalogMatchMethod: String, Sendable {
    case catalogID, productIdentifier, internalModel, model, name, fuzzyName
}

nonisolated struct CatalogMatchResult: Sendable {
    let candidate: CatalogMatchCandidate
    let method: CatalogMatchMethod
}

/// Matches a CSV row to the encyclopedia, most precise key first:
/// catalog_id → product_identifier → internal_model → model (A-number) → normalized name → fuzzy name.
/// Several candidates for one key are disambiguated by a score over the other columns.
nonisolated struct CSVCatalogMatcher: Sendable {
    let candidates: [CatalogMatchCandidate]
    private let byID: [String: Int]
    private let byIdentifier: [String: [Int]]
    private let byModel: [String: [Int]]
    private let byName: [String: [Int]]
    private let nameTokens: [Set<String>]

    init(candidates: [CatalogMatchCandidate], extraIDAliases: [String: String] = [:]) {
        self.candidates = candidates
        var byID: [String: Int] = [:], byIdentifier: [String: [Int]] = [:], byModel: [String: [Int]] = [:], byName: [String: [Int]] = [:]
        for (index, c) in candidates.enumerated() {
            if byID[c.catalogID.lowercased()] == nil { byID[c.catalogID.lowercased()] = index }
            for value in c.identifiers { byIdentifier[value, default: []].append(index) }
            for value in c.models { byModel[value, default: []].append(index) }
            for value in [c.name] + c.aliases {
                let key = Self.normalizedName(value)
                if !key.isEmpty, !(byName[key]?.contains(index) ?? false) { byName[key, default: []].append(index) }
            }
        }
        for (alias, target) in extraIDAliases {
            if let index = byID[target.lowercased()], byID[alias.lowercased()] == nil { byID[alias.lowercased()] = index }
        }
        self.byID = byID; self.byIdentifier = byIdentifier; self.byModel = byModel; self.byName = byName
        self.nameTokens = candidates.map { Self.tokens($0.name) }
    }

    func match(_ query: CatalogMatchQuery) -> CatalogMatchResult? {
        if let id = query.catalogID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
           let index = byID[id.lowercased()] {
            return CatalogMatchResult(candidate: candidates[index], method: .catalogID)
        }
        let identifiers = Self.splitIdentifiers(query.productIdentifier)
        let identifierHits = Set(identifiers.flatMap { byIdentifier[$0] ?? [] })
        if !identifierHits.isEmpty { return best(identifierHits, query, .productIdentifier) }

        // The catalog has no internal (J/K/N…) model numbers; an internal_model that looks like
        // an identifier or A-number is still tried against those indexes.
        let internalIDs = Self.splitIdentifiers(query.internalModel).flatMap { byIdentifier[$0] ?? [] }
        if !internalIDs.isEmpty { return best(Set(internalIDs), query, .internalModel) }

        let models = Self.aNumbers(query.model) + Self.aNumbers(query.internalModel)
        let modelHits = Set(models.flatMap { byModel[$0] ?? [] })
        if !modelHits.isEmpty { return best(modelHits, query, .model) }

        let name = Self.normalizedName(query.productName ?? "")
        guard !name.isEmpty else { return nil }
        if let hits = byName[name], !hits.isEmpty { return best(Set(hits), query, .name) }

        // Fuzzy: token overlap with every catalog name.
        let queryTokens = Self.tokens(query.productName ?? "")
        guard !queryTokens.isEmpty else { return nil }
        var bestIndex: Int?, bestScore = 0.0
        for (index, tokens) in nameTokens.enumerated() where !tokens.isEmpty {
            let inter = Double(queryTokens.intersection(tokens).count)
            guard inter > 0 else { continue }
            let jaccard = inter / Double(queryTokens.union(tokens).count)
            let coverage = inter / Double(queryTokens.count)
            var score = jaccard * 0.6 + coverage * 0.4
            if let year = query.releaseYear, !year.isEmpty, candidates[index].year == year { score += 0.05 }
            if score > bestScore { bestScore = score; bestIndex = index }
        }
        guard let bestIndex, bestScore >= 0.6 else { return nil }
        return CatalogMatchResult(candidate: candidates[bestIndex], method: .fuzzyName)
    }

    private func best(_ hits: Set<Int>, _ query: CatalogMatchQuery, _ method: CatalogMatchMethod) -> CatalogMatchResult {
        let queryName = Self.normalizedName(query.productName ?? "")
        let queryTokens = Self.tokens(query.productName ?? "")
        let identifiers = Set(Self.splitIdentifiers(query.productIdentifier) + Self.splitIdentifiers(query.internalModel))
        let models = Set(Self.aNumbers(query.model))

        // 专项检测用户是否标注了 U2 特别版硬件（在品名、内部型号、备注、自定义昵称等任何字段提及）
        let isQueryU2 = (query.productName?.localizedCaseInsensitiveContains("u2") == true) ||
                        (query.internalModel?.localizedCaseInsensitiveContains("u2") == true) ||
                        (query.notes?.localizedCaseInsensitiveContains("u2") == true) ||
                        (query.customName?.localizedCaseInsensitiveContains("u2") == true) ||
                        (query.internalModel?.localizedCaseInsensitiveContains("MA664") == true) ||
                        (query.internalModel?.localizedCaseInsensitiveContains("MA452") == true)

        // 专项检测用户是否标注了 Balmain 特别版硬件（在品名、内部型号、备注、自定义昵称等任何字段提及）
        let isQueryBalmain = (query.productName?.localizedCaseInsensitiveContains("balmain") == true) ||
                             (query.internalModel?.localizedCaseInsensitiveContains("balmain") == true) ||
                             (query.notes?.localizedCaseInsensitiveContains("balmain") == true) ||
                             (query.customName?.localizedCaseInsensitiveContains("balmain") == true)

        // 专项检测用户是否标注了 USB-C 款或 2代（针对 AirPods Max 等）
        let isQueryUSBC = (query.productName?.localizedCaseInsensitiveContains("usb-c") == true) ||
                          (query.productName?.localizedCaseInsensitiveContains("usbc") == true) ||
                          (query.productName?.localizedCaseInsensitiveContains("max 2") == true) ||
                          (query.productName?.localizedCaseInsensitiveContains("max2") == true) ||
                          (query.internalModel?.localizedCaseInsensitiveContains("usb-c") == true) ||
                          (query.internalModel?.localizedCaseInsensitiveContains("a3184") == true) ||
                          (query.model?.localizedCaseInsensitiveContains("a3184") == true) ||
                          (query.model?.localizedCaseInsensitiveContains("a3454") == true) ||
                          (query.notes?.localizedCaseInsensitiveContains("usb-c") == true) ||
                          (query.customName?.localizedCaseInsensitiveContains("usb-c") == true)

        func score(_ index: Int) -> Double {
            let c = candidates[index]
            var s = 0.0
            if !identifiers.isEmpty, !identifiers.isDisjoint(with: c.identifiers) { s += 6 }
            if !models.isEmpty, !models.isDisjoint(with: c.models) { s += 2 }
            if !queryName.isEmpty, ([c.name] + c.aliases).contains(where: { Self.normalizedName($0) == queryName }) { s += 3 }
            if !queryTokens.isEmpty {
                let t = nameTokens[index]
                s += Double(queryTokens.intersection(t).count) / Double(max(1, queryTokens.union(t).count)) * 2
            }
            if let year = query.releaseYear, !year.isEmpty, c.year == year { s += 1 }

            // U2 Edition 精准定向加减权：用户标注 U2 时坚决不认作普通版；用户未标注时避免误认作 U2
            let isCandidateU2 = c.name.localizedCaseInsensitiveContains("u2") || c.catalogID.localizedCaseInsensitiveContains("u2")
            if isQueryU2 {
                if isCandidateU2 { s += 10 } else { s -= 10 }
            } else {
                if isCandidateU2 { s -= 5 }
            }

            // Balmain Edition 精准定向加减权：用户未明确标注 Balmain 时避免误认作 Balmain
            let isCandidateBalmain = c.name.localizedCaseInsensitiveContains("balmain") || c.catalogID.localizedCaseInsensitiveContains("balmain")
            if isQueryBalmain {
                if isCandidateBalmain { s += 10 } else { s -= 10 }
            } else {
                if isCandidateBalmain { s -= 5 }
            }

            // AirPods Max USB-C / 2代 定向加减权：用户未标注 USB-C 时优先匹配 1代闪电口版
            let isCandidateUSBC = c.name.localizedCaseInsensitiveContains("usb-c") || c.catalogID.localizedCaseInsensitiveContains("usbc")
            if isQueryUSBC {
                if isCandidateUSBC { s += 10 } else { s -= 5 }
            } else {
                if isCandidateUSBC { s -= 6 }
            }

            // Prefer catalog entries the app already uses as legacy IDs (Mac-1, iPod-9 …).
            if !c.catalogID.contains(",") && c.catalogID.contains("-") { s += 0.1 }
            return s
        }
        let index = hits.max { a, b in
            let sa = score(a), sb = score(b)
            return sa != sb ? sa < sb : candidates[a].catalogID > candidates[b].catalogID
        }!
        return CatalogMatchResult(candidate: candidates[index], method: method)
    }

    // MARK: Normalization

    static func normalizedName(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init)).lowercased()
    }

    static func tokens(_ value: String) -> Set<String> {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let stop: Set<String> = ["the", "with", "and", "for", "apple", "generation", "gen", "edition"]
        return Set(parts.filter { !stop.contains($0) }.map { token in
            // "1st"/"2nd"/"3rd"/"4th" → "1"/"2"…, so "iPod nano 2" meets "iPod nano (2nd generation)".
            if token.range(of: #"^\d+(st|nd|rd|th)$"#, options: .regularExpression) != nil { return String(token.prefix { $0.isNumber }) }
            return token
        })
    }

    /// Identifiers look like "MacBookPro18,3", or Apple part/order numbers like "MA664", "MA664J", "MA452".
    static func splitIdentifiers(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        var results: [String] = []
        let pattern = #"[A-Za-z][A-Za-z ]*\d+,\d+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(value.startIndex..., in: value)
            results.append(contentsOf: regex.matches(in: value, range: range).compactMap { Range($0.range, in: value) }
                .map { value[$0].replacingOccurrences(of: " ", with: "").lowercased() })
        }
        // 提取 Apple 零件/订购编号 (如 MA664, MA664J, MA452, M9787)
        let partPattern = #"(?i)\bM[A-Z0-9]{3,5}(?:[A-Z]{1,2}/[A-Z])?\b"#
        if let partRegex = try? NSRegularExpression(pattern: partPattern) {
            let range = NSRange(value.startIndex..., in: value)
            results.append(contentsOf: partRegex.matches(in: value, range: range).compactMap { Range($0.range, in: value) }
                .map { String(value[$0]).lowercased() })
        }
        return results
    }

    static func aNumbers(_ value: String?) -> [String] {
        guard let value, !value.isEmpty, let regex = try? NSRegularExpression(pattern: #"(?i)\bA\s?(\d{4})\b"#) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { Range($0.range(at: 1), in: value) }.map { "A" + value[$0] }
    }
}
