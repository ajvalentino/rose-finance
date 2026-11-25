import SwiftUI

struct EditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(scheme: colorScheme) }
    let editor: Editor
    @ViewState private var name: String = ""
    @ViewState private var amount: String = ""
    @ViewState private var note: String = ""
    @ViewState private var date: Date = Date()
    @ViewState private var bucket: Bucket = Bucket.needs
    @ViewState private var groupID: UUID?
    @ViewState private var categoryID: UUID?
    @ViewState private var archived: Bool = false
    @ViewState private var income: Bool = false
    @ViewState private var moveHistory: Bool = false
    @ViewState private var error: String?
    @ViewState private var paycheck: String = ""
    @ViewState private var frequency: PayFrequency = .biweekly
    @ViewState private var estimatorOpen: Bool = false
    @ViewState private var estimatedAmount: String?
    var l: Ledger { store.ledger }
    var title: String {
        switch editor.kind {
        case .account: return editor.record == nil ? "Add account" : "Edit account"
        case .entry: return editor.record == nil ? "Add transaction" : "Edit transaction"
        case .group: return editor.record == nil ? "Add budget group" : "Edit budget group"
        case .category: return editor.record == nil ? "Add category" : "Edit category"
        case .plan: return "Edit monthly plan"
        case .income: return "Edit planned income"
        }
    }
    var availableCategories: [Category] {
        l.categories.filter { c in
            (!c.archived && l.groups.contains { $0.id == c.groupID && !$0.archived }) || c.id == l.entries.first(where: { $0.id == editor.record })?.categoryID
        }.sorted { a, b in
            let ga = l.groups.first { $0.id == a.groupID }?.name ?? "", gb = l.groups.first { $0.id == b.groupID }?.name ?? ""
            return ga == gb ? a.name < b.name : ga < gb
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.system(size: 26, weight: .medium, design: .serif))
            Form {
                switch editor.kind {
                case .account:
                    TextField("Account name", text: $name)
                    TextField("Current balance ($)", text: $amount)
                    Text("This is a manual balance. Saving marks it updated today. Negative balances are allowed.").font(.caption).foregroundStyle(.secondary)
                case .group:
                    TextField("Group name", text: $name)
                    Picker("Type for future transactions", selection: $bucket) { ForEach(Bucket.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Archive this group", isOn: $archived)
                    Text("Archived groups and their categories are hidden from new transactions. Existing entries keep their original type, even if you change this group's type.").font(.caption).foregroundStyle(.secondary)
                case .category:
                    TextField("Category name", text: $name)
                    Picker("Budget group", selection: $groupID) {
                        Text("Choose a group").tag(nil as UUID?)
                        ForEach(l.groups.filter { !$0.archived || $0.id == groupID }) { Text("\($0.name) · \($0.bucket.rawValue)").tag(Optional($0.id)) }
                    }
                    Toggle("Archive this category", isOn: $archived)
                    if editor.record != nil {
                        Toggle("Move existing transactions too", isOn: $moveHistory)
                        Text("Use this only when correcting their classification. It updates historical group and type totals; monthly budget amounts stay unchanged.").font(.caption).foregroundStyle(.secondary)
                    }
                case .entry:
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("This is income", isOn: $income)
                    TextField("Description", text: $name)
                    TextField("Amount ($)", text: $amount)
                    if !income {
                        Picker("Category", selection: $categoryID) {
                            Text("Choose a category").tag(nil as UUID?)
                            ForEach(availableCategories) { c in
                                Text("\(l.groups.first { $0.id == c.groupID }?.name ?? "") → \(c.name)").tag(Optional(c.id))
                            }
                        }
                        if let c = l.categories.first(where: { $0.id == categoryID }), let g = l.groups.first(where: { $0.id == c.groupID }) {
                            Text("New entries fill \(g.name) under \(g.bucket.rawValue). Editing an existing entry keeps its historical classification unless you choose a different category.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                    Text("Enter a positive amount, without commas. Transactions don't change account balances.").font(.caption).foregroundStyle(.secondary)
                case .income:
                    Text("Planned income for " + editor.month).font(.headline)
                    TextField("Planned take-home income ($)", text: $amount)
                    if estimatedAmount == amount {
                        Text("Estimated monthly average — actual income may differ.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Enter the total you plan to receive after taxes and deductions. This is a plan, not income received. It does not create transactions or change balances.").font(.caption).foregroundStyle(.secondary)
                    Button(estimatorOpen ? "Hide paycheck estimator" : "Calculate an estimate for me") { estimatorOpen.toggle() }
                    if estimatorOpen {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Take-home amount per paycheck ($)", text: $paycheck)
                            Picker("How often are you paid?", selection: $frequency) {
                                ForEach(PayFrequency.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Text("Estimate only: " + frequency.explanation + ". Annual average, rounded to cents. Actual months may have fewer or more paychecks; this does not predict payday dates or calculate taxes.").font(.caption).foregroundStyle(.secondary)
                            Button("Use estimate") { fillEstimate() }
                            Text("Fills the planned-income field once. You can edit it afterward. Save applies it to this month; Cancel discards changes.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 10)
                    }
                case .plan:
                    Text(l.groups.first { $0.id == editor.record }?.name ?? "Budget group").font(.headline)
                    Text(editor.month)
                    TextField("Planned amount ($)", text: $amount)
                    Text("This is the total for the broad group. Its detailed categories share this amount. Enter 0 to leave it unbudgeted.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout).accessibilityLabel("Error: " + error) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(26).foregroundStyle(palette.text).tint(palette.accent).background(palette.background).frame(width: 590, height: editor.kind == .income ? 670 : nil).onAppear(perform: load)
    }
    func dollars(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
    func load() {
        switch editor.kind {
        case .account:
            if let a = l.accounts.first(where: { $0.id == editor.record }) { name = a.name; amount = dollars(a.cents) }
        case .group:
            if let g = l.groups.first(where: { $0.id == editor.record }) { name = g.name; bucket = g.bucket; archived = g.archived }
        case .category:
            if let c = l.categories.first(where: { $0.id == editor.record }) { name = c.name; groupID = c.groupID; archived = c.archived }
        case .entry:
            date = Ledger.date(editor.month + "-01") ?? Date()
            if editor.month == Ledger.month() { date = Date() }
            if let e = l.entries.first(where: { $0.id == editor.record }) { name = e.name; amount = dollars(e.cents); note = e.note; date = Ledger.date(e.date) ?? Date(); income = e.income; categoryID = e.categoryID }
        case .plan: amount = dollars(l.planned(editor.month, group: editor.record))
        case .income:
            if let plan = l.expectedIncome?[editor.month] {
                amount = dollars(plan.cents)
                if plan.estimated { estimatedAmount = amount }
            }
        }
    }
    func fillEstimate() {
        do {
            let cents = try frequency.estimate(cents: Ledger.amount(paycheck))
            amount = dollars(cents); estimatedAmount = amount; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        do {
            var copy = l
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if editor.kind != .plan && editor.kind != .income && (cleanName.isEmpty || cleanName.count > 120) { throw AppError.message("Enter a name or description of 1–120 characters.") }
            func normalized(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            switch editor.kind {
            case .account:
                let cents = try Ledger.amount(amount, allowNegative: true)
                let a = Account(id: editor.record ?? UUID(), name: cleanName, cents: cents)
                copy.accounts.removeAll { $0.id == a.id }; copy.accounts.append(a)
            case .group:
                guard !copy.groups.contains(where: { $0.id != editor.record && normalized($0.name) == normalized(cleanName) }) else { throw AppError.message("There's already a group with that name.") }
                let g = Group(id: editor.record ?? UUID(), name: cleanName, bucket: bucket, archived: archived)
                if let i = copy.groups.firstIndex(where: { $0.id == g.id }) { copy.groups[i] = g } else { copy.groups.append(g) }
            case .category:
                guard let groupID else { throw AppError.message("Choose a budget group.") }
                guard !copy.categories.contains(where: { $0.id != editor.record && $0.groupID == groupID && normalized($0.name) == normalized(cleanName) }) else { throw AppError.message("There's already a category with that name in this group.") }
                let c = Category(id: editor.record ?? UUID(), name: cleanName, groupID: groupID, archived: archived)
                if let i = copy.categories.firstIndex(where: { $0.id == c.id }) {
                    copy.moveCategory(c.id, to: groupID, moveHistory: moveHistory); copy.categories[i] = c
                } else { copy.categories.append(c) }
            case .entry:
                let cents = try Ledger.amount(amount)
                guard cents > 0 else { throw AppError.message("Enter an amount greater than zero.") }
                var e = Entry(id: editor.record ?? UUID(), date: Ledger.day(date), name: cleanName, cents: cents, income: income, note: note)
                if !income {
                    guard let c = copy.categories.first(where: { $0.id == categoryID }), let g = copy.groups.first(where: { $0.id == c.groupID }) else { throw AppError.message("Choose a category. You can create one in Budget → Edit groups & categories.") }
                    e.categoryID = c.id; e.groupID = g.id; e.bucket = g.bucket
                    if let old = copy.entries.first(where: { $0.id == editor.record }), !old.income && old.categoryID == c.id { e.groupID = old.groupID; e.bucket = old.bucket }
                }
                if let i = copy.entries.firstIndex(where: { $0.id == e.id }) { copy.entries[i] = e } else { copy.entries.append(e) }
            case .income:
                copy.setExpectedIncome(month: editor.month, cents: try Ledger.amount(amount), estimated: estimatedAmount == amount)
            case .plan:
                guard let group = editor.record else { throw AppError.message("Choose a budget group.") }
                copy.setPlan(month: editor.month, group: group, cents: try Ledger.amount(amount))
            }
            try copy.validate()
            try store.disk.save(copy)
            store.ledger = copy; store.message = "Saved on this Mac"; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
