import Foundation
import SwiftUI

enum SidebarRoute: String, CaseIterable, Identifiable {
    case dashboard
    case keyboard
    case keyboard3D
    case events
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .keyboard: "键盘热力图"
        case .keyboard3D: "3D键盘热力图"
        case .events: "事件明细"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .keyboard: "keyboard"
        case .keyboard3D: "cube.transparent"
        case .events: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

enum CharacterKind: String, Codable, CaseIterable {
    case chinese
    case english
    case digit
    case space
    case punctuation
    case special

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "英文"
        case .digit: "数字"
        case .space: "空格"
        case .punctuation: "标点"
        case .special: "功能键"
        }
    }
}

struct KeystrokeCapture: Sendable {
    let sequence: Int64
    let timestamp: Date
    let keyCode: Int
    let keyName: String
    let keyCharacter: String?
    let intervalMilliseconds: Int?

    var isDeleteKey: Bool {
        keyName == "Key.backspace" || keyName == "Key.delete"
    }

    var frequencyKey: String {
        keyCharacter?.isEmpty == false ? keyCharacter! : keyName
    }

    var characterKind: CharacterKind {
        CharacterClassifier.kind(for: keyCharacter)
    }
}

struct RealtimeStats: Equatable, Sendable {
    var sessionID: String
    var keystrokesCount: Int
    var charactersCount: Int
    var deletedCount: Int
    var validInputCount: Int
    var startedAt: Date

    static let empty = RealtimeStats(
        sessionID: "",
        keystrokesCount: 0,
        charactersCount: 0,
        deletedCount: 0,
        validInputCount: 0,
        startedAt: .now
    )
}

struct DailyStats: Identifiable, Equatable, Sendable {
    var id: String { date }
    let date: String
    let totalKeystrokes: Int
    let totalCharacters: Int
    let totalDeletes: Int
    let totalSessions: Int
}

struct WordFrequencyItem: Identifiable, Equatable, Sendable {
    var id: String { "\(word)-\(type.rawValue)" }
    let word: String
    let type: CharacterKind
    let count: Int
    let lastUsed: Date?

    var displayWord: String {
        KeyNameMapper.displayName(for: word)
    }
}

struct ApplicationUsageItem: Identifiable, Equatable, Sendable {
    var id: String { applicationName }
    let applicationName: String
    let keystrokes: Int
    let characters: Int
    let activeSeconds: Int
    let lastWindowTitle: String
}

struct KeystrokeEventItem: Identifiable, Equatable, Sendable {
    let id: Int64
    let timestamp: Date
    let keyCode: Int
    let keyName: String
    let keyCharacter: String?
    let application: String
    let windowTitle: String
    let intervalMilliseconds: Int?
    let characterKind: CharacterKind

    var displayKey: String {
        KeyNameMapper.displayName(for: keyCharacter?.isEmpty == false ? keyCharacter! : keyName)
    }
}

struct AppSnapshot: Equatable, Sendable {
    var realtime: RealtimeStats = .empty
    var daily: DailyStats = DailyStats(
        date: DateFormatter.typeRecorderDay.string(from: .now),
        totalKeystrokes: 0,
        totalCharacters: 0,
        totalDeletes: 0,
        totalSessions: 0
    )
    var frequencies: [WordFrequencyItem] = []
    var applications: [ApplicationUsageItem] = []
    var events: [KeystrokeEventItem] = []
}

enum StatisticsScope: Sendable {
    case today
    case allDates
}

struct StatisticsFilter: Equatable, Sendable {
    var excludesFunctionalKeys: Bool
    var includesEscapeReturnDelete: Bool

    static let none = StatisticsFilter(
        excludesFunctionalKeys: false,
        includesEscapeReturnDelete: false
    )
}

enum DataClearScope: Sendable {
    case today
    case all
}

enum CharacterClassifier {
    static func kind(for character: String?) -> CharacterKind {
        guard let character, let scalar = character.unicodeScalars.first else {
            return .special
        }
        if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
            return .chinese
        }
        if CharacterSet.letters.contains(scalar) {
            return .english
        }
        if CharacterSet.decimalDigits.contains(scalar) {
            return .digit
        }
        if character == " " {
            return .space
        }
        if ".,!?;:'\"()-[]{}\\/".contains(character) {
            return .punctuation
        }
        return .special
    }
}

enum KeyNameMapper {
    private static let map: [String: String] = [
        "Key.backspace": "Delete",
        "Key.delete": "Delete",
        "Key.enter": "Return",
        "Key.return": "Return",
        "Key.tab": "Tab",
        "Key.space": "Space",
        "Key.esc": "Esc",
        "Key.escape": "Esc",
        "Key.shift": "Shift",
        "Key.shift_r": "Shift",
        "Key.ctrl": "Control",
        "Key.ctrl_r": "Control",
        "Key.cmd": "Command",
        "Key.cmd_r": "Command",
        "Key.alt": "Option",
        "Key.alt_r": "Option",
        "Key.fn": "fn",
        "Key.caps_lock": "Caps Lock",
        "Key.up": "↑",
        "Key.down": "↓",
        "Key.left": "←",
        "Key.right": "→",
        "Key.page_up": "PgUp",
        "Key.page_down": "PgDn"
    ]

    static func displayName(for key: String) -> String {
        if let value = map[key] {
            return value
        }
        if key.hasPrefix("Key.f"), let number = Int(key.dropFirst("Key.f".count)) {
            return "F\(number)"
        }
        if key == " " {
            return "Space"
        }
        if key.hasPrefix("Key.") {
            let name = key.dropFirst(4)
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return key
    }
}

extension DateFormatter {
    static let typeRecorderDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let typeRecorderTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension Int {
    var durationText: String {
        if self < 60 {
            return "\(self)秒"
        }
        let minutes = self / 60
        let seconds = self % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)分钟" : "\(minutes)分\(seconds)秒"
        }
        let hours = minutes / 60
        return "\(hours)小时\(minutes % 60)分钟"
    }
}
