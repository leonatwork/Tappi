import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable {
    case system, english, german

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        guard self == .system else { return self }
        let supported = Bundle.preferredLocalizations(from: ["en", "de"],
                                                      forPreferences: preferredLanguages).first
        return supported == "de" ? .german : .english
    }

    func text(_ english: String, _ german: String) -> String {
        resolved() == .german ? german : english
    }
}
