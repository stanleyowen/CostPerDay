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
                         ? "All totals are shown in this currency. Items purchased abroad retain the exchange rate recorded at the time of purchase."
                         : String(localized: "\(foreignCount) items purchased in another currency use the exchange rate recorded at the time of purchase.", comment: "Settings footer. The placeholder is a count of items."))
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
                         ? String(localized: "Create your own categories for anything the built-in list does not cover.", comment: "Settings footer")
                         : String(localized: "The figure on the right indicates how many items use each category. Deleting a category preserves those items; they are simply shown as uncategorised.", comment: "Settings footer"))
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
                    Text("Backups are stored as plain JSON. Restoring adds any missing entries and skips items already present; it never overwrites your library.")
                }

                Section {
                    Button {
                        openAppSettings()
                    } label: {
                        HStack {
                            Label("Preferred language", systemImage: "globe")
                            Spacer()
                            Text(currentLanguageName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.tertiary)
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Opens Settings, where the language for this application can be changed independently of the system language.")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/stanleyowen/CostPerDay")!) {
                        LabeledContent {
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } label: {
                            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
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

    /// The language the app is currently displaying, named in that language —
    /// "Deutsch" rather than "German" — which is how iOS itself lists them.
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)
            ?? locale.localizedString(forLanguageCode: code)
            ?? code
    }

    /// Opens this app's page in Settings, where iOS exposes the per-app Language
    /// control once the bundle ships more than one localisation.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
        save(failureTitle: String(localized: "Could not change currency", comment: "Alert title"))
    }

    // MARK: Backup

    private func export() {
        do {
            exportURL = try Backup.writeTemporary(
                Backup.makeFile(gadgets: items, baseCurrency: baseCurrency, customCategories: customCategories)
            )
        } catch {
            alert = AlertState(title: String(localized: "Export failed", comment: "Alert title"), message: error.localizedDescription)
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
            var message = String(localized: "Added \(outcome.added) items.", comment: "Restore result. The placeholder is a count.")
            if outcome.categoriesAdded > 0 {
                message += " " + String(localized: "Restored \(outcome.categoriesAdded) custom categories.", comment: "Restore result. The placeholder is a count.")
            }
            if outcome.skipped > 0 {
                message += " " + String(localized: "Skipped \(outcome.skipped) entries already present.", comment: "Restore result. The placeholder is a count.")
            }
            alert = AlertState(title: String(localized: "Restore complete", comment: "Alert title"), message: message)
        } catch {
            alert = AlertState(title: String(localized: "Restore failed", comment: "Alert title"), message: error.localizedDescription)
        }
    }

    private func usageCount(of category: CustomCategory) -> Int {
        items.filter { $0.categoryKey == category.key }.count
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets where customCategories.indices.contains(index) {
            context.delete(customCategories[index])
        }
        save(failureTitle: String(localized: "Could not delete category", comment: "Alert title"))
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
                        Label("Retrieving today's rate…", systemImage: "arrow.clockwise")
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
                    Text("Your \(gadgetCount) items are currently priced against \(from). This rate re-expresses them in \(to). The prices originally entered remain unchanged; only the conversion is adjusted.")
                }
            }
            .navigationTitle(Text("Switch to \(to)"))
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
                        ? String(localized: "Suggested from a cached rate. Please confirm it is still accurate.", comment: "Note under a suggested exchange rate")
                        : String(localized: "Suggested from today's rate. Adjust it if you prefer a different value.", comment: "Note under a suggested exchange rate")
                case .failure:
                    fetchNote = String(localized: "A rate could not be retrieved. Please enter one manually.", comment: "Note under an exchange rate field")
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
