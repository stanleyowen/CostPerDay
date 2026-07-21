import SwiftUI
import SwiftData

/// Full-screen category chooser, grouped by sector. A flat picker stopped being
/// usable once the app covered more than electronics.
struct CategoryPickerView: View {
    @Binding var selectedKey: String
    /// Called when the choice changes, so the caller can re-apply a default lifetime.
    var onSelect: (CategoryDisplay) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Query private var customCategories: [CustomCategory]
    @State private var search = ""
    @State private var creatingCategory: CustomCategory?

    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }

    private var groups: [(sector: Sector, categories: [CategoryDisplay])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalog.grouped }
        return catalog.grouped.compactMap { group in
            let matches = group.categories.filter {
                $0.label.localizedCaseInsensitiveContains(query)
            }
            return matches.isEmpty ? nil : (group.sector, matches)
        }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.sector) { group in
                Section {
                    ForEach(group.categories) { category in
                        Button {
                            selectedKey = category.key
                            onSelect(category)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.symbol)
                                    .foregroundStyle(category.tint)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.label)
                                        .foregroundStyle(.primary)
                                    Text("Typically lasts \(Duration.fromMonths(category.defaultLifetimeMonths))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if category.key == selectedKey {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        // Without this, List gives every Button row's text the accent
                        // tint by default — it reads as disabled/washed-out, not selectable.
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label(group.sector.label, systemImage: group.sector.symbol)
                }
            }

            Section {
                Button {
                    creatingCategory = CustomCategory()
                } label: {
                    Label("New category", systemImage: "plus.circle")
                }
            } footer: {
                Text("If no category matches, create your own with a dedicated icon and typical lifetime.")
            }
        }
        .searchable(text: $search, prompt: Text("Search categories"))
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $creatingCategory) { category in
            CustomCategoryEditView(category: category, isNew: true) { saved in
                // Adopt the category the user just created — that's why they made it.
                selectedKey = saved.key
                onSelect(CategoryCatalog.display(for: saved))
                dismiss()
            }
        }
    }
}

/// Create or edit one user-defined category.
struct CustomCategoryEditView: View {
    let category: CustomCategory
    let isNew: Bool
    var onSave: (CustomCategory) -> Void

    /// The form edits this, never `category` directly — so Cancel can simply dismiss
    /// without needing to undo anything. `category` is only touched once, on Save.
    @State private var draft: CustomCategoryDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    init(category: CustomCategory, isNew: Bool, onSave: @escaping (CustomCategory) -> Void = { _ in }) {
        self.category = category
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: CustomCategoryDraft(category: category))
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Sector", selection: $draft.sector) {
                        ForEach(Sector.allCases) { sector in
                            Label(sector.label, systemImage: sector.symbol).tag(sector)
                        }
                    }
                } footer: {
                    Text("The sector determines how this category is grouped in the picker and on the dashboard.")
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CategorySymbols.choices, id: \.self) { symbol in
                            Button {
                                draft.symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(draft.symbolName == symbol ? .white : draft.tint.color)
                                    .background(
                                        draft.symbolName == symbol ? draft.tint.color : Color(.tertiarySystemFill),
                                        in: .rect(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Colour") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CategoryTint.allCases) { tint in
                            Button {
                                draft.tint = tint
                            } label: {
                                Circle()
                                    .fill(tint.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if draft.tint == tint {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Stepper(value: $draft.defaultLifetimeMonths, in: 1...Item.maxLifetimeMonths, step: 1) {
                        LabeledContent(
                            "Typically lasts",
                            value: Duration.fromMonths(draft.defaultLifetimeMonths)
                        )
                    }
                } header: {
                    Text("Default lifetime")
                } footer: {
                    Text("Pre-fills the expected lifetime when this category is selected. It can still be adjusted for each individual item.")
                }
            }
            .navigationTitle(isNew ? String(localized: "New Category", comment: "Screen title") : String(localized: "Edit Category", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .interactiveDismissDisabled(isNew)
    }

    private func save() {
        draft.name = trimmedName
        draft.apply(to: category)
        // A brand-new category isn't inserted until Save, so cancelling leaves nothing behind.
        if isNew { context.insert(category) }
        do {
            try context.save()
            onSave(category)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        dismiss()
    }
}
