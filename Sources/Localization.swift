import Foundation

func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
}

func trf(_ key: String, _ arguments: CVarArg...) -> String {
    let format = tr(key)
    return String(format: format, locale: Locale.current, arguments: arguments)
}

enum BarPocketLocalization {
    static func validateResources() -> Bool {
        let requiredKeys = ["menu.notch_blackout", "manager.title", "help.message"]
        for language in ["en", "zh-Hans", "zh-Hant", "es", "ko", "ja", "de", "fr", "nl"] {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                fputs("Missing localization bundle: \(language)\n", stderr)
                return false
            }
            for key in requiredKeys {
                let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                guard !value.isEmpty, value != key else {
                    fputs("Missing localization key \(key) in \(language)\n", stderr)
                    return false
                }
            }
        }
        return true
    }
}
