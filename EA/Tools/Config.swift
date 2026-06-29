import Foundation

enum Config {
    static let supabaseURL: String = value(for: "SUPABASE_URL")
    static let supabaseAnonKey: String = value(for: "SUPABASE_ANON_KEY")
    static let openAIAPIKey: String = value(for: "OPENAI_API_KEY")
    static let openAIHost: String = value(for: "OPENAI_HOST")
    static let openAIBasePath: String = value(for: "OPENAI_BASE_PATH")

    private static func value(for key: String) -> String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let value = dict[key] as? String, !value.isEmpty
        else {
            fatalError("Missing \(key) in Secrets.plist. Copy Secrets.plist.sample to Secrets.plist and fill in real values.")
        }
        return value
    }
}
