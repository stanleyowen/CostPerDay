import SwiftUI
import SwiftData

struct GadgetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Gadget.purchaseDate, order: .reverse) private var gadgets: [Gadget]

    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var sort: SortOption = .costPerDay
    @State private var showRetired = false
    @State private var newGadget: Gadget?
    @State private var deletedNotice: String?

    private var costMode: CostMode { CostMode(rawValue: costModeRaw) ?? .actual }

    enum SortOption: String, CaseIterable, Identifiable {
        case costPerDay = "Cost / day"
        case price = "Price"
        case newest = "Newest"
        case name = "Name"
        var id: String { rawValue }
    }

    private var visible: [Gadget] {
        let pool = gadgets.filter { showRetired || !$0.isRetired }
        switch sort {
        case .costPerDay: return pool.sorted { $0.costPerDay(mode: costMode) > $1.costPerDay(mode: costMode) }
        case .price: return pool.sorted { $0.netCost > $1.netCost }
        case .newest: return pool.sorted { $0.purchaseDate > $1.purchaseDate }
        case .name: return pool.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private var activeGadgets: [Gadget] { gadgets.filter { !$0.isRetired } }

    var body: some View {
        NavigationStack {
            Group {
                if gadgets.isEmpty {
                    EmptyStateView { addGadget() }
                } else {
                    list
                }
            }
            .navigationTitle("Gadgets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOption.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Toggle("Show retired", isOn: $showRetired)
                        #if DEBUG
                        Divider()
                        Button("Load sample data") { SampleData.insert(into: context) }
                        #endif
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add gadget", systemImage: "plus") { addGadget() }
                }
            }
            .sheet(item: $newGadget) { gadget in
                GadgetEditView(gadget: gadget, isNew: true)
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = deletedNotice {
                    UndoBar(message: notice) { undoDelete() } dismiss: { deletedNotice = nil }
                }
            }
        }
    }

    private var list: some View {
        List {
            if !activeGadgets.isEmpty {
                Section {
                    BurnRateHeader(gadgets: activeGadgets, mode: costMode, currency: baseCurrency)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Cost basis", selection: $costModeRaw) {
                    ForEach(CostMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            } footer: {
                Text(costMode.explanation)
            }

            Section {
                ForEach(visible) { gadget in
                    NavigationLink {
                        GadgetDetailView(gadget: gadget)
                    } label: {
                        GadgetRow(gadget: gadget, mode: costMode, currency: baseCurrency)
                    }
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func addGadget() {
        let gadget = Gadget(currencyCode: baseCurrency)
        context.insert(gadget)
        newGadget = gadget
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
        guard !doomed.isEmpty else { return }
        let name = doomed.count == 1 ? (doomed[0].name.isEmpty ? "Gadget" : doomed[0].name) : "\(doomed.count) gadgets"

        context.undoManager?.beginUndoGrouping()
        for gadget in doomed { context.delete(gadget) }
        context.undoManager?.endUndoGrouping()

        withAnimation { deletedNotice = "Deleted \(name)" }
    }

    private func undoDelete() {
        context.undoManager?.undo()
        withAnimation { deletedNotice = nil }
    }
}

/// Delete is the one destructive action in the app, so it always comes with a way back.
private struct UndoBar: View {
    let message: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            // Auto-dismiss so the bar never sits there permanently.
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}

/// The number the whole app exists to make you feel: what your gadgets cost you every day.
private struct BurnRateHeader: View {
    let gadgets: [Gadget]
    let mode: CostMode
    let currency: String

    private var perDay: Double {
        gadgets.reduce(0) { $0 + $1.costPerDay(mode: mode) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Your electronics cost you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.perDay(perDay, code: currency))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("per day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Money.string(perDay * 30.4375, code: currency)) a month · \(Money.string(perDay * 365.25, code: currency)) a year")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No gadgets yet", systemImage: "square.stack.3d.up.slash")
        } description: {
            Text("Add the electronics you own to see what they really cost you each day.")
        } actions: {
            Button("Add your first gadget", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
    }
}
