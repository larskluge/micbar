import Foundation
import Combine

struct Language: Hashable, Identifiable {
    let name: String
    let flag: String
    var id: String { name }
}

class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    private let key = "selectedLanguages"
    private let defaultLanguages = ["English", "German"]

    @Published var selectedLanguages: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedLanguages).sorted(), forKey: key)
        }
    }

    /// All languages with flag emoji, sorted alphabetically.
    static let allLanguages: [Language] = [
        Language(name: "Afrikaans", flag: "🇿🇦"), Language(name: "Albanian", flag: "🇦🇱"),
        Language(name: "Amharic", flag: "🇪🇹"), Language(name: "Arabic", flag: "🇸🇦"),
        Language(name: "Armenian", flag: "🇦🇲"), Language(name: "Azerbaijani", flag: "🇦🇿"),
        Language(name: "Basque", flag: "🇪🇸"), Language(name: "Belarusian", flag: "🇧🇾"),
        Language(name: "Bengali", flag: "🇧🇩"), Language(name: "Bosnian", flag: "🇧🇦"),
        Language(name: "Bulgarian", flag: "🇧🇬"), Language(name: "Burmese", flag: "🇲🇲"),
        Language(name: "Catalan", flag: "🇪🇸"), Language(name: "Cebuano", flag: "🇵🇭"),
        Language(name: "Chinese", flag: "🇨🇳"), Language(name: "Croatian", flag: "🇭🇷"),
        Language(name: "Czech", flag: "🇨🇿"), Language(name: "Danish", flag: "🇩🇰"),
        Language(name: "Dutch", flag: "🇳🇱"), Language(name: "English", flag: "🇬🇧"),
        Language(name: "Estonian", flag: "🇪🇪"), Language(name: "Filipino", flag: "🇵🇭"),
        Language(name: "Finnish", flag: "🇫🇮"), Language(name: "French", flag: "🇫🇷"),
        Language(name: "Galician", flag: "🇪🇸"), Language(name: "Georgian", flag: "🇬🇪"),
        Language(name: "German", flag: "🇩🇪"), Language(name: "Greek", flag: "🇬🇷"),
        Language(name: "Gujarati", flag: "🇮🇳"), Language(name: "Haitian Creole", flag: "🇭🇹"),
        Language(name: "Hausa", flag: "🇳🇬"), Language(name: "Hebrew", flag: "🇮🇱"),
        Language(name: "Hindi", flag: "🇮🇳"), Language(name: "Hungarian", flag: "🇭🇺"),
        Language(name: "Icelandic", flag: "🇮🇸"), Language(name: "Igbo", flag: "🇳🇬"),
        Language(name: "Indonesian", flag: "🇮🇩"), Language(name: "Irish", flag: "🇮🇪"),
        Language(name: "Italian", flag: "🇮🇹"), Language(name: "Japanese", flag: "🇯🇵"),
        Language(name: "Javanese", flag: "🇮🇩"), Language(name: "Kannada", flag: "🇮🇳"),
        Language(name: "Kazakh", flag: "🇰🇿"), Language(name: "Khmer", flag: "🇰🇭"),
        Language(name: "Korean", flag: "🇰🇷"), Language(name: "Kurdish", flag: "🇮🇶"),
        Language(name: "Kyrgyz", flag: "🇰🇬"), Language(name: "Lao", flag: "🇱🇦"),
        Language(name: "Latvian", flag: "🇱🇻"), Language(name: "Lithuanian", flag: "🇱🇹"),
        Language(name: "Luxembourgish", flag: "🇱🇺"), Language(name: "Macedonian", flag: "🇲🇰"),
        Language(name: "Malay", flag: "🇲🇾"), Language(name: "Malayalam", flag: "🇮🇳"),
        Language(name: "Maltese", flag: "🇲🇹"), Language(name: "Maori", flag: "🇳🇿"),
        Language(name: "Marathi", flag: "🇮🇳"), Language(name: "Mongolian", flag: "🇲🇳"),
        Language(name: "Nepali", flag: "🇳🇵"), Language(name: "Norwegian", flag: "🇳🇴"),
        Language(name: "Pashto", flag: "🇦🇫"), Language(name: "Persian", flag: "🇮🇷"),
        Language(name: "Polish", flag: "🇵🇱"), Language(name: "Portuguese", flag: "🇵🇹"),
        Language(name: "Punjabi", flag: "🇮🇳"), Language(name: "Romanian", flag: "🇷🇴"),
        Language(name: "Russian", flag: "🇷🇺"), Language(name: "Samoan", flag: "🇼🇸"),
        Language(name: "Serbian", flag: "🇷🇸"), Language(name: "Sesotho", flag: "🇱🇸"),
        Language(name: "Shona", flag: "🇿🇼"), Language(name: "Sindhi", flag: "🇵🇰"),
        Language(name: "Sinhala", flag: "🇱🇰"), Language(name: "Slovak", flag: "🇸🇰"),
        Language(name: "Slovenian", flag: "🇸🇮"), Language(name: "Somali", flag: "🇸🇴"),
        Language(name: "Spanish", flag: "🇪🇸"), Language(name: "Sundanese", flag: "🇮🇩"),
        Language(name: "Swahili", flag: "🇰🇪"), Language(name: "Swedish", flag: "🇸🇪"),
        Language(name: "Tajik", flag: "🇹🇯"), Language(name: "Tamil", flag: "🇮🇳"),
        Language(name: "Tatar", flag: "🇷🇺"), Language(name: "Telugu", flag: "🇮🇳"),
        Language(name: "Thai", flag: "🇹🇭"), Language(name: "Turkish", flag: "🇹🇷"),
        Language(name: "Turkmen", flag: "🇹🇲"), Language(name: "Ukrainian", flag: "🇺🇦"),
        Language(name: "Urdu", flag: "🇵🇰"), Language(name: "Uzbek", flag: "🇺🇿"),
        Language(name: "Vietnamese", flag: "🇻🇳"), Language(name: "Welsh", flag: "🏴󠁧󠁢󠁷󠁬󠁳󠁿"),
        Language(name: "Xhosa", flag: "🇿🇦"), Language(name: "Yiddish", flag: "🇮🇱"),
        Language(name: "Yoruba", flag: "🇳🇬"), Language(name: "Zulu", flag: "🇿🇦"),
    ]

    /// Lookup flag by language name.
    static let flagForLanguage: [String: String] = {
        Dictionary(allLanguages.map { ($0.name, $0.flag) }, uniquingKeysWith: { first, _ in first })
    }()

    init() {
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            self.selectedLanguages = Set(saved)
        } else {
            self.selectedLanguages = Set(defaultLanguages)
        }
    }

    /// Selected languages sorted in the order they appear in allLanguages.
    var orderedSelectedLanguages: [Language] {
        Self.allLanguages.filter { selectedLanguages.contains($0.name) }
    }

    func toggle(_ language: String) {
        if selectedLanguages.contains(language) {
            selectedLanguages.remove(language)
        } else {
            selectedLanguages.insert(language)
        }
    }
}
