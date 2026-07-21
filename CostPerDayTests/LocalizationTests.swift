import Testing
import Foundation
@testable import CostPerDay

/// Guards the localisation pipeline. These catch the two ways localisation silently
/// rots: a language stops being bundled, or a string is added to the code without a
/// translation and falls back to English everywhere.
@Suite("Localization")
struct LocalizationTests {
    /// Must match `knownRegions` in the project file and the languages built by
    /// `Localization/build_catalog.py`.
    static let expectedLanguages = [
        "en", "zh-Hant", "zh-Hans", "ja", "ko", "id",
        "es", "fr", "de", "pt-BR", "ru", "vi",
    ]

    @Test("Every expected language is bundled with the app")
    func allLanguagesAreBundled() {
        let bundled = Set(Bundle.main.localizations)
        for language in Self.expectedLanguages {
            #expect(bundled.contains(language), "\(language) is missing from the app bundle")
        }
    }

    @Test("Each language bundle actually resolves a known string")
    func eachLanguageResolvesStrings() throws {
        for language in Self.expectedLanguages {
            let path = try #require(
                Bundle.main.path(forResource: language, ofType: "lproj"),
                "no \(language).lproj in the bundle"
            )
            let bundle = try #require(Bundle(path: path))
            let value = bundle.localizedString(forKey: "Base currency", value: nil, table: nil)
            #expect(value != "Base currency" || language == "en",
                    "\(language) fell back to the English source string")
            #expect(!value.isEmpty)
        }
    }

    @Test("Category and sector names are translated in every language")
    func modelLabelsAreTranslated() throws {
        // These come from String(localized:) in model code rather than SwiftUI Text,
        // so they are the ones most easily missed when adding a new case.
        let samples = ["Phone", "Electronics", "Bed & Mattress", "Transport, Sport & Hobby"]
        for language in Self.expectedLanguages where language != "en" {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in samples {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value != key, "\(language) is missing a translation for \(key)")
            }
        }
    }

    @Test("Plural-aware durations read correctly at one and many")
    func pluralsResolve() {
        #expect(Duration.fromDays(1) == "1 day")
        #expect(Duration.fromDays(45) == "45 days")
        #expect(Duration.fromMonths(1) == "1 month")
        #expect(Duration.fromMonths(18) == "18 months")
    }
}
