import SwiftUI

/// Category grid for transactions: your most-used first, then every group.
struct RecordCategoryPicker: View {
    let kind: RecordKind
    @Binding var selection: String
    var frequent: [String] = []

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var groups: [RecordGroup] {
        kind == .income ? [.income, .other] : RecordGroup.expenseGroups
    }

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                    if search.isEmpty, !frequent.isEmpty {
                        section(title: String(localized: "Frequently used", comment: "Category picker section"), symbol: "clock.arrow.circlepath", tint: .secondary, categories: frequent.compactMap(RecordCategory.init(rawValue:)))
                    }
                    ForEach(groups) { group in
                        let categories = RecordCategory.inGroup(group).filter(matches)
                        if !categories.isEmpty {
                            section(title: group.label, symbol: group.symbol, tint: group.tint, categories: categories)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search categories"))
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func matches(_ category: RecordCategory) -> Bool {
        search.isEmpty || category.label.localizedCaseInsensitiveContains(search) || category.group.label.localizedCaseInsensitiveContains(search)
    }

    private func section(title: String, symbol: String, tint: Color, categories: [RecordCategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(categories) { category in
                    let selected = category.rawValue == selection
                    Button {
                        selection = category.rawValue
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(selected ? .white : category.tint)
                                .frame(width: 44, height: 44)
                                .background(selected ? AnyShapeStyle(category.tint.gradient) : AnyShapeStyle(category.tint.opacity(0.14)), in: .circle)
                            Text(category.label)
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2, reservesSpace: true)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(selected ? category.tint : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Pick labels from the ones already in use, or add new ones.
struct LabelPicker: View {
    @Binding var selection: [String]
    let known: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var newLabel = ""
    @FocusState private var adding: Bool

    private var all: [String] {
        RecordDraft.normalisedLabels(selection + known)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New label", text: $newLabel)
                            .focused($adding)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Labels cut across categories — a shop, a trip, a person you split costs with.")
                }

                if !all.isEmpty {
                    Section {
                        ForEach(all, id: \.self) { label in
                            let selected = selection.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
                            Button {
                                toggle(label)
                            } label: {
                                HStack {
                                    Circle().fill(LabelTint.color(for: label)).frame(width: 10, height: 10)
                                    Text(label).foregroundStyle(.primary)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        selection = RecordDraft.normalisedLabels(selection + [label])
        newLabel = ""
    }

    private func toggle(_ label: String) {
        if let index = selection.firstIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            selection.remove(at: index)
        } else {
            selection.append(label)
        }
    }
}
