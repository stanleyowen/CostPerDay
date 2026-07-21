import Foundation

/// Everything that can be wrong with an item entry, checked in one place so the
/// edit form, the importer, and the tests all agree on what "valid" means.
enum ItemValidation {
    enum Field: Hashable {
        case name, price, currency, rate, purchaseDate, lifetime, resale, retiredDate
    }

    struct Issue: Identifiable, Hashable {
        let field: Field
        let message: String
        var id: Field { field }
    }

    static func issues(for item: Item, baseCurrency: String, now: Date = .now) -> [Issue] {
        var issues: [Issue] = []

        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(Issue(field: .name, message: String(
                localized: "A name is required.",
                comment: "Validation error"
            )))
        }

        if !item.price.isFinite || item.price <= 0 {
            issues.append(Issue(field: .price, message: String(
                localized: "The price must be greater than zero.",
                comment: "Validation error"
            )))
        } else if item.price > 1_000_000_000 {
            // A currency-blind cap, not a plausibility check — 10,000,000 was a
            // reasonable ceiling in USD/EUR but flagged perfectly normal prices in
            // low-value currencies (e.g. 17,249,000 IDR is only about $1,050).
            // This only catches an accidental extra digit or two.
            issues.append(Issue(field: .price, message: String(
                localized: "This amount is unusually large. Please confirm the number of digits.",
                comment: "Validation error"
            )))
        }

        if item.currencyCode.count != 3 {
            issues.append(Issue(field: .currency, message: String(
                localized: "Please select a currency.",
                comment: "Validation error"
            )))
        }

        if item.currencyCode != baseCurrency {
            if !item.rateToBase.isFinite || item.rateToBase <= 0 {
                issues.append(Issue(field: .rate, message: String(
                    localized: "Please enter the value of 1 \(item.currencyCode) in \(baseCurrency).",
                    comment: "Validation error. First placeholder is the item's currency code, second is the base currency code."
                )))
            }
            if item.resaleValue > 0, item.resaleRateToBase != 0,
               !item.resaleRateToBase.isFinite || item.resaleRateToBase <= 0 {
                issues.append(Issue(field: .rate, message: String(
                    localized: "The resale exchange rate must be greater than zero.",
                    comment: "Validation error"
                )))
            }
        }

        if item.purchaseDate.startOfDay > now.startOfDay {
            issues.append(Issue(field: .purchaseDate, message: String(
                localized: "The purchase date cannot be in the future.",
                comment: "Validation error"
            )))
        }

        if item.expectedLifetimeMonths < 1 {
            issues.append(Issue(field: .lifetime, message: String(
                localized: "The expected lifetime must be at least one month.",
                comment: "Validation error"
            )))
        } else if item.expectedLifetimeMonths > Item.maxLifetimeMonths {
            issues.append(Issue(field: .lifetime, message: String(
                localized: "The expected lifetime cannot exceed 50 years.",
                comment: "Validation error"
            )))
        }

        if !item.resaleValue.isFinite || item.resaleValue < 0 {
            issues.append(Issue(field: .resale, message: String(
                localized: "The recovered value cannot be negative.",
                comment: "Validation error"
            )))
        } else if item.resaleValue > item.price, item.price > 0 {
            issues.append(Issue(field: .resale, message: String(
                localized: "The recovered value cannot exceed the purchase price.",
                comment: "Validation error"
            )))
        }

        if let retired = item.retiredDate {
            if retired.startOfDay < item.purchaseDate.startOfDay {
                issues.append(Issue(field: .retiredDate, message: String(
                    localized: "The retirement date cannot precede the purchase date.",
                    comment: "Validation error"
                )))
            } else if retired.startOfDay > now.startOfDay {
                issues.append(Issue(field: .retiredDate, message: String(
                    localized: "The retirement date cannot be in the future.",
                    comment: "Validation error"
                )))
            }
        }

        return issues
    }

    static func isValid(_ item: Item, baseCurrency: String, now: Date = .now) -> Bool {
        issues(for: item, baseCurrency: baseCurrency, now: now).isEmpty
    }

    static func message(for field: Field, in issues: [Issue]) -> String? {
        issues.first { $0.field == field }?.message
    }
}
