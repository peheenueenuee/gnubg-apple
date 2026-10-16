import Foundation
import GNUbgNative

func runLocalizationSmoke() {
    func table(_ language: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language),
              let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { fatalError("Missing localization table: \(language)") }
        return table
    }
    let english = table("en"), japanese = table("ja")
    precondition(Set(english.keys) == Set(japanese.keys), "Localization keys differ")
    let regex = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?([duf@])"#)
    func arguments(_ text: String) -> [Int: String] {
        let string = text as NSString
        var result: [Int: String] = [:]
        for (index, match) in regex.matches(in: text, range: NSRange(location: 0, length: string.length)).enumerated() {
            let position = match.range(at: 1).location == NSNotFound ? index + 1 : Int(string.substring(with: match.range(at: 1)))!
            result[position] = string.substring(with: match.range(at: 2))
        }
        return result
    }
    for key in english.keys {
        precondition(arguments(english[key]!) == arguments(japanese[key]!), "Format arguments differ: \(key)")
        precondition(L10n.text(key) != key, "Unresolved localization key: \(key)")
    }
    let preferred = Bundle.main.preferredLocalizations.first ?? "en"
    if let index = CommandLine.arguments.firstIndex(of: "--expect-language") {
        precondition(index + 1 < CommandLine.arguments.count)
        precondition(preferred == CommandLine.arguments[index + 1], "Unexpected selected localization: \(preferred)")
    }
    let ja = preferred == "ja"
    precondition(L10n.text("game.roll") == (ja ? "サイコロを振る" : "Roll dice"))
    precondition(L10n.text("board.point_accessibility", 24, 3, L10n.player(0)) ==
        (ja ? "24ポイント、白の駒3個" : "Point 24, 3 Ivory checkers"))
    let trialText = L10n.text("analysis.completed_trials", UInt32(1296))
    let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: 1296), number: .decimal)
    precondition(trialText == (ja ? "試行回数 \(formattedCount)回" : "Trials: \(formattedCount)"), "Unexpected trial text: \(trialText)")
    precondition(L10n.text("cube.value", UInt16(64)) == (ja ? "キューブ 64" : "Cube 64"))
    precondition(Step(from: 24, to: -1).label == (ja ? "バー/上がり" : "Bar/Off"))
    precondition(L10n.result(GNUBG_NATIVE_NOT_READY) == L10n.text("error.not_ready"))
    print("Localization smoke OK: \(preferred), \(english.count) keys, interpolation, accessibility, move labels, errors")
}
