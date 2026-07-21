import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var gadgets: [Gadget]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var rebaseTarget: String?
    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var alert: AlertState?

    private var foreignCount: Int {
        gadgets.filter { $0.currencyCode != baseCurrency }.count
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
                         ? "Every total in the app is shown in this currency. Gadgets bought abroad keep the exchange rate you entered at purchase."
                         : "\(foreignCount) gadget\(foreignCount == 1 ? "" : "s") bought in another currency use the rate you locked in at purchase.")
                }

                Section {
                    Button {
                        export()
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(gadgets.isEmpty)

                    Button {
                        isImporting = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Backups are plain JSON. Restoring adds anything missing and skips gadgets you already have — it never overwrites your library.")
                }

                Section {
                    LabeledContent("Gadgets", value: "\(gadgets.count)")
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
            .sheet(item: $rebaseTarget) { target in
                RebaseSheet(from: baseCurrency, to: target, gadgetCount: gadgets.count) { factor in
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
        if gadgets.isEmpty {
            baseCurrency = code
        } else {
            rebaseTarget = code
        }
    }

    private func applyRebase(to code: String, factor: Double) {
        Gadget.rebase(gadgets, by: factor)
        baseCurrency = code
        rebaseTarget = nil
        save(failureTitle: "Couldn't change currency")
    }

    // MARK: Backup

    private func export() {
        do {
            exportURL = try Backup.writeTemporary(Backup.makeFile(gadgets: gadgets, baseCurrency: baseCurrency))
        } catch {
            alert = AlertState(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let file = try Backup.read(from: url)
            let outcome = Backup.restore(file, into: context, existing: gadgets)
            try context.save()
            alert = AlertState(
                title: "Restored",
                message: "Added \(outcome.added) gadget\(outcome.added == 1 ? "" : "s")."
                    + (outcome.skipped > 0 ? " Skipped \(outcome.skipped) you already had." : "")
            )
        } catch {
            alert = AlertState(title: "Restore failed", message: error.localizedDescription)
        }
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
