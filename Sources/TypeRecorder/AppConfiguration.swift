import Foundation

enum AppSettingsKeys {
    static let dailyResetEnabled = "TypeRecorder.Settings.isDailyResetEnabled"
    static let excludesFunctionalKeysFromStatistics = "TypeRecorder.Settings.excludesFunctionalKeysFromStatistics"
    static let includesEscapeReturnDeleteInStatistics = "TypeRecorder.Settings.includesEscapeReturnDeleteInStatistics"
    static let hidesDockIcon = "TypeRecorder.Settings.hidesDockIcon"
}

enum AppWindowID {
    static let main = "TypeRecorder.MainWindow"
}

extension Notification.Name {
    static let typeRecorderHideDockIconPreferenceDidChange = Notification.Name("TypeRecorder.Settings.hideDockIconPreferenceDidChange")
}
