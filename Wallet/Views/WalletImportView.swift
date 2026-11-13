import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Bring years of BudgetBakers Wallet history across: pick the CSV export, review
/// what was found, import. Safe to repeat with a newer export — anything already
/// imported is skipped.
struct WalletImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    enum Stage {
        case start
        case parsing
        case preview(WalletImport.Plan, duplicates: Int)
        case importing
        case done(LedgerWriter.ImportOutcome)
        case failed(String)
    }

    @State private var stage: Stage = .start
    @State private var picking = false
    @State private var adoptReference = true
    @State private var factor: Double = 1
    @State private var factorNote: String?
    @State private var storeIsEmpty = true
    @State private var doneTrigger = 0

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .start: startView
                case .parsing: ProgressView("Reading your export…").frame(maxHeight: .infinity)
                case .preview(let plan, let duplicates): preview(plan, duplicates: duplicates)
                case .importing: ProgressView("Importing…").frame(maxHeight: .infinity)
                case .done(let outcome): doneView(outcome)
                case .failed(let message): failedView(message)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import from BudgetBakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = stage {} else { Button("Cancel") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
                load(result)
            }
            .sensoryFeedback(.success, trigger: doneTrigger)
        }
        .interactiveDismissDisabled(isBusy)
    }

    private var isBusy: Bool {
        switch stage {
        case .parsing, .importing: true
        default: false
        }
    }

    // MARK: Stages

    private var startView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Brand.gradient)
                    .padding(.top, 24)
                VStack(spacing: 6) {
                    Text("Move your history to Wallet").font(.title2.bold())
                    Text("Accounts, categories, labels, transfers and foreign-currency rates all come across.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 14) {
                    step(1, String(localized: "In BudgetBakers, open Settings → Exports and export your records as CSV."))
                    step(2, String(localized: "Save the file to Files, or share it to this device."))
                    step(3, String(localized: "Choose it below. Nothing is imported until you confirm."))
                }
                .card()
                Button {
                    picking = true
                } label: {
                    Label("Choose CSV file", systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                Label("The file is read on this device only.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Brand.accent, in: .circle)
            Text(text).font(.subheadline)
        }
    }

    private func preview(_ plan: WalletImport.Plan, duplicates: Int) -> some View {
        let reference = plan.referenceCurrency
        let needsConversion = reference != baseCurrency && !(storeIsEmpty && adoptReference)
        return Form {
            Section {
                LabeledContent("Transactions", value: "\(plan.records.count)")
                LabeledContent("Expenses", value: "\(plan.expenseCount)")
                LabeledContent("Income", value: "\(plan.incomeCount)")
                LabeledContent("Transfers", value: "\(plan.transferCount)")
                if plan.labelCount > 0 { LabeledContent("Labels", value: "\(plan.labelCount)") }
                if let first = plan.firstDate, let last = plan.lastDate {
                    LabeledContent("Period", value: "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                }
            } header: {
                Text("Found")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if duplicates > 0 {
                        Text("\(duplicates) transactions were imported before and will be skipped.")
                    }
                    if plan.externalTransfers > 0 {
                        Text("\(plan.externalTransfers) transfers have no matching account in the export, so they're kept as money moving in or out of Wallet.")
                    }
                    if plan.skippedRows > 0 {
                        Text("\(plan.skippedRows) rows couldn't be read and will be left out.")
                    }
                }
            }

            Section("Accounts") {
                ForEach(plan.accounts) { account in
                    HStack(spacing: 12) {
                        CategoryTile(symbol: account.kind.symbol, tint: account.kind.defaultTint.color, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name)
                            Text("\(account.kind.label) · \(account.currency)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(account.recordCount)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            if reference != baseCurrency {
                Section {
                    if storeIsEmpty {
                        Toggle("Use \(reference) as main currency", isOn: $adoptReference)
                    }
                    if needsConversion {
                        LabeledContent("1 \(reference) =") {
                            HStack(spacing: 4) {
                                TextField("Rate", value: $factor, format: .number.precision(.fractionLength(0...6)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text(baseCurrency).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Currency")
                } footer: {
                    Text(needsConversion
                         ? (factorNote ?? String(localized: "BudgetBakers reported amounts in \(reference). This rate converts them into \(baseCurrency) for totals; original amounts are kept."))
                         : String(localized: "Totals and reports will be shown in \(reference), as in BudgetBakers."))
                }
                .task(id: needsConversion) { if needsConversion { await suggestFactor(from: reference) } }
            }

            Section {
                Button {
                    run(plan)
                } label: {
                    Text("Import \(max(0, plan.records.count - duplicates)) transactions")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(plan.records.count - duplicates <= 0 || (needsConversion && !(factor.isFinite && factor > 0)))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    private func doneView(_ outcome: LedgerWriter.ImportOutcome) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.income)
                .symbolEffect(.bounce, value: doneTrigger)
            Text("Import complete").font(.title2.bold())
            VStack(spacing: 4) {
                Text("\(outcome.added) transactions added")
                if outcome.accountsCreated > 0 { Text("\(outcome.accountsCreated) accounts created") }
                if outcome.skipped > 0 { Text("\(outcome.skipped) already present, skipped") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("Imported balances start from zero. If an account's balance doesn't match your bank, open the account and correct its current balance.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .padding(20)
        }
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't import", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Choose another file") { picking = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }

    // MARK: Work

    private func load(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        stage = .parsing
        Task {
            do {
                let data = try readSecurely(url)
                let plan = try await Task.detached(priority: .userInitiated) { try WalletImport.plan(from: data) }.value
                let duplicates = existingDuplicates(plan)
                storeIsEmpty = isStoreEmpty()
                adoptReference = storeIsEmpty
                withAnimation(.snappy) { stage = .preview(plan, duplicates: duplicates) }
            } catch {
                withAnimation { stage = .failed(error.localizedDescription) }
            }
        }
    }

    /// Reads the picked file with a size check first — an import is untrusted input.
    private func readSecurely(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > CSV.maxBytes {
            throw CSV.Failure.tooLarge
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func existingDuplicates(_ plan: WalletImport.Plan) -> Int {
        var descriptor = FetchDescriptor<Record>(predicate: #Predicate { $0.importKey != nil })
        descriptor.propertiesToFetch = [\.importKey]
        let keys = Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.importKey))
        return plan.records.filter { keys.contains($0.key) }.count
    }

    private func isStoreEmpty() -> Bool {
        let records = (try? context.fetchCount(FetchDescriptor<Record>())) ?? 0
        let items = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        return records == 0 && items == 0 && accounts == 0
    }

    private func suggestFactor(from reference: String) async {
        switch await ExchangeRateService.shared.quote(from: reference, to: baseCurrency) {
        case .success(let quote):
            factor = quote.rate
            factorNote = String(localized: "Suggested from today's rate. Original amounts are kept; this only affects totals.", comment: "Import footer")
        case .failure:
            factorNote = String(localized: "A rate could not be retrieved. Please enter one manually.", comment: "Note under an exchange rate field")
        }
    }

    private func run(_ plan: WalletImport.Plan) {
        let reference = plan.referenceCurrency
        let adopting = storeIsEmpty && adoptReference && reference != baseCurrency
        if adopting { baseCurrency = reference }
        let conversion = adopting || reference == baseCurrency ? 1 : factor
        let base = baseCurrency
        stage = .importing
        guard let container = DataStore.shared.container else { return }
        Task {
            do {
                let writer = LedgerWriter(modelContainer: container)
                let outcome = try await writer.importWallet(plan, factor: conversion, baseCurrency: base)
                withAnimation(.snappy) { stage = .done(outcome) }
                doneTrigger += 1
            } catch {
                withAnimation { stage = .failed(error.localizedDescription) }
            }
        }
    }
}
