import Foundation

/// Everything that can be wrong with a gadget entry, checked in one place so the
/// edit form, the importer, and the tests all agree on what "valid" means.
enum GadgetValidation {
    enum Field: Hashable {
        case name, price, currency, rate, purchaseDate, lifetime, resale, retiredDate
    }

    struct Issue: Identifiable, Hashable {
        let field: Field
        let message: String
        var id: Field { field }
    }

    static func issues(for gadget: Gadget, baseCurrency: String, now: Date = .now) -> [Issue] {
        var issues: [Issue] = []

        if gadget.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(Issue(field: .name, message: "Give it a name."))
        }

        if !gadget.price.isFinite || gadget.price <= 0 {
            issues.append(Issue(field: .price, message: "Price must be more than zero."))
        } else if gadget.price > 1_000_000_000 {
            // A currency-blind cap, not a plausibility check — 10,000,000 was a
            // reasonable ceiling in USD/EUR but flagged perfectly normal prices in
            // low-value currencies (e.g. 17,249,000 IDR is only about $1,050).
            // This just catches an accidental extra digit or two.
            issues.append(Issue(field: .price, message: "That's a huge number — check you didn't add an extra digit."))
        }

        if gadget.currencyCode.count != 3 {
            issues.append(Issue(field: .currency, message: "Pick a currency."))
        }

        if gadget.currencyCode != baseCurrency {
            if !gadget.rateToBase.isFinite || gadget.rateToBase <= 0 {
                issues.append(Issue(field: .rate, message: "Enter how much 1 \(gadget.currencyCode) is worth in \(baseCurrency)."))
            }
            if gadget.resaleValue > 0, gadget.resaleRateToBase != 0,
               !gadget.resaleRateToBase.isFinite || gadget.resaleRateToBase <= 0 {
                issues.append(Issue(field: .rate, message: "The resale rate must be more than zero."))
            }
        }

        if gadget.purchaseDate.startOfDay > now.startOfDay {
            issues.append(Issue(field: .purchaseDate, message: "You can't have bought it in the future."))
        }

        if gadget.expectedLifetimeMonths < 1 {
            issues.append(Issue(field: .lifetime, message: "Expected lifetime must be at least one month."))
        } else if gadget.expectedLifetimeMonths > Gadget.maxLifetimeMonths {
            issues.append(Issue(field: .lifetime, message: "Expected lifetime tops out at 50 years."))
        }

        if !gadget.resaleValue.isFinite || gadget.resaleValue < 0 {
            issues.append(Issue(field: .resale, message: "Recovered value can't be negative."))
        } else if gadget.resaleValue > gadget.price, gadget.price > 0 {
            issues.append(Issue(field: .resale, message: "You can't recover more than you paid."))
        }

        if let retired = gadget.retiredDate {
            if retired.startOfDay < gadget.purchaseDate.startOfDay {
                issues.append(Issue(field: .retiredDate, message: "It can't be retired before you bought it."))
            } else if retired.startOfDay > now.startOfDay {
                issues.append(Issue(field: .retiredDate, message: "Retirement date can't be in the future."))
            }
        }

        return issues
    }

    static func isValid(_ gadget: Gadget, baseCurrency: String, now: Date = .now) -> Bool {
        issues(for: gadget, baseCurrency: baseCurrency, now: now).isEmpty
    }

    static func message(for field: Field, in issues: [Issue]) -> String? {
        issues.first { $0.field == field }?.message
    }
}
