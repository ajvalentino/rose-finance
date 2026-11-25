import Foundation

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case needs = "Needs", wants = "Wants", savings = "Savings"
    var id: String { rawValue }
}
struct Account: Codable, Identifiable {
    var id = UUID()
    var name: String
    var cents: Int
    var updated: Date = Date()
}
struct Group: Codable, Identifiable {
    var id = UUID()
    var name: String
    var bucket: Bucket
    var archived = false
}
struct Category: Codable, Identifiable {
    var id = UUID()
    var name: String
    var groupID: UUID
    var archived = false
}
struct Entry: Codable, Identifiable {
    var id = UUID()
    var date: String
    var name: String
    var cents: Int
    var categoryID: UUID?
    // Historical classification is deliberate, independent of current category mapping.
    var groupID: UUID?
    var bucket: Bucket?
    var income: Bool
    var note: String = ""
}
struct Plan: Codable, Identifiable {
    var id = UUID()
    var month: String
    var groupID: UUID
    var cents: Int
}
struct Ledger: Codable {
    var version = 1
    var sample = true
    var accounts: [Account] = []
    var groups: [Group] = []
    var categories: [Category] = []
    var entries: [Entry] = []
    var plans: [Plan] = []

    static func month(_ date: Date = Date()) -> String { day(date).prefix(7).description }
    static func day(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ text: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let d = f.date(from: text), day(d) == text else { return nil }; return d
    }
    static func money(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD"))
    }
    static func amount(_ text: String, allowNegative: Bool = false) throws -> Int {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = allowNegative ? #"^-?\d{1,9}(\.\d{1,2})?$"# : #"^\d{1,9}(\.\d{1,2})?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw AppError.message("Enter an amount like 25 or 25.50, without a dollar sign or commas.")
        }
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }
    func total(_ month: String, income: Bool = false, bucket: Bucket? = nil, group: UUID? = nil) -> Int {
        entries.filter { $0.date.hasPrefix(month) && $0.income == income &&
            (bucket == nil || $0.bucket == bucket) && (group == nil || $0.groupID == group)
        }.reduce(0) { $0 + $1.cents }
    }
    func planned(_ month: String, group: UUID? = nil) -> Int {
        plans.filter { $0.month == month && (group == nil || $0.groupID == group) }.reduce(0) { $0 + $1.cents }
    }
    mutating func setPlan(month: String, group: UUID, cents: Int) {
        plans.removeAll { $0.month == month && $0.groupID == group }
        plans.append(Plan(month: month, groupID: group, cents: cents))
    }
    mutating func moveCategory(_ id: UUID, to group: UUID, moveHistory: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }), let target = groups.first(where: { $0.id == group }) else { return }
        categories[index].groupID = group
        if moveHistory {
            for index in entries.indices where entries[index].categoryID == id {
                entries[index].groupID = group; entries[index].bucket = target.bucket
            }
        }
    }
    mutating func clearExamples() {
        accounts.removeAll(); entries.removeAll(); plans.removeAll(); sample = false
    }
    func validate() throws {
        func require(_ okay: Bool, _ message: String) throws { if !okay { throw AppError.message(message) } }
        try require(version == 1, "This backup uses an unsupported file version.")
        try require(accounts.count <= 1000 && groups.count <= 1000 && categories.count <= 10000 && entries.count <= 100000 && plans.count <= 100000, "This file contains too many records.")
        func unique<T: Identifiable>(_ items: [T]) -> Bool where T.ID: Hashable { Set(items.map(\.id)).count == items.count }
        try require(unique(accounts) && unique(groups) && unique(categories) && unique(entries) && unique(plans), "This file has duplicate record identifiers.")
        func name(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= 120 }
        func bounded(_ n: Int) -> Bool { n >= -99999999999 && n <= 99999999999 }
        let groupIDs = Set(groups.map(\.id)), categoryIDs = Set(categories.map(\.id))
        for a in accounts { try require(name(a.name) && bounded(a.cents) && a.updated.timeIntervalSince1970.isFinite, "An account has an invalid name, balance, or update date.") }
        for g in groups { try require(name(g.name), "A budget group needs a name of at most 120 characters.") }
        for c in categories { try require(name(c.name) && groupIDs.contains(c.groupID), "A category has an invalid name or missing budget group.") }
        for e in entries {
            try require(Self.date(e.date) != nil && name(e.name) && e.cents > 0 && bounded(e.cents) && e.note.count <= 2000, "A transaction has an invalid date, description, amount, or note.")
            if e.income { try require(e.categoryID == nil && e.groupID == nil && e.bucket == nil, "Income cannot be assigned to an expense category.") }
            else { try require(e.categoryID.map(categoryIDs.contains) == true && e.groupID.map(groupIDs.contains) == true && e.bucket != nil, "A transaction references a missing category or group.") }
        }
        var keys = Set<String>()
        for p in plans {
            try require(Self.date(p.month + "-01") != nil && p.month.count == 7 && groupIDs.contains(p.groupID) && p.cents >= 0 && bounded(p.cents), "A budget has an invalid month, group, or amount.")
            try require(keys.insert(p.month + p.groupID.uuidString).inserted, "This file has duplicate monthly budgets.")
        }
    }
    static func examples(now: Date = Date()) -> Ledger {
        var l = Ledger()
        l.accounts = [Account(name: "Everyday checking", cents: 185000), Account(name: "Savings", cents: 320000)]
        let specs: [(String, Bucket, [String], Int)] = [
            ("Home & bills", .needs, ["Rent", "Utilities", "Phone"], 110000),
            ("Food", .needs, ["Groceries", "Work lunches"], 35000),
            ("Getting around", .needs, ["Gas", "Parking", "Maintenance"], 15000),
            ("Health & care", .needs, ["Healthcare", "Personal care"], 10000),
            ("Fun & extras", .wants, ["Restaurants", "Entertainment", "Shopping"], 20000),
            ("Savings contributions", .savings, ["Emergency fund", "Vacation"], 25000)
        ]
        let month = month(now)
        for (name, bucket, names, cents) in specs {
            let g = Group(name: name, bucket: bucket); l.groups.append(g)
            l.categories += names.map { Category(name: $0, groupID: g.id) }
            l.setPlan(month: month, group: g.id, cents: cents)
        }
        l.entries.append(Entry(date: month + "-01", name: "Example paycheck", cents: 300000, income: true))
        for (name, category, cents) in [("Example rent", "Rent", 95000), ("Weekly groceries", "Groceries", 6240), ("Dinner with friends", "Restaurants", 2800), ("Put aside for emergencies", "Emergency fund", 10000)] {
            let c = l.categories.first { $0.name == category }!, g = l.groups.first { $0.id == c.groupID }!
            l.entries.append(Entry(date: month + "-01", name: name, cents: cents, categoryID: c.id, groupID: g.id, bucket: g.bucket, income: false))
        }
        return l
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

// Each mutation persists a validated copy before publishing it to the interface.
final class LedgerDisk {
    let url: URL
    var directory: URL { url.deletingLastPathComponent() }
    init(url: URL) { self.url = url }
    func load() throws -> Ledger {
        let l = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url)); try l.validate(); return l
    }
    func backup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let folder = directory.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Finance-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
    func save(_ ledger: Ledger) throws {
        try ledger.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ledger)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try backup()
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func restore(_ file: URL) throws -> Ledger {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 50_000_000 else { throw AppError.message("Choose a backup smaller than 50 MB.") }
        let l = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file)); try l.validate()
        try save(l); return l
    }
}
