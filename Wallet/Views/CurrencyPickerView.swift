import SwiftUI

/// Searchable currency list — the system has well over a hundred, so a plain picker
/// meant a long scroll every time. Common currencies come first; search matches the
/// code or the localized name ("yen", "JPY", "円").
struct CurrencyPickerView: View {
    @Binding var selection: String
    /// Called after a choice is made, instead of writing the binding directly — the
    /// base-currency switch needs to confirm a rate first.
    var onPick: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Currency.all }
        return Currency.all.filter { Currency.matches($0, query: query) }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { code in
                Button {
                    if let onPick { onPick(code) } else { selection = code }
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(Currency.symbol(code))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(width: 40, height: 40)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(code).font(.body.weight(.semibold))
                            Text(Currency.name(code)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if code == selection {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search currencies"))
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
