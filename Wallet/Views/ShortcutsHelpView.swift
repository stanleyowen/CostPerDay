import SwiftUI
import AppIntents

/// What Wallet exposes to Shortcuts and Siri, and the one automation worth setting up:
/// logging every Apple Pay payment automatically.
struct ShortcutsHelpView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "square.2.layers.3d.top.filled")
                        .font(.largeTitle)
                        .foregroundStyle(.pink.gradient)
                    Text("Log without opening the app")
                        .font(.title3.bold())
                    Text("Wallet's actions work in the Shortcuts app, with Siri, from Spotlight and the Action button.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Actions") {
                action("Add Transaction", symbol: "plus.circle.fill", tint: Brand.accent,
                       detail: String(localized: "Amount, type, account, category, note, merchant, date and labels. Leave the category out and Wallet picks the one you usually use."))
                action("New Transaction", symbol: "square.and.pencil", tint: .blue,
                       detail: String(localized: "Opens Wallet with the entry keypad ready."))
                action("Get Balance", symbol: "banknote.fill", tint: .green,
                       detail: String(localized: "One account, or your total across all of them."))
                action("Get Spending", symbol: "chart.pie.fill", tint: .purple,
                       detail: String(localized: "Today, this week, month or year — optionally for one category."))
            }

            Section {
                step(1, String(localized: "In Shortcuts, open Automation and tap +."))
                step(2, String(localized: "Choose Transaction, pick your cards, and select Run Immediately."))
                step(3, String(localized: "Add Wallet's Add Transaction action. Set Amount to the transaction's Amount and Merchant to its Merchant."))
                step(4, String(localized: "Every Apple Pay payment is now logged, already categorised from your history."))
            } header: {
                Text("Log Apple Pay automatically")
            }

            Section {
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Shortcuts & Siri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func action(_ title: LocalizedStringKey, symbol: String, tint: Color, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Brand.accent, in: .circle)
            Text(text).font(.subheadline)
        }
    }
}
