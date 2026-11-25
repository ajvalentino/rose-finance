import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Disambiguate the property wrapper from newer SDK macros named State.
typealias ViewState<T> = SwiftUI.State<T>

@MainActor final class Store: ObservableObject {
    @Published var ledger = Ledger()
    @Published var error: String?
    @Published var message = ""
    @Published var ready = false
    let disk: LedgerDisk
    init() {
        let override = ProcessInfo.processInfo.environment["COMPANION_DATA_DIR"]
        let base = override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rose Finance")
        disk = LedgerDisk(url: base.appendingPathComponent("Finance.json"))
        do {
            if FileManager.default.fileExists(atPath: disk.url.path) { ledger = try disk.load() }
            else { ledger = Ledger.examples(); try disk.save(ledger) }
            ready = true
        } catch { self.error = "Your data could not be opened. It has not been replaced. \(error.localizedDescription) Use Restore backup to recover a saved file." }
    }
    func change(_ action: (inout Ledger) throws -> Void) {
        guard ready else { error = "Restore a valid backup before making changes."; return }
        do { var copy = ledger; try action(&copy); try disk.save(copy); ledger = copy; message = "Saved on this Mac" }
        catch { self.error = error.localizedDescription }
    }
    func export() {
        guard ready else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Rose-Finance-\(Ledger.day()).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL != disk.url.standardizedFileURL else { error = "Choose a different location from the app's working data file."; return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(ledger).write(to: url, options: .atomic); message = "Backup saved. Keep this file somewhere safe." }
        catch { self.error = error.localizedDescription }
    }
    func restore() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert(); alert.messageText = "Replace this app's data with your backup?"
        alert.informativeText = "The current file will be kept in the automatic Backups folder first. Your backup will be checked before anything is replaced."
        alert.addButton(withTitle: "Restore backup"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { ledger = try disk.restore(url); ready = true; message = "Backup restored" }
        catch { self.error = "Restore failed. Your current data was kept. \(error.localizedDescription)" }
    }
}

let rose = Color(red: 0.60, green: 0.22, blue: 0.36)
let blush = Color(red: 0.98, green: 0.95, blue: 0.95)
let ink = Color(red: 0.22, green: 0.15, blue: 0.19)

enum Page: String, CaseIterable, Identifiable {
    case home = "Home", accounts = "Accounts", budget = "Budget", transactions = "Transactions", year = "Year", help = "Help"
    var id: String { rawValue }
    var icon: String { switch self { case .home: return "house"; case .accounts: return "wallet.pass"; case .budget: return "list.bullet.rectangle"; case .transactions: return "arrow.left.arrow.right"; case .year: return "calendar"; case .help: return "questionmark.circle" } }
    var subtitle: String { switch self {
    case .home: return "A little clarity for your everyday money."
    case .accounts: return "Your latest balances, updated by you."
    case .budget: return "A simple plan, with room for real life."
    case .transactions: return "Income, purchases, and money put aside."
    case .year: return "See the bigger picture, one month at a time."
    case .help: return "Start here. Come back whenever you need a hand."
    } }
}
struct Editor: Identifiable {
    enum Kind { case account, group, category, entry, plan }
    let id = UUID()
    var kind: Kind
    var record: UUID? = nil
    var month: String = Ledger.month()
}
@main struct RoseFinanceApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        Window("Rose Finance", id: "main") { Content().environmentObject(store).tint(rose).preferredColorScheme(.light) }
            .defaultSize(width: 1080, height: 760)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct Content: View {
    @EnvironmentObject var store: Store
    @ViewState private var page: Page = .home
    @ViewState private var month: String = Ledger.month()
    @ViewState private var year: String = String(Ledger.month().prefix(4))
    @ViewState private var monthDate: Date = Date()
    @ViewState private var query: String = ""
    @ViewState private var categoryFilter: UUID?
    @ViewState private var kindFilter: String = "All"
    @ViewState private var structure: Bool = false
    @ViewState private var editor: Editor?
    @ViewState private var confirmation: String?
    @ViewState private var pending: (() -> Void)?
    var l: Ledger { store.ledger }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("rose").font(.system(size: 37, weight: .semibold, design: .serif)).foregroundStyle(rose).padding(.bottom, 2)
                Text("YOUR MONEY, GENTLY").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.bottom, 26)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.icon).font(.system(size: 14, weight: page == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(page == item ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).foregroundStyle(page == item ? rose : ink)
                }
                Spacer()
                Image(systemName: "lock.shield").foregroundStyle(rose)
                Text("Just on this Mac").font(.callout.weight(.medium))
                Text("No bank connection.\nNo account to sign into.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 205).background(Color(red: 0.96, green: 0.88, blue: 0.90))
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.rawValue).font(.system(size: 32, weight: .medium, design: .serif))
                        Text(page.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if [.home, .budget, .transactions].contains(page) {
                        VStack(alignment: .trailing, spacing: 5) {
                            DatePicker("Month", selection: $monthDate, displayedComponents: .date).labelsHidden().datePickerStyle(.stepperField)
                                .onChange(of: monthDate) { value in month = Ledger.month(value) }
                            Text(monthTitle(month)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if l.sample && store.ready {
                    HStack { Image(systemName: "sparkles"); Text("You're exploring fictional example data."); Spacer(); Button("Start my own") { ask("Clear the example accounts, transactions, and budget amounts? Your category structure will stay.") { store.change { $0.clearExamples() } } } }
                        .font(.callout).padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                if !store.ready {
                    card { Text("Your data needs attention").font(.title2); Text("The original file is untouched. Open Help to restore a backup."); Button("Open Help") { page = .help } }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .home: home
                        case .accounts: accounts
                        case .budget: budget
                        case .transactions: transactions
                        case .year: annual
                        case .help: help
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
                }
                HStack { Text(store.message).font(.caption).foregroundStyle(.secondary); Spacer(); if page != .help { Button("Need a hand?") { page = .help }.buttonStyle(.plain).font(.caption).foregroundStyle(rose) } }
            }.padding(28).frame(maxWidth: .infinity).background(blush)
        }.foregroundStyle(ink).frame(minWidth: 880, minHeight: 640)
            .sheet(item: $editor) { EditSheet(editor: $0).environmentObject(store).tint(rose) }
            .alert("Couldn't complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            .alert("Please confirm", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Continue", role: .destructive) { pending?(); pending = nil }
            } message: { Text(confirmation ?? "") }
    }
    func ask(_ text: String, action: @escaping () -> Void) { pending = action; confirmation = text }
    func monthTitle(_ month: String) -> String {
        guard let d = Ledger.date(month + "-01") else { return month }
        return d.formatted(.dateTime.month(.wide).year())
    }
    func card<Inner: View>(@ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(22).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    func metric(_ label: String, _ value: Int, _ caption: String) -> some View {
        card { Text(label).font(.callout).foregroundStyle(.secondary); Text(Ledger.money(value)).font(.system(size: 25, weight: .medium, design: .rounded)); Text(caption).font(.caption).foregroundStyle(.secondary) }
    }
    var home: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(monthTitle(month)).font(.title3.weight(.medium)); Spacer(); Button("Add transaction", systemImage: "plus") { editor = Editor(kind: .entry, month: month) }.buttonStyle(.borderedProminent).disabled(!store.ready) }
            HStack(alignment: .top, spacing: 12) {
                metric("Income recorded", l.total(month, income: true), "Money you've logged as received")
                metric("Spent this month", l.total(month, bucket: .needs) + l.total(month, bucket: .wants), "Needs and wants, excluding savings")
                metric("Budget remaining", l.planned(month) - l.total(month), "Plan minus spending and savings contributions")
            }
            card {
                Text("Your plan at a glance").font(.title3.weight(.medium))
                ForEach(Bucket.allCases) { bucket in
                    let plan = l.plans.filter { $0.month == month }.filter { p in l.groups.first { $0.id == p.groupID }?.bucket == bucket }.reduce(0) { $0 + $1.cents }
                    let actual = l.total(month, bucket: bucket)
                    HStack { Text(bucket.rawValue); Spacer(); Text("\(Ledger.money(actual)) of \(Ledger.money(plan))").foregroundStyle(.secondary) }
                    ProgressView(value: min(Double(actual), Double(max(plan, 1))), total: Double(max(plan, 1))).tint(rose)
                }
                Button("Open my budget") { page = .budget }
            }
            card { Label("Balances and budgets tell different stories", systemImage: "info.circle").font(.headline); Text("Transactions update your budget and reports. Account balances only change when you edit them. Budget remaining is not your bank balance.").foregroundStyle(.secondary) }
            if l.entries.isEmpty { card { Text("A fresh start").font(.headline); Text("Add your accounts, make a monthly plan, then record your first transaction. Help walks you through each step.") } }
        }
    }
    var accounts: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Update these when you check your bank.").foregroundStyle(.secondary); Spacer(); Button("Add account", systemImage: "plus") { editor = Editor(kind: .account) }.disabled(!store.ready) }
            if l.accounts.isEmpty { card { Text("Add your first account").font(.headline); Text("Give it any name you like, such as Everyday checking, and enter its current balance.") } }
            ForEach(l.accounts) { a in
                card { HStack {
                    VStack(alignment: .leading, spacing: 6) { Text(a.name).font(.headline); Text("Updated \(a.updated.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text(Ledger.money(a.cents)).font(.title2); Button("Edit") { editor = Editor(kind: .account, record: a.id) }
                    Button("Remove", role: .destructive) { ask("Remove \(a.name)? Transactions will remain. An automatic backup is kept.") { store.change { $0.accounts.removeAll { $0.id == a.id } } } }
                } }
            }
            Text("Account totals do not calculate or reconcile from transactions. No bank credentials are stored.").font(.callout).foregroundStyle(.secondary)
        }
    }
    var visibleGroups: [Group] { l.groups.filter { !$0.archived || l.planned(month, group: $0.id) != 0 || l.total(month, group: $0.id) != 0 } }
    var budget: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Copy previous month's plan") {
                    let previous = Ledger.month(Calendar.current.date(byAdding: .month, value: -1, to: Ledger.date(month + "-01")!)!)
                    guard l.plans.contains(where: { $0.month == previous }) else { store.error = "There isn't a plan for \(monthTitle(previous)) yet."; return }
                    ask("Replace \(monthTitle(month))'s plan with \(monthTitle(previous))'s amounts? Transactions will stay the same.") { store.change { ledger in
                        let copy = ledger.plans.filter { $0.month == previous }
                        ledger.plans.removeAll { $0.month == month }
                        for p in copy { ledger.setPlan(month: month, group: p.groupID, cents: p.cents) }
                    } }
                }.disabled(!store.ready)
                Spacer(); Toggle("Edit groups & categories", isOn: $structure).toggleStyle(.switch)
            }
            if structure { structureView }
            ForEach(Bucket.allCases) { bucket in
                card {
                    Text(bucket.rawValue).font(.title3.weight(.medium))
                    ForEach(visibleGroups.filter { $0.bucket == bucket }) { group in
                        let planned = l.planned(month, group: group.id), actual = l.total(month, group: group.id)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(group.name).font(.headline); Text(actual > planned ? "Over your plan by \(Ledger.money(actual - planned))" : "\(Ledger.money(planned - actual)) remaining").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); VStack(alignment: .trailing) { Text("\(Ledger.money(actual)) recorded"); Text("\(Ledger.money(planned)) planned").font(.caption).foregroundStyle(.secondary) }
                            Button("Edit plan") { editor = Editor(kind: .plan, record: group.id, month: month) }.disabled(!store.ready)
                        }.padding(.vertical, 5)
                    }
                }
            }
            Text("Budget broad groups. Pick a detailed category when recording a transaction. Savings contributions count toward your plan, but not your spending total.").font(.callout).foregroundStyle(.secondary)
        }
    }
    var structureView: some View {
        card {
            HStack { Text("Make this yours").font(.headline); Spacer(); Button("Add group") { editor = Editor(kind: .group) }; Button("Add category") { editor = Editor(kind: .category) } }
            Text("Rename freely. Archive items to hide them from new entries while keeping history. Changing a group's type affects future entries; past entries keep their original Needs, Wants, or Savings classification.").font(.callout).foregroundStyle(.secondary)
            ForEach(l.groups) { g in
                HStack { Text(g.name + (g.archived ? " (archived)" : "")).font(.headline); Text(g.bucket.rawValue).foregroundStyle(.secondary); Spacer(); Button("Edit group") { editor = Editor(kind: .group, record: g.id) } }
                ForEach(l.categories.filter { $0.groupID == g.id }) { c in
                    HStack { Text("    " + c.name + (c.archived ? " (archived)" : "")); Spacer(); Button("Edit category") { editor = Editor(kind: .category, record: c.id) } }.font(.callout)
                }
                Divider()
            }
        }.disabled(!store.ready)
    }
    var filteredEntries: [Entry] {
        l.entries.filter { e in
            e.date.hasPrefix(month) && (categoryFilter == nil || e.categoryID == categoryFilter) &&
            (kindFilter == "All" || (kindFilter == "Income" ? e.income : kindFilter == "Savings" ? e.bucket == .savings : !e.income && e.bucket != .savings)) &&
            (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (e.name + " " + e.note + " " + (l.categories.first { $0.id == e.categoryID }?.name ?? "Income")).localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.sorted { $0.date > $1.date }
    }
    var transactions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search descriptions, categories, or notes", text: $query).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $kindFilter) { ForEach(["All", "Income", "Spending", "Savings"], id: \.self) { Text($0).tag($0) } }.frame(width: 150)
                Button("Add transaction", systemImage: "plus") { editor = Editor(kind: .entry, month: month) }.buttonStyle(.borderedProminent).disabled(!store.ready)
            }
            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(nil as UUID?)
                ForEach(l.categories.sorted { $0.name < $1.name }) { Text($0.name).tag(Optional($0.id)) }
            }.frame(maxWidth: 320)
            if filteredEntries.isEmpty { card { Text("No transactions to show").font(.headline); Text("Try another month or filter, or add a transaction. Descriptions can be casual; your category determines where it goes in the budget.") } }
            ForEach(filteredEntries) { e in
                card { HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(e.name).font(.headline)
                        Text("\(e.date) · \(e.income ? "Income" : l.categories.first { $0.id == e.categoryID }?.name ?? "Category") · \(e.bucket?.rawValue ?? "Received")").font(.caption).foregroundStyle(.secondary)
                        if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(); Text(Ledger.money(e.cents)).font(.title3)
                    Button("Edit") { editor = Editor(kind: .entry, record: e.id, month: month) }
                    Button("Delete", role: .destructive) { ask("Delete this transaction? An automatic backup is kept.") { store.change { $0.entries.removeAll { $0.id == e.id } } } }
                } }
            }
        }
    }
    var years: [String] { Array(Set(l.entries.map { String($0.date.prefix(4)) } + l.plans.map { String($0.month.prefix(4)) } + [String(Ledger.month().prefix(4)), year])).sorted().reversed() }
    var annual: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text($0).tag($0) } }.frame(width: 180)
            HStack(spacing: 12) { metric("Income recorded", l.total(year, income: true), year); metric("Spending", l.total(year, bucket: .needs) + l.total(year, bucket: .wants), "Needs and wants"); metric("Put into savings", l.total(year, bucket: .savings), "Contributions, not account balances") }
            card {
                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 14) {
                    GridRow { Text("Month"); Text("Income"); Text("Spending"); Text("Savings"); Text("After spending & savings") }.font(.caption.weight(.semibold))
                    ForEach(1...12, id: \.self) { n in
                        let m = String(format: "%@-%02d", year, n), income = l.total(m, income: true), spent = l.total(m, bucket: .needs) + l.total(m, bucket: .wants), saved = l.total(m, bucket: .savings)
                        GridRow { Text(Ledger.date(m + "-01")!.formatted(.dateTime.month(.abbreviated))); Text(Ledger.money(income)); Text(Ledger.money(spent)); Text(Ledger.money(saved)); Text(Ledger.money(income - spent - saved)) }
                    }
                }.font(.callout)
            }
            Text("Only recorded transactions are included. A blank month shows zero; it doesn't mean nothing happened. These totals are not bank balances.").font(.callout).foregroundStyle(.secondary)
        }
    }
    var help: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                Text("Your first few minutes").font(.title3.weight(.medium))
                Text("1. Explore the examples, then choose Start my own. This clears example accounts, transactions, and amounts while retaining your category structure.\n\n2. In Accounts, add checking or savings accounts and their current balances. You can rename them anytime.\n\n3. In Budget, choose a month and use Edit plan beside each broad group. Edit groups & categories lets you customize the structure.\n\n4. In Transactions, record money received, purchases, or savings contributions. Choose a date and category, and enter a positive amount such as 25.50.\n\n5. Check Home for the month and Year for the bigger picture.")
            }
            card {
                Text("Everyday questions").font(.title3.weight(.medium))
                helpItem("How do categories work?", "Needs, Wants, and Savings contain broad budget groups. Detailed categories fill those groups automatically. For example, Groceries fills the Food budget. You only choose the detailed category when adding a transaction.")
                helpItem("Why didn't my account balance change?", "Balances are manual snapshots. Recording a transaction updates reports and your budget only. Check your bank and edit the account balance when you want a fresh snapshot. Its update date shows when you last did that.")
                helpItem("How do I record savings?", "Choose a category in a Savings group when putting money aside. This uses part of your monthly plan without counting as spending. Moving between your own accounts isn't income; edit their balances separately. This version tracks positive contributions, not savings withdrawals or automatic transfers.")
                helpItem("How do I fix a mistake?", "Use Edit beside a transaction or account. Delete removes a transaction after confirmation. For a returned purchase, reduce or remove the original purchase; refund transactions aren't supported in this first version.")
                helpItem("What happens when I rename or move a category?", "Renames update labels everywhere. Moving a category affects future transactions unless you select Move existing transactions too. Past transactions keep their old group and type by default. Archive groups or categories you no longer use; history stays available.")
                helpItem("How do I start a new month?", "Use the date control in the upper right to choose any day in that month. Budget can copy the previous month's plan. Transactions never copy. You don't need to close or reopen months.")
            }
            card {
                Text("Keep a copy. Take it with you.").font(.title3.weight(.medium))
                Text("Your data lives on this Mac, separately from the app. Before every change, the previous file is automatically kept in Backups. Updates to the app keep your data. Backups contain personal financial information, so store them somewhere private. Automatic backups stay on this Mac; export one to another location regularly.")
                HStack {
                    Button("Back up my data…") { store.export() }.disabled(!store.ready)
                    Button("Restore backup…") { store.restore() }
                    Button("Show data & automatic backups") { NSWorkspace.shared.open(store.disk.directory) }
                }
                Text("To move computers: save a backup, copy the app and backup to the other Mac, then choose Restore backup there. Restoring checks the file first and keeps a recovery copy of your current data. There is no syncing between devices.")
                Text(store.disk.directory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    func helpItem(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary) }.padding(.vertical, 4)
    }
}
