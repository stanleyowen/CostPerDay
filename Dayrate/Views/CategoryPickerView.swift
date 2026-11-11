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

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                ForEach(groups, id: \.sector) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(group.sector.label, systemImage: group.sector.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(group.categories) { category in
                                CategoryCell(category: category, isSelected: category.key == selectedKey) {
                                    selectedKey = category.key
                                    onSelect(category)
                                    dismiss()
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        creatingCategory = CustomCategory()
                    } label: {
                        Label("New category", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Text("If no category matches, create your own with a dedicated icon and typical lifetime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $search, prompt: Text("Search categories"))
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selectedKey)
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

/// One tappable category tile: icon, name and typical lifetime.
private struct CategoryCell: View {
    let category: CategoryDisplay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CategoryTile(symbol: category.symbol, tint: category.tint, size: 42)
                VStack(spacing: 1) {
                    Text(category.label)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(Duration.fromMonthsAbbreviated(category.defaultLifetimeMonths))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Keeps every tile in a row the same height whether the name takes
                // one line or two.
                .frame(height: 50, alignment: .top)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? category.tint : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, category.tint)
                        .padding(6)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(String(localized: "Typically lasts \(Duration.fromMonths(category.defaultLifetimeMonths))")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    VStack(spacing: 10) {
                        CategoryTile(symbol: draft.symbolName, tint: draft.tint.color, size: 72)
                            .animation(.snappy, value: draft.symbolName)
                        Text(trimmedName.isEmpty ? String(localized: "Untitled") : trimmedName)
                            .font(.headline)
                            .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                        Text(Duration.fromMonths(draft.defaultLifetimeMonths))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

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
                                    .accessibilityLabel(Text(verbatim: symbol))
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
                                withAnimation(.snappy) { draft.tint = tint }
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
                            .accessibilityLabel(Text(tint.label))
                            .accessibilityAddTraits(draft.tint == tint ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: draft.tint)
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
