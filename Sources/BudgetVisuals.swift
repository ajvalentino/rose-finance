import SwiftUI

private let groupColors: [Color] = [Color(red: 0.75, green: 0.35, blue: 0.48), Color(red: 0.88, green: 0.57, blue: 0.64), Color(red: 0.58, green: 0.40, blue: 0.59), Color(red: 0.70, green: 0.57, blue: 0.68), Color(red: 0.70, green: 0.49, blue: 0.40), Color(red: 0.53, green: 0.60, blue: 0.53)]

struct GroupPie: View {
    let ledger: Ledger
    let month: String
    let planned: Bool
    @Environment(\.colorScheme) private var scheme
    var rows: [(Group, Int, Color)] {
        ledger.groups.enumerated().compactMap { index, group in
            let amount = planned ? ledger.planned(month, group: group.id) : ledger.total(month, group: group.id)
            return amount > 0 ? (group, amount, groupColors[index % groupColors.count]) : nil
        }
    }
    var body: some View {
        let data = rows
        let total = data.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 16) {
            Text(planned ? "Planned allocations by group" : "Actual amounts by group").font(.title3.weight(.medium))
            Text(planned ? "Planned Needs, Wants, and Savings. Income is not part of this pie." : "Recorded Needs, Wants, and Savings contributions. Savings is included here, separately from spending.").font(.callout).foregroundStyle(.secondary)
            if total == 0 {
                Label(planned ? "Set group amounts to see your planned allocation." : "Record transactions to see your actual breakdown.", systemImage: "chart.pie").foregroundStyle(.secondary).padding(.vertical, 24)
            } else {
                HStack(alignment: .center, spacing: 28) {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2 - 3
                        var angle = -90.0
                        for row in data {
                            let end = angle + Double(row.1) / Double(total) * 360
                            var path = Path(); path.move(to: center)
                            path.addArc(center: center, radius: radius, startAngle: .degrees(angle), endAngle: .degrees(end), clockwise: false)
                            path.closeSubpath()
                            context.fill(path, with: .color(row.2))
                            context.stroke(path, with: .color(Palette(scheme: scheme).surface), lineWidth: 2)
                            angle = end
                        }
                    }.frame(width: 170, height: 170).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(data.indices, id: \.self) { i in
                            HStack {
                                Circle().fill(data[i].2).frame(width: 9, height: 9)
                                Text(data[i].0.name)
                                Spacer()
                                Text(Ledger.money(data[i].1)).monospacedDigit()
                                Text((Double(data[i].1) / Double(total)).formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.secondary).frame(width: 45, alignment: .trailing)
                            }.font(.callout)
                        }
                        Divider()
                        HStack { Text(planned ? "Total planned" : "Total recorded").fontWeight(.medium); Spacer(); Text(Ledger.money(total)).fontWeight(.medium) }
                    }
                }
            }
        }.padding(22).background(Palette(scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ActualBudget: View {
    let ledger: Ledger
    let month: String
    let seeTransactions: (UUID, UUID?) -> Void
    @Environment(\.colorScheme) private var scheme
    var palette: Palette { Palette(scheme: scheme) }
    var groups: [Group] {
        ledger.groups.filter { !$0.archived || ledger.planned(month, group: $0.id) != 0 || ledger.total(month, group: $0.id) != 0 }
    }
    func actual(_ group: UUID, category: UUID? = nil) -> Int {
        ledger.entries.filter { !$0.income && $0.date.hasPrefix(month) && $0.groupID == group && (category == nil || $0.categoryID == category) }.reduce(0) { $0 + $1.cents }
    }
    func categories(_ group: UUID) -> [Category] {
        ledger.categories.filter { category in
            (category.groupID == group && !category.archived) || ledger.entries.contains { !$0.income && $0.date.hasPrefix(month) && $0.groupID == group && $0.categoryID == category.id }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Actual vs planned").font(.title3.weight(.medium))
                ForEach(Bucket.allCases) { bucket in
                    let planned = ledger.plans.filter { p in p.month == month && ledger.groups.first { $0.id == p.groupID }?.bucket == bucket }.reduce(0) { $0 + $1.cents }
                    let amount = ledger.total(month, bucket: bucket)
                    HStack { Text(bucket.rawValue); Spacer(); Text("\(Ledger.money(amount)) actual / \(Ledger.money(planned)) planned").font(.callout).foregroundStyle(.secondary) }
                    ProgressView(value: min(Double(amount), Double(max(planned, 1))), total: Double(max(planned, 1))).tint(palette.accent)
                    if amount > planned { Text("Over plan by " + Ledger.money(amount - planned)).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Actual comes from transactions, not account balances. Savings contributions are shown alongside spending.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            GroupPie(ledger: ledger, month: month, planned: false)
            Text("Groups & transaction categories").font(.title3.weight(.medium))
            Text("Subcategories share their group's planned amount; they do not have separate budgets. Past transactions keep their historical group when a category moves.").font(.callout).foregroundStyle(.secondary)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.name).font(.headline)
                            Text("\(Ledger.money(actual(group.id))) actual / \(Ledger.money(ledger.planned(month, group: group.id))) planned").font(.callout)
                            let left = ledger.planned(month, group: group.id) - actual(group.id)
                            Text(left < 0 ? "Over plan by \(Ledger.money(-left))" : "\(Ledger.money(left)) remaining in group plan").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("See transactions") { seeTransactions(group.id, nil) }.accessibilityLabel("See transactions for " + group.name)
                    }
                    ForEach(categories(group.id)) { category in
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name + (category.groupID != group.id ? " (historical group)" : "")).font(.callout.weight(.medium))
                                Text("\(Ledger.money(actual(group.id, category: category.id))) actual · shares \(Ledger.money(ledger.planned(month, group: group.id))) group plan").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("See transactions") { seeTransactions(group.id, category.id) }.font(.caption).accessibilityLabel("See transactions for \(category.name) in \(group.name)")
                        }.padding(.leading, 12)
                    }
                }.padding(22).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }.foregroundStyle(palette.text)
    }
}
