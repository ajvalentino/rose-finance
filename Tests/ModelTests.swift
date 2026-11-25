import Foundation

@main struct ModelTests {
    static func main() throws {
        var checks = 0
        func check(_ okay: Bool, _ label: String) {
            guard okay else { fatalError("FAIL: " + label) }; checks += 1
        }
        func rejects(_ label: String, _ action: () throws -> Void) {
            do { try action(); fatalError("FAIL: accepted " + label) } catch { checks += 1 }
        }
        var l = Ledger.examples(now: Ledger.date("2026-11-24")!)
        try l.validate()
        check(l.total("2026-11", income: true) == 300000, "sample income")
        check(l.total("2026-11", bucket: .needs) == 101240, "needs arithmetic")
        check(l.total("2026-11", bucket: .wants) == 2800, "wants arithmetic")
        check(l.total("2026-11", bucket: .savings) == 10000, "savings separate")
        check(l.total("2026") == l.total("2026-11"), "year rollup")
        let accounts = l.accounts.map(\.cents)
        let category = l.categories.first { $0.name == "Groceries" }!
        let oldGroup = category.groupID, newGroup = l.groups.first { $0.bucket == .wants }!.id
        l.categories[l.categories.firstIndex { $0.id == category.id }!].name = "Food shopping"
        check(l.entries.first { $0.categoryID == category.id }?.groupID == oldGroup, "rename keeps references")
        l.moveCategory(category.id, to: newGroup, moveHistory: false)
        check(l.total("2026-11", group: oldGroup) == 6240, "move preserves history")
        l.moveCategory(category.id, to: newGroup, moveHistory: true)
        check(l.total("2026-11", group: oldGroup) == 0 && l.total("2026-11", bucket: .wants) == 9040, "explicit historical move")
        check(l.accounts.map(\.cents) == accounts, "transactions and classification never touch balances")
        check(try Ledger.amount("25.50") == 2550, "exact cents")
        check(try Ledger.amount("-12.34", allowNegative: true) == -1234, "negative manual balance")
        for bad in ["nan", "1e5", "12.345", "-1", "$25", "1,000", "", "9999999999"] { rejects("invalid amount \(bad)") { _ = try Ledger.amount(bad) } }
        check(Ledger.date("2026-02-30") == nil, "impossible date")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = LedgerDisk(url: folder.appendingPathComponent("Finance.json"))
        try disk.save(l)
        let restored = try disk.load()
        check(restored.total("2026") == l.total("2026"), "persistence roundtrip")
        var bad = l; bad.entries[0].cents = -1
        rejects("negative restored transaction") { try disk.save(bad) }
        check(try disk.load().entries[0].cents == l.entries[0].cents, "invalid save leaves current file untouched")
        bad = l; bad.entries[1].groupID = UUID()
        rejects("missing group") { try bad.validate() }
        bad = l; bad.plans.append(bad.plans[0])
        rejects("duplicate plan") { try bad.validate() }
        bad = l; bad.version = 99
        rejects("unknown schema") { try bad.validate() }
        bad = l; bad.entries[0].date = "2026-13-01"
        rejects("bad date") { try bad.validate() }
        let backup = folder.appendingPathComponent("export.json")
        try JSONEncoder().encode(l).write(to: backup)
        var cleared = l; cleared.clearExamples(); try disk.save(cleared)
        check(cleared.accounts.isEmpty && cleared.entries.isEmpty && cleared.plans.isEmpty && !cleared.sample, "example reset")
        check(cleared.groups.count == l.groups.count && cleared.categories.count == l.categories.count, "reset retains structure")
        _ = try disk.restore(backup)
        check(try disk.load().entries.count == l.entries.count, "restore")
        let backups = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        check(backups.count == 2, "pre-save and pre-restore recovery copies")
        try Data("not a backup".utf8).write(to: backup)
        rejects("corrupt backup") { _ = try disk.restore(backup) }
        check(try disk.load().entries.count == l.entries.count, "failed restore keeps data")
        print("Passed \(checks) model and persistence checks.")
    }
}
