import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Item]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var rebaseTarget: String?
    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var alert: AlertState?

    @State private var editingCategory: CustomCategory?

    private var foreignCount: Int {
        items.filter { $0.currencyCode != baseCurrency }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Base currency", selection: Binding(
                        get: { baseCurrency },
                        set: { requestRebase(to: $0) }
                    )) {
                        ForEach(Currency.all, id: \.self) { code in
                            Text(Currency.label(code)).tag(code)
                        }
                    }
                } header: {
                    Text("Currency")
                } footer: {
                    Text(foreignCount == 0
                         ? "Every total in the app is shown in this currency. Things bought abroad keep the exchange rate you entered at purchase."
                         : "\(foreignCount) item\(foreignCount == 1 ? "" : "s") bought in another currency use the rate you locked in at purchase.")
                }

                Section {
                    ForEach(customCategories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.symbolName)
                                    .foregroundStyle(category.tint.color)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.name.isEmpty ? "Untitled" : category.name)
                                        .foregroundStyle(.primary)
                                    Text("\(category.sector.label) · \(Duration.fromMonths(category.defaultLifetimeMonths))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(usageCount(of: category))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        // Without this, List gives every Button row's text the accent
                        // tint by default — it reads as disabled/washed-out, not selectable.
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCategories)

                    Button {
                        editingCategory = CustomCategory()
                    } label: {
                        Label("New category", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Custom categories")
                } footer: {
                    Text(customCategories.isEmpty
                         ? "Add your own categories for anything the built-in list doesn't cover."
                         : "The number on the right is how many items use each one. Deleting a category leaves those items intact — they just show as uncategorised.")
                }

                Section {
                    Button {
                        export()
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(items.isEmpty)

                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Backups are plain JSON. Restoring adds anything missing and skips items you already have — it never overwrites your library.")
                }

                Section {
                    LabeledContent("Items", value: "\(items.count)")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $exportURL) { url in
                ShareSheet(url: url)
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert(item: $alert) { state in
                Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("OK")))
            }
            .sheet(item: $editingCategory) { category in
                CustomCategoryEditView(
                    category: category,
                    isNew: !customCategories.contains(where: { $0.uuid == category.uuid })
                )
            }
            .sheet(item: $rebaseTarget) { target in
                RebaseSheet(from: baseCurrency, to: target, gadgetCount: items.count) { factor in
                    applyRebase(to: target, factor: factor)
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Base currency

    private func requestRebase(to code: String) {
        guard code != baseCurrency else { return }
        // With nothing stored yet there are no rates to convert, so just switch.
        if items.isEmpty {
            baseCurrency = code
        } else {
            rebaseTarget = code
        }
    }

    private func applyRebase(to code: String, factor: Double) {
        Item.rebase(items, by: factor)
        baseCurrency = code
        rebaseTarget = nil
        save(failureTitle: "Couldn't change currency")
    }

    // MARK: Backup

    private func export() {
        do {
            exportURL = try Backup.writeTemporary(
                Backup.makeFile(gadgets: items, baseCurrency: baseCurrency, customCategories: customCategories)
            )
        } catch {
            alert = AlertState(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let file = try Backup.read(from: url)
            let outcome = Backup.restore(
                file, into: context, existing: items, existingCategories: customCategories
            )
            try context.save()
            var message = "Added \(outcome.added) item\(outcome.added == 1 ? "" : "s")."
            if outcome.categoriesAdded > 0 {
                message += " Restored \(outcome.categoriesAdded) custom categor\(outcome.categoriesAdded == 1 ? "y" : "ies")."
            }
            if outcome.skipped > 0 {
                message += " Skipped \(outcome.skipped) you already had."
            }
            alert = AlertState(title: "Restored", message: message)
        } catch {
            alert = AlertState(title: "Restore failed", message: error.localizedDescription)
        }
    }

    private func usageCount(of category: CustomCategory) -> Int {
        items.filter { $0.categoryKey == category.key }.count
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets where customCategories.indices.contains(index) {
            context.delete(customCategories[index])
        }
        save(failureTitle: "Couldn't delete category")
    }

    private func save(failureTitle: String) {
        do {
            try context.save()
        } catch {
            alert = AlertState(title: failureTitle, message: error.localizedDescription)
        }
    }
}

/// Switching base currency has to re-express every locked-in rate, and only the user
/// knows today's rate between the old base and the new one.
private struct RebaseSheet: View {
    let from: String
    let to: String
    let gadgetCount: Int
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var factor: Double = 1
    @State private var isFetching = false
    @State private var fetchNote: String?

    private var isValid: Bool { factor.isFinite && factor > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("1 \(from) =") {
                        HStack(spacing: 4) {
                            TextField("Rate", value: $factor, format: .number.precision(.fractionLength(0...6)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(to).foregroundStyle(.secondary)
                        }
                    }
                    if isFetching {
                        Label("Fetching today's rate…", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let fetchNote {
                        Text(fetchNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Conversion rate")
                } footer: {
                    Text("Your \(gadgetCount) gadget\(gadgetCount == 1 ? "" : "s") were priced against \(from). This rate re-expresses them in \(to). Prices you originally entered stay untouched — only the conversion changes.")
                }
            }
            .navigationTitle("Switch to \(to)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Convert") { onConfirm(factor) }
                        .disabled(!isValid)
                }
            }
            .task {
                isFetching = true
                switch await ExchangeRateService.shared.quote(from: from, to: to) {
                case .success(let quote):
                    factor = quote.rate
                    fetchNote = quote.servedFromCache
                        ? "Suggested from a cached rate — check it's still right."
                        : "Suggested from today's rate — edit it if you'd rather use your own."
                case .failure:
                    fetchNote = "Couldn't fetch a rate — enter it yourself."
                }
                isFetching = false
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
