#if DEBUG
import Foundation
import SwiftData

/// The sample data used when the base currency is NT$: a young professional renting
/// in Taipei on NT$62,000 a month. The ledger is simulated day by day, so it adds
/// up the way a real one would — cash comes from ATM withdrawals when the wallet runs
/// low, EasyCard is topped up from cash, the credit card is paid off in full every
/// month, and savings grow by the monthly transfer plus interest.
extension SampleData {
    @MainActor
    static func insertTaiwanLedger(into context: ModelContext) {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let days = 150
        var random = SeededRandom(seed: 886)

        let bank = Account(name: "Cathay Payroll", kind: .bank, currencyCode: "TWD", initialBalance: 86_400, tint: .preset(.green), sortOrder: 0)
        let card = Account(name: "CUBE Card", kind: .card, currencyCode: "TWD", initialBalance: 0, tint: .custom("#2B4C7E"), sortOrder: 1)
        let cash = Account(name: "Cash", kind: .cash, currencyCode: "TWD", initialBalance: 2_600, tint: .preset(.orange), sortOrder: 2)
        let easyCard = Account(name: "EasyCard", kind: .eWallet, currencyCode: "TWD", initialBalance: 380, tint: .preset(.cyan), sortOrder: 3)
        let savings = Account(name: "Richart Savings", kind: .savings, currencyCode: "TWD", initialBalance: 320_000, tint: .custom("#C9A227"), sortOrder: 4)
        savings.excludeFromStats = true
        for account in [bank, card, cash, easyCard, savings] { context.insert(account) }

        var balance: [UUID: Double] = [
            bank.uuid: bank.initialBalance, card.uuid: 0, cash.uuid: cash.initialBalance,
            easyCard.uuid: easyCard.initialBalance, savings.uuid: savings.initialBalance,
        ]

        func move(_ amount: Double, from: Account, to: Account, _ note: String, at date: Date) {
            context.insert(Record(kind: .transfer, amount: amount, currencyCode: "TWD", date: date, accountID: from.uuid, toAccountID: to.uuid, note: note))
            balance[from.uuid, default: 0] -= amount
            balance[to.uuid, default: 0] += amount
        }
        /// When the payroll account can't cover a payment (the month the Japan trip and
        /// the camera hit the card), money comes back from savings in round tens of thousands.
        func coverFromSavings(_ amount: Double, from account: Account, at date: Date) {
            let shortfall = amount + 3_000 - balance[account.uuid, default: 0]
            guard account === bank, shortfall > 0 else { return }
            move((shortfall / 10_000).rounded(.up) * 10_000, from: savings, to: bank, "From savings", at: date.addingTimeInterval(-600))
        }
        func transfer(_ amount: Double, from: Account, to: Account, _ note: String, at date: Date) {
            guard date <= now, amount > 0 else { return }
            coverFromSavings(amount, from: from, at: date)
            move(amount, from: from, to: to, note, at: date)
        }
        @discardableResult
        func expense(_ amount: Double, _ category: RecordCategory, _ note: String, from account: Account, at date: Date, labels: [String] = []) -> Record? {
            guard date <= now else { return nil }
            // Never spend money that isn't there: EasyCard autoloads from the credit
            // card, and the wallet gets an ATM stop first.
            let before = date.addingTimeInterval(-300)
            if account === easyCard, balance[easyCard.uuid, default: 0] < amount {
                transfer(500, from: card, to: easyCard, "EasyCard autoload", at: before)
            }
            if account === cash, balance[cash.uuid, default: 0] < amount {
                transfer(3_000, from: bank, to: cash, "ATM", at: before)
            }
            coverFromSavings(amount, from: account, at: date)
            let record = Record(kind: .expense, amount: amount, currencyCode: "TWD", date: date, accountID: account.uuid, category: category, note: note, labels: labels)
            context.insert(record)
            balance[account.uuid, default: 0] -= amount
            return record
        }
        func income(_ amount: Double, _ category: RecordCategory, _ note: String, to account: Account, at date: Date) {
            guard date <= now else { return }
            context.insert(Record(kind: .income, amount: amount, currencyCode: "TWD", date: date, accountID: account.uuid, category: category, note: note))
            balance[account.uuid, default: 0] += amount
        }
        /// A price that looks like one: whole dollars, rounded to 5 or 10 above NT$100.
        func price(_ low: Double, _ high: Double) -> Double {
            let raw = random.double(in: low...high)
            let step: Double = raw >= 1_000 ? 10 : raw >= 100 ? 5 : 1
            return (raw / step).rounded() * step
        }

        // The Japan trip: booked well ahead, five days in Osaka a couple of months ago.
        let tripStart = days - 87
        let tripDays = tripStart..<(tripStart + 5)
        let trip = ["Japan trip"]

        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset - days, to: today) else { continue }
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            }
            let weekday = calendar.component(.weekday, from: day)
            let dayOfMonth = calendar.component(.day, from: day)
            let month = calendar.component(.month, from: day)
            let isWorkday = (2...6).contains(weekday)
            let travelling = tripDays.contains(offset)

            // An ATM stop on the way to work once the wallet runs low.
            if !travelling, isWorkday, balance[cash.uuid, default: 0] < 800 {
                transfer(3_000, from: bank, to: cash, "ATM", at: at(8, 5))
            }

            // Monthly bills and money moves.
            switch dayOfMonth {
            case 1:
                expense(16_500, .rent, "Rent", from: bank, at: at(9))
            case 3:
                expense(1_388, .fitness, "World Gym", from: card, at: at(7))
            case 5:
                income(62_000, .wage, "Salary", to: bank, at: at(9))
            case 6:
                transfer(15_000, from: bank, to: savings, "Monthly saving", at: at(10))
            case 8:
                expense(599, .phone, "Chunghwa Telecom", from: card, at: at(9))
            case 12:
                expense(390, .streaming, "Netflix", from: card, at: at(6))
            case 15:
                expense(149, .streaming, "Spotify", from: card, at: at(6))
            case 18 where month % 2 == 1:
                // Taipower bills every other month, more in the air-conditioned summer.
                let summer = (6...9).contains(month)
                expense(summer ? price(2_100, 2_800) : price(850, 1_250), .utilities, "Taipower", from: bank, at: at(19))
                expense(price(260, 320), .utilities, "Water bill", from: bank, at: at(19, 5))
            case 20:
                // The card is paid off in full from the payroll account.
                transfer(balance[card.uuid].map { -$0 } ?? 0, from: bank, to: card, "Card payment", at: at(9))
            case 21:
                let interest = ((balance[savings.uuid] ?? 0) * 0.015 / 12).rounded()
                income(interest, .interest, "Interest", to: savings, at: at(6))
            case 25 where month % 2 == 0 && random.chance(0.5):
                income(200, .lotteryWinnings, "Receipt lottery", to: cash, at: at(20))
            default:
                break
            }

            if travelling {
                let dayOfTrip = offset - tripStart
                expense(price(1_600, 2_900), .restaurant, ["Dotonbori", "Kuromon Market", "Kyoto lunch", "Izakaya", "Airport ramen"][dayOfTrip], from: card, at: at(19), labels: trip)
                expense(price(250, 600), .publicTransport, "ICOCA", from: card, at: at(10), labels: trip)
                if dayOfTrip == 1 { expense(5_340, .healthBeauty, "Don Quijote", from: card, at: at(16), labels: trip) }
                if dayOfTrip == 2 { expense(1_150, .events, "Osaka Castle & museum", from: card, at: at(11), labels: trip) }
                if dayOfTrip == 3, let camera = expense(50_840, .electronics, "Fujifilm X100VI", from: card, at: at(17), labels: trip) {
                    let item = LedgerActions.trackAsItem(camera, in: context)
                    item.categoryRaw = ItemCategory.camera.rawValue
                    item.expectedLifetimeMonths = 72
                }
                continue
            }

            if isWorkday {
                if random.chance(0.8) {
                    expense(price(55, 90), .restaurant, random.pick(["Breakfast shop", "Egg crepe & soy milk", "Rice ball", "Breakfast shop"]), from: cash, at: at(8, 10))
                }
                if random.chance(0.95) {
                    expense(50, .publicTransport, "MRT commute", from: easyCard, at: at(8, 40))
                }
                if random.chance(0.45) {
                    if random.chance(0.7) {
                        expense(55, .barCafe, "7-Eleven City Cafe", from: easyCard, at: at(10, 20))
                    } else {
                        expense(price(80, 160), .barCafe, random.pick(["Louisa Coffee", "Starbucks"]), from: card, at: at(10, 20))
                    }
                }
                if random.chance(0.95) {
                    expense(price(100, 185), .restaurant, random.pick(["Bento", "Beef noodles", "Dumplings", "Curry rice", "Braised pork rice", "Pho"]), from: cash, at: at(12, 20))
                }
                if random.chance(0.35) {
                    expense(price(50, 75), .barCafe, "Bubble tea", from: cash, at: at(15, 30))
                }
                if weekday == 4 {
                    expense(price(380, 820), .groceries, "PX Mart", from: card, at: at(19, 10))
                } else if random.chance(0.2) {
                    expense(price(90, 160), .groceries, "FamilyMart", from: easyCard, at: at(19, 40))
                } else if random.chance(0.15) {
                    expense(price(420, 680), .restaurant, random.pick(["Hot pot", "Ramen", "Thai food"]), from: card, at: at(19, 30))
                } else {
                    expense(price(120, 240), .restaurant, random.pick(["Night market", "Fried rice", "Noodle stall", "Night market"]), from: cash, at: at(19, 30))
                }
            } else {
                if random.chance(0.6) {
                    expense(price(260, 420), .restaurant, "Brunch", from: card, at: at(11, 10))
                }
                if weekday == 7 {
                    expense(price(520, 1_050), .groceries, "Carrefour", from: card, at: at(16))
                    if random.chance(0.55) {
                        expense(price(650, 1_450), .restaurant, random.pick(["Hot pot with friends", "Izakaya", "Korean BBQ", "Din Tai Fung"]), from: card, at: at(19), labels: ["Friends"])
                        if random.chance(0.5) {
                            expense(price(180, 330), .taxi, "Uber", from: card, at: at(22, 40))
                        }
                    }
                } else {
                    expense(price(120, 220), .restaurant, random.pick(["Night market", "Dumplings", "Beef noodles"]), from: cash, at: at(18, 30))
                }
                if random.chance(0.3) {
                    expense(random.pick([320.0, 340, 360]), .events, "Movie", from: card, at: at(14), labels: random.chance(0.5) ? ["Friends"] : [])
                }
                if random.chance(0.35) {
                    expense(random.pick([10.0, 20, 30]), .publicTransport, "YouBike", from: easyCard, at: at(15))
                }
                if random.chance(0.4) {
                    expense(price(60, 85), .barCafe, "Bubble tea", from: cash, at: at(16, 30))
                }
                if random.chance(0.12) {
                    expense(random.pick([590.0, 790, 990, 1_490]), .clothes, "Uniqlo", from: card, at: at(15, 30))
                }
            }

            // Less regular errands.
            if offset % 19 == 4 {
                expense(price(240, 620), .drugstore, "Watsons", from: card, at: at(18, 50))
            }
            if offset % 34 == 9 {
                expense(500, .wellness, "Haircut", from: cash, at: at(13))
            }
            if offset % 11 == 2 {
                expense(price(290, 1_650), random.pick([.homeGarden, .stationery, .homeGarden, .healthBeauty]), "Shopee order", from: card, at: at(21, 15))
            }
            if offset == 41 || offset == 118 {
                expense(150, .healthCare, "Clinic co-pay", from: cash, at: at(18))
            }

            // One-offs: the trip bookings, a purchase tracked as an item and one waiting to be.
            if offset == tripStart - 46 {
                expense(13_860, .travel, "Flights TPE–KIX", from: card, at: at(22), labels: trip)
            }
            if offset == tripStart - 30 {
                expense(16_240, .travel, "Osaka hotel", from: card, at: at(21, 30), labels: trip)
            }
            if offset == days - 40 {
                if let buds = expense(7_490, .electronics, "AirPods Pro 2", from: card, at: at(20, 30)) {
                    LedgerActions.trackAsItem(buds, in: context).categoryRaw = ItemCategory.audio.rawValue
                }
            }
            if offset == days - 5 {
                expense(9_990, .electronics, "Panasonic dehumidifier", from: card, at: at(21))
            }
        }

        context.insert(Budget(name: "Food", limit: 18_000, period: .month, categoryKeys: ["group:food"]))
        context.insert(Budget(name: "Shopping", limit: 5_000, period: .month, categoryKeys: ["group:shopping"]))
        context.insert(Budget(name: "Everything", limit: 45_000, period: .month, categoryKeys: []))
        try? context.save()
    }

    /// Things owned, priced as bought in Taiwan; one ordered from the US at the rate of the day.
    static func makeTaiwanItems() -> [Item] {
        func ago(_ months: Int) -> Date {
            Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        }
        let iphone = Item(name: "iPhone 16 Pro", brand: "Apple", category: .phone, price: 36_900, currencyCode: "TWD", purchaseDate: ago(9), expectedLifetimeMonths: 36)
        let mac = Item(name: "MacBook Air 13\"", brand: "Apple", category: .laptop, price: 35_900, currencyCode: "TWD", purchaseDate: ago(20), expectedLifetimeMonths: 60)
        let scooter = Item(name: "Gogoro VIVA MIX", brand: "Gogoro", category: .vehicle, price: 62_980, currencyCode: "TWD", purchaseDate: ago(30), expectedLifetimeMonths: 96)
        let bike = Item(name: "Escape R3", brand: "Giant", category: .bicycle, price: 16_800, currencyCode: "TWD", purchaseDate: ago(40), expectedLifetimeMonths: 84)
        let cooker = Item(name: "Electric Cooker", brand: "Tatung", category: .smallAppliance, price: 2_690, currencyCode: "TWD", purchaseDate: ago(50), expectedLifetimeMonths: 180)
        let vacuum = Item(name: "V12 Vacuum", brand: "Dyson", category: .largeAppliance, price: 21_900, currencyCode: "TWD", purchaseDate: ago(26), expectedLifetimeMonths: 72)
        let mattress = Item(name: "Pocket Spring Mattress", brand: "Sealy", category: .bed, price: 18_800, currencyCode: "TWD", purchaseDate: ago(34), expectedLifetimeMonths: 96)
        let chair = Item(name: "Ergonomic Chair", brand: "Ergohuman", category: .seating, price: 12_900, currencyCode: "TWD", purchaseDate: ago(22), expectedLifetimeMonths: 96)
        let desk = Item(name: "Standing Desk", brand: "IKEA", category: .tableDesk, price: 9_990, currencyCode: "TWD", purchaseDate: ago(22), expectedLifetimeMonths: 120)
        let shoes = Item(name: "Pegasus 41", brand: "Nike", category: .footwear, price: 3_900, currencyCode: "TWD", purchaseDate: ago(8), expectedLifetimeMonths: 18)
        let jacket = Item(name: "Ultra Light Down Jacket", brand: "Uniqlo", category: .clothing, price: 1_990, currencyCode: "TWD", purchaseDate: ago(23), expectedLifetimeMonths: 60)
        let glasses = Item(name: "Prescription Glasses", category: .eyewear, price: 6_800, currencyCode: "TWD", purchaseDate: ago(14), expectedLifetimeMonths: 24)
        let keyboard = Item(name: "Keychron K3", brand: "Keychron", category: .accessory, price: 94, currencyCode: "USD", rateToBase: 32.1, purchaseDate: ago(18), expectedLifetimeMonths: 48)

        let oldPhone = Item(name: "iPhone 13", brand: "Apple", category: .phone, price: 25_900, currencyCode: "TWD", purchaseDate: ago(48), expectedLifetimeMonths: 36)
        oldPhone.retiredDate = ago(9)
        oldPhone.resaleValue = 8_000

        return [iphone, mac, scooter, bike, cooker, vacuum, mattress, chair, desk, shoes, jacket, glasses, keyboard, oldPhone]
    }
}

/// SplitMix64: the same "random" ledger on every seed, so screenshots are repeatable.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(in: 0...1) < probability
    }

    mutating func pick<T>(_ options: [T]) -> T {
        options[Int(next() % UInt64(options.count))]
    }
}
#endif
