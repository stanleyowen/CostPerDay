import SwiftUI

/// The top level of the transaction category tree. Reports roll categories up into
/// these groups for the coarse "where did the money go" view.
enum RecordGroup: String, CaseIterable, Identifiable, Codable {
    case food, shopping, housing, transport, vehicle, life, communication
    case financial, investments, income, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: String(localized: "Food & Drinks", comment: "Transaction category group")
        case .shopping: String(localized: "Shopping", comment: "Transaction category group")
        case .housing: String(localized: "Housing", comment: "Transaction category group")
        case .transport: String(localized: "Transportation", comment: "Transaction category group")
        case .vehicle: String(localized: "Vehicle", comment: "Transaction category group")
        case .life: String(localized: "Life & Entertainment", comment: "Transaction category group")
        case .communication: String(localized: "Communication & PC", comment: "Transaction category group")
        case .financial: String(localized: "Financial expenses", comment: "Transaction category group")
        case .investments: String(localized: "Investments", comment: "Transaction category group")
        case .income: String(localized: "Income", comment: "Transaction category group")
        case .other: String(localized: "Others", comment: "Transaction category group")
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .shopping: "bag.fill"
        case .housing: "house.fill"
        case .transport: "bus.fill"
        case .vehicle: "car.fill"
        case .life: "theatermasks.fill"
        case .communication: "wifi"
        case .financial: "building.columns.fill"
        case .investments: "chart.line.uptrend.xyaxis"
        case .income: "arrow.down.circle.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .food: Color(red: 0.96, green: 0.42, blue: 0.20)
        case .shopping: Color(red: 0.91, green: 0.30, blue: 0.55)
        case .housing: Color(red: 0.72, green: 0.50, blue: 0.30)
        case .transport: Color(red: 0.20, green: 0.55, blue: 0.95)
        case .vehicle: Color(red: 0.36, green: 0.40, blue: 0.86)
        case .life: Color(red: 0.25, green: 0.72, blue: 0.45)
        case .communication: Color(red: 0.10, green: 0.70, blue: 0.80)
        case .financial: Color(red: 0.45, green: 0.52, blue: 0.60)
        case .investments: Color(red: 0.60, green: 0.38, blue: 0.90)
        case .income: Color(red: 0.16, green: 0.68, blue: 0.38)
        case .other: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }

    /// Groups offered when recording an expense — everything except income.
    static let expenseGroups: [RecordGroup] = allCases.filter { $0 != .income }
}

/// Built-in transaction categories, modelled on the familiar personal-finance tree
/// (and on BudgetBakers Wallet's, so its exports map one-to-one).
///
/// Raw values are persisted on every record: add cases, never rename them.
enum RecordCategory: String, CaseIterable, Identifiable, Codable {
    // Food & Drinks
    case foodGeneral, groceries, restaurant, barCafe
    // Shopping
    case shoppingGeneral, clothes, jewels, healthBeauty, kids, homeGarden, pets
    case electronics, gifts, stationery, freeTime, drugstore
    // Housing
    case housingGeneral, rent, mortgage, utilities, services, maintenance, propertyInsurance
    // Transportation
    case transportGeneral, publicTransport, taxi, longDistance, businessTrips
    // Vehicle
    case vehicleGeneral, fuel, parking, vehicleMaintenance, rentals, vehicleInsurance, leasing
    // Life & Entertainment
    case lifeGeneral, healthCare, wellness, fitness, events, lifeEvents, hobbies
    case education, subscriptions, streaming, travel, charity, alcoholTobacco, lottery
    // Communication & PC
    case communicationGeneral, phone, internet, software, postal
    // Financial expenses
    case financialGeneral, taxes, insurance, loanInterest, fines, advisory, fees, childSupport
    // Investments
    case investmentsGeneral, realty, vehiclesChattels, financialInvestments, savings, collections
    // Income
    case incomeGeneral, wage, interest, sale, rentalIncome, grants, lending, coupons
    case lotteryWinnings, refunds, childSupportIncome, giftsReceived
    // Others
    case otherGeneral, unknown

    var id: String { rawValue }

    var group: RecordGroup {
        switch self {
        case .foodGeneral, .groceries, .restaurant, .barCafe: .food
        case .shoppingGeneral, .clothes, .jewels, .healthBeauty, .kids, .homeGarden, .pets,
             .electronics, .gifts, .stationery, .freeTime, .drugstore: .shopping
        case .housingGeneral, .rent, .mortgage, .utilities, .services, .maintenance, .propertyInsurance: .housing
        case .transportGeneral, .publicTransport, .taxi, .longDistance, .businessTrips: .transport
        case .vehicleGeneral, .fuel, .parking, .vehicleMaintenance, .rentals, .vehicleInsurance, .leasing: .vehicle
        case .lifeGeneral, .healthCare, .wellness, .fitness, .events, .lifeEvents, .hobbies,
             .education, .subscriptions, .streaming, .travel, .charity, .alcoholTobacco, .lottery: .life
        case .communicationGeneral, .phone, .internet, .software, .postal: .communication
        case .financialGeneral, .taxes, .insurance, .loanInterest, .fines, .advisory, .fees, .childSupport: .financial
        case .investmentsGeneral, .realty, .vehiclesChattels, .financialInvestments, .savings, .collections: .investments
        case .incomeGeneral, .wage, .interest, .sale, .rentalIncome, .grants, .lending, .coupons,
             .lotteryWinnings, .refunds, .childSupportIncome, .giftsReceived: .income
        case .otherGeneral, .unknown: .other
        }
    }

    /// The group's own catch-all entry ("Food & Drinks" rather than "Groceries").
    var isGeneral: Bool { Self.generalByGroup[group] == self }

    var label: String {
        switch self {
        case .foodGeneral: RecordGroup.food.label
        case .groceries: String(localized: "Groceries", comment: "Transaction category")
        case .restaurant: String(localized: "Restaurant, fast-food", comment: "Transaction category")
        case .barCafe: String(localized: "Bar, cafe", comment: "Transaction category")
        case .shoppingGeneral: RecordGroup.shopping.label
        case .clothes: String(localized: "Clothes & shoes", comment: "Transaction category")
        case .jewels: String(localized: "Jewels, accessories", comment: "Transaction category")
        case .healthBeauty: String(localized: "Health and beauty", comment: "Transaction category")
        case .kids: String(localized: "Kids", comment: "Transaction category")
        case .homeGarden: String(localized: "Home, garden", comment: "Transaction category")
        case .pets: String(localized: "Pets, animals", comment: "Transaction category")
        case .electronics: String(localized: "Electronics, accessories", comment: "Transaction category")
        case .gifts: String(localized: "Gifts, joy", comment: "Transaction category")
        case .stationery: String(localized: "Stationery, tools", comment: "Transaction category")
        case .freeTime: String(localized: "Free time", comment: "Transaction category")
        case .drugstore: String(localized: "Drug-store, chemist", comment: "Transaction category")
        case .housingGeneral: RecordGroup.housing.label
        case .rent: String(localized: "Rent", comment: "Transaction category")
        case .mortgage: String(localized: "Mortgage", comment: "Transaction category")
        case .utilities: String(localized: "Energy, utilities", comment: "Transaction category")
        case .services: String(localized: "Services", comment: "Transaction category")
        case .maintenance: String(localized: "Maintenance, repairs", comment: "Transaction category")
        case .propertyInsurance: String(localized: "Property insurance", comment: "Transaction category")
        case .transportGeneral: RecordGroup.transport.label
        case .publicTransport: String(localized: "Public transport", comment: "Transaction category")
        case .taxi: String(localized: "Taxi", comment: "Transaction category")
        case .longDistance: String(localized: "Long distance", comment: "Transaction category")
        case .businessTrips: String(localized: "Business trips", comment: "Transaction category")
        case .vehicleGeneral: RecordGroup.vehicle.label
        case .fuel: String(localized: "Fuel", comment: "Transaction category")
        case .parking: String(localized: "Parking", comment: "Transaction category")
        case .vehicleMaintenance: String(localized: "Vehicle maintenance", comment: "Transaction category")
        case .rentals: String(localized: "Rentals", comment: "Transaction category")
        case .vehicleInsurance: String(localized: "Vehicle insurance", comment: "Transaction category")
        case .leasing: String(localized: "Leasing", comment: "Transaction category")
        case .lifeGeneral: RecordGroup.life.label
        case .healthCare: String(localized: "Health care, doctor", comment: "Transaction category")
        case .wellness: String(localized: "Wellness, beauty", comment: "Transaction category")
        case .fitness: String(localized: "Active sport, fitness", comment: "Transaction category")
        case .events: String(localized: "Culture, sport events", comment: "Transaction category")
        case .lifeEvents: String(localized: "Life events", comment: "Transaction category")
        case .hobbies: String(localized: "Hobbies", comment: "Transaction category")
        case .education: String(localized: "Education, development", comment: "Transaction category")
        case .subscriptions: String(localized: "Books, audio, subscriptions", comment: "Transaction category")
        case .streaming: String(localized: "TV, streaming", comment: "Transaction category")
        case .travel: String(localized: "Holiday, trips, hotels", comment: "Transaction category")
        case .charity: String(localized: "Charity, gifts", comment: "Transaction category")
        case .alcoholTobacco: String(localized: "Alcohol, tobacco", comment: "Transaction category")
        case .lottery: String(localized: "Lottery, gambling", comment: "Transaction category")
        case .communicationGeneral: RecordGroup.communication.label
        case .phone: String(localized: "Phone, cell phone", comment: "Transaction category")
        case .internet: String(localized: "Internet", comment: "Transaction category")
        case .software: String(localized: "Software, apps, games", comment: "Transaction category")
        case .postal: String(localized: "Postal services", comment: "Transaction category")
        case .financialGeneral: RecordGroup.financial.label
        case .taxes: String(localized: "Taxes", comment: "Transaction category")
        case .insurance: String(localized: "Insurances", comment: "Transaction category")
        case .loanInterest: String(localized: "Loan, interests", comment: "Transaction category")
        case .fines: String(localized: "Fines", comment: "Transaction category")
        case .advisory: String(localized: "Advisory", comment: "Transaction category")
        case .fees: String(localized: "Charges, fees", comment: "Transaction category")
        case .childSupport: String(localized: "Child support", comment: "Transaction category")
        case .investmentsGeneral: RecordGroup.investments.label
        case .realty: String(localized: "Realty", comment: "Transaction category")
        case .vehiclesChattels: String(localized: "Vehicles, chattels", comment: "Transaction category")
        case .financialInvestments: String(localized: "Financial investments", comment: "Transaction category")
        case .savings: String(localized: "Savings", comment: "Transaction category")
        case .collections: String(localized: "Collections", comment: "Transaction category")
        case .incomeGeneral: RecordGroup.income.label
        case .wage: String(localized: "Wage, invoices", comment: "Transaction category")
        case .interest: String(localized: "Interests, dividends", comment: "Transaction category")
        case .sale: String(localized: "Sale", comment: "Transaction category")
        case .rentalIncome: String(localized: "Rental income", comment: "Transaction category")
        case .grants: String(localized: "Dues & grants", comment: "Transaction category")
        case .lending: String(localized: "Lending, renting", comment: "Transaction category")
        case .coupons: String(localized: "Checks, coupons", comment: "Transaction category")
        case .lotteryWinnings: String(localized: "Lottery winnings", comment: "Transaction category")
        case .refunds: String(localized: "Refunds (tax, purchase)", comment: "Transaction category")
        case .childSupportIncome: String(localized: "Child support received", comment: "Transaction category")
        case .giftsReceived: String(localized: "Gifts received", comment: "Transaction category")
        case .otherGeneral: RecordGroup.other.label
        case .unknown: String(localized: "Uncategorised", comment: "Transaction category")
        }
    }

    var symbol: String {
        switch self {
        case .foodGeneral: "fork.knife"
        case .groceries: "cart.fill"
        case .restaurant: "takeoutbag.and.cup.and.straw.fill"
        case .barCafe: "cup.and.saucer.fill"
        case .shoppingGeneral: "bag.fill"
        case .clothes: "tshirt.fill"
        case .jewels: "sparkles"
        case .healthBeauty: "comb.fill"
        case .kids: "figure.and.child.holdinghands"
        case .homeGarden: "leaf.fill"
        case .pets: "pawprint.fill"
        case .electronics: "headphones"
        case .gifts: "gift.fill"
        case .stationery: "pencil.and.ruler.fill"
        case .freeTime: "gamecontroller.fill"
        case .drugstore: "cross.case.fill"
        case .housingGeneral: "house.fill"
        case .rent: "key.fill"
        case .mortgage: "building.2.fill"
        case .utilities: "bolt.fill"
        case .services: "wrench.adjustable.fill"
        case .maintenance: "hammer.fill"
        case .propertyInsurance: "house.lodge.fill"
        case .transportGeneral: "bus.fill"
        case .publicTransport: "tram.fill"
        case .taxi: "car.side.fill"
        case .longDistance: "airplane"
        case .businessTrips: "briefcase.fill"
        case .vehicleGeneral: "car.fill"
        case .fuel: "fuelpump.fill"
        case .parking: "parkingsign.circle.fill"
        case .vehicleMaintenance: "wrench.and.screwdriver.fill"
        case .rentals: "car.2.fill"
        case .vehicleInsurance: "checkmark.shield.fill"
        case .leasing: "doc.text.fill"
        case .lifeGeneral: "theatermasks.fill"
        case .healthCare: "stethoscope"
        case .wellness: "heart.fill"
        case .fitness: "figure.run"
        case .events: "ticket.fill"
        case .lifeEvents: "balloon.2.fill"
        case .hobbies: "paintpalette.fill"
        case .education: "graduationcap.fill"
        case .subscriptions: "books.vertical.fill"
        case .streaming: "play.tv.fill"
        case .travel: "suitcase.rolling.fill"
        case .charity: "hand.raised.fill"
        case .alcoholTobacco: "wineglass.fill"
        case .lottery: "dice.fill"
        case .communicationGeneral: "wifi"
        case .phone: "iphone"
        case .internet: "network"
        case .software: "app.badge.fill"
        case .postal: "envelope.fill"
        case .financialGeneral: "building.columns.fill"
        case .taxes: "percent"
        case .insurance: "shield.lefthalf.filled"
        case .loanInterest: "creditcard.fill"
        case .fines: "exclamationmark.triangle.fill"
        case .advisory: "person.crop.circle.badge.questionmark"
        case .fees: "banknote.fill"
        case .childSupport: "figure.2.and.child.holdinghands"
        case .investmentsGeneral: "chart.line.uptrend.xyaxis"
        case .realty: "building.fill"
        case .vehiclesChattels: "shippingbox.fill"
        case .financialInvestments: "chart.bar.fill"
        case .savings: "dollarsign.circle.fill"
        case .collections: "square.stack.3d.up.fill"
        case .incomeGeneral: "arrow.down.circle.fill"
        case .wage: "briefcase.fill"
        case .interest: "percent"
        case .sale: "tag.fill"
        case .rentalIncome: "key.fill"
        case .grants: "rosette"
        case .lending: "arrow.left.arrow.right"
        case .coupons: "ticket.fill"
        case .lotteryWinnings: "star.fill"
        case .refunds: "arrow.uturn.backward.circle.fill"
        case .childSupportIncome: "figure.2.and.child.holdinghands"
        case .giftsReceived: "gift.fill"
        case .otherGeneral: "ellipsis.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var tint: Color { group.tint }

    /// Whether this category normally describes money coming in. Used to pick the
    /// right list when the user switches between expense and income.
    var isIncome: Bool { group == .income }

    static func inGroup(_ group: RecordGroup) -> [RecordCategory] {
        allCases.filter { $0.group == group }
    }

    private static let generalByGroup: [RecordGroup: RecordCategory] = [
        .food: .foodGeneral, .shopping: .shoppingGeneral, .housing: .housingGeneral,
        .transport: .transportGeneral, .vehicle: .vehicleGeneral, .life: .lifeGeneral,
        .communication: .communicationGeneral, .financial: .financialGeneral,
        .investments: .investmentsGeneral, .income: .incomeGeneral, .other: .otherGeneral,
    ]

    static func general(of group: RecordGroup) -> RecordCategory {
        generalByGroup[group] ?? .otherGeneral
    }

    /// The closest category in the ownership tracker, used when a purchase is turned
    /// into a tracked item. Nil when no sensible item category exists (food, fees…).
    var suggestedItemCategory: ItemCategory? {
        switch self {
        case .electronics: .accessory
        case .phone: .phone
        case .clothes: .clothing
        case .jewels: .jewellery
        case .homeGarden: .decor
        case .freeTime, .hobbies: .games
        case .stationery: .tools
        case .fitness: .sports
        case .vehicleGeneral, .vehiclesChattels: .vehicle
        case .software: .other
        case .shoppingGeneral, .gifts, .collections: .other
        default: nil
        }
    }

    /// Categories whose purchases tend to be things you keep, so Wallet can suggest
    /// tracking their lifecycle.
    var isDurable: Bool { suggestedItemCategory != nil && self != .software && self != .gifts }
}

// MARK: - Display

/// Everything needed to draw a transaction's category, including the unknown case.
struct RecordCategoryDisplay: Hashable, Identifiable {
    let key: String
    let label: String
    let symbol: String
    let tint: Color
    let group: RecordGroup
    let isMissing: Bool

    var id: String { key }

    static func resolve(_ key: String) -> RecordCategoryDisplay {
        if let category = RecordCategory(rawValue: key) {
            return RecordCategoryDisplay(
                key: key, label: category.label, symbol: category.symbol,
                tint: category.tint, group: category.group, isMissing: false
            )
        }
        return RecordCategoryDisplay(
            key: key,
            label: String(localized: "Removed category", comment: "Shown when an item refers to a category that no longer exists"),
            symbol: "questionmark.circle", tint: .secondary, group: .other, isMissing: true
        )
    }

    /// Transfers have no category of their own; they borrow this neutral look.
    static let transfer = RecordCategoryDisplay(
        key: "transfer",
        label: String(localized: "Transfer", comment: "Transaction type"),
        symbol: "arrow.left.arrow.right",
        tint: Color(red: 0.42, green: 0.48, blue: 0.62),
        group: .other,
        isMissing: false
    )
}
