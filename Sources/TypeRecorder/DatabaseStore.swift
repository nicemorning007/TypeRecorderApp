import Foundation

enum DatabaseError: Error, LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let message): "数据读取失败：\(message)"
        case .writeFailed(let message): "数据写入失败：\(message)"
        case .decodeFailed(let message): "数据解析失败：\(message)"
        }
    }
}

final class DatabaseStore: @unchecked Sendable {
    private let storageDirectory: URL
    private let eventsDirectory: URL
    private let sessionsURL: URL
    private let currentSessionID: String
    private let sessionStartTime: Date
    private let lock = NSLock()
    private var currentSession: StoredTypingSession
    private var nextEventID: Int64
    private var eventsByDate: [String: [StoredKeystrokeEvent]] = [:]
    private var sessionsCache: [StoredTypingSession] = []
    private var eventFileHandles: [String: FileHandle] = [:]
    private var pendingEventDataByDate: [String: Data] = [:]
    private var pendingEventCount = 0
    private var lastEventFlushTime = Date()
    private var sessionDirtyCount = 0
    private var lastSessionPersistTime = Date.distantPast

    init() throws {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TypeRecorder", isDirectory: true)

        storageDirectory = supportDirectory
        eventsDirectory = supportDirectory.appendingPathComponent("events", isDirectory: true)
        sessionsURL = supportDirectory.appendingPathComponent("sessions.json")
        currentSessionID = UUID().uuidString
        sessionStartTime = .now
        currentSession = StoredTypingSession(
            sessionID: currentSessionID,
            startTime: sessionStartTime,
            endTime: nil,
            durationSeconds: 0,
            totalKeystrokes: 0,
            totalCharacters: 0,
            totalBackspaces: 0,
            totalDeletes: 0,
            inputMethodUsage: [:],
            isActive: true,
            createdAt: sessionStartTime
        )

        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let loadedEvents = try Self.loadEventCache(from: eventsDirectory)
        eventsByDate = loadedEvents.eventsByDate
        nextEventID = loadedEvents.nextEventID
        sessionsCache = try Self.loadSessions(from: sessionsURL)
        try upsertCurrentSession()
    }

    deinit {
        try? flushPendingEventData(force: true)
        try? upsertCurrentSessionIfNeeded(force: true)
        for handle in eventFileHandles.values {
            try? handle.close()
        }
    }

    var path: String {
        storageDirectory.path
    }

    var sessionID: String {
        currentSessionID
    }

    var startedAt: Date {
        sessionStartTime
    }

    func record(_ capture: KeystrokeCapture) throws {
        lock.lock()
        defer { lock.unlock() }

        let event = StoredKeystrokeEvent(
            id: nextEventID,
            // 展示顺序必须使用存储层全局递增 id。记录器里的 sequence 每次启动都会重置，
            // 如果拿它和历史数据混排，新输入会被旧记录压住，最近输入看起来就不会刷新。
            sequence: nextEventID,
            timestamp: capture.timestamp,
            date: DateFormatter.typeRecorderDay.string(from: capture.timestamp),
            keyCode: capture.keyCode,
            keyName: capture.keyName,
            keyCharacter: capture.keyCharacter,
            inputMethod: "",
            application: "",
            windowTitle: "",
            intervalMilliseconds: capture.intervalMilliseconds,
            sessionID: currentSessionID,
            isPrintable: true,
            characterKind: capture.characterKind
        )
        nextEventID += 1

        // 先写内存，再批量落盘。界面统计读取内存缓存，所以不需要每个按键都同步写磁盘。
        try bufferJSONLine(event, date: event.date)
        eventsByDate[event.date, default: []].append(event)

        currentSession.endTime = capture.timestamp
        currentSession.durationSeconds = max(0, Int(capture.timestamp.timeIntervalSince(sessionStartTime)))
        currentSession.totalKeystrokes += 1
        currentSession.totalCharacters += 1
        currentSession.totalBackspaces += capture.keyName == "Key.backspace" ? 1 : 0
        currentSession.totalDeletes += capture.keyName == "Key.delete" ? 1 : 0
        try upsertCurrentSessionIfNeeded(force: false)
    }

    func snapshot(scope: StatisticsScope = .today, filter: StatisticsFilter = .none) throws -> AppSnapshot {
        lock.lock()
        defer { lock.unlock() }
        try flushPendingEventData(force: true)
        try upsertCurrentSessionIfNeeded(force: true)

        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let today = DateFormatter.typeRecorderDay.string(from: now)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = DateFormatter.typeRecorderDay.string(from: yesterdayDate)
        let scopedEvents: [StoredKeystrokeEvent]
        let scopedSessions: [StoredTypingSession]
        let statsDateLabel: String

        switch scope {
        case .today:
            // 每日重置只影响统计口径：底层事件依然按 yyyy-MM-dd 文件分天保存。
            scopedEvents = eventsByDate[today, default: []]
            scopedSessions = sessionsCache.filter {
                DateFormatter.typeRecorderDay.string(from: $0.startTime) == today
            }
            statsDateLabel = today
        case .allDates:
            // 关闭每日重置时不改写历史数据，只把所有日期的事件合并后再计算展示统计。
            scopedEvents = eventsByDate
                .keys
                .sorted()
                .flatMap { eventsByDate[$0, default: []] }
            scopedSessions = sessionsCache
            statsDateLabel = "累计"
        }

        // 过滤只服务统计展示。scopedEvents 仍然保留完整原始记录，用于“最近输入”和“事件明细”，
        // 避免设置开关反过来影响真实数据留存或用户回看明细。
        let statisticalEvents = eventsForStatistics(scopedEvents, filter: filter)
        // 今日称号只看自然日当天的数据。即使用户关闭“每日 0 时自动重置统计”，
        // 这里也不能使用 scopedEvents，否则称号会被累计历史按键量直接顶到最高等级。
        let todayStatisticalEvents = eventsForStatistics(eventsByDate[today, default: []], filter: filter)
        // 分时统计固定比较今天和昨天的自然日小时分布，不跟随“每日重置”开关切到累计数据。
        // 这里仍然复用统计过滤设置，保证“排除功能键”等用户选择对所有统计图表保持一致。
        let yesterdayStatisticalEvents = eventsForStatistics(eventsByDate[yesterday, default: []], filter: filter)

        return AppSnapshot(
            realtime: realtimeStats(for: statsDateLabel, events: statisticalEvents),
            daily: dailyStats(for: statsDateLabel, events: statisticalEvents, sessions: scopedSessions),
            todayKeystrokesCount: todayStatisticalEvents.count,
            hourlyKeystrokes: hourlyKeystrokes(events: todayStatisticalEvents),
            yesterdayHourlyKeystrokes: hourlyKeystrokes(events: yesterdayStatisticalEvents),
            frequencies: wordFrequency(limit: 300, events: statisticalEvents),
            applications: [],
            events: recentEvents(limit: 250, events: scopedEvents)
        )
    }

    func realtimeStats(for date: String) throws -> RealtimeStats {
        lock.lock()
        defer { lock.unlock() }
        return realtimeStats(for: date, events: eventsByDate[date, default: []])
    }

    func dailyStats(for date: String) throws -> DailyStats {
        lock.lock()
        defer { lock.unlock() }
        return dailyStats(for: date, events: eventsByDate[date, default: []])
    }

    func wordFrequency(limit: Int, date: String) throws -> [WordFrequencyItem] {
        lock.lock()
        defer { lock.unlock() }
        return wordFrequency(limit: limit, events: eventsByDate[date, default: []])
    }

    func applicationUsage(date: String) throws -> [ApplicationUsageItem] {
        lock.lock()
        defer { lock.unlock() }
        return applicationUsage(events: eventsByDate[date, default: []])
    }

    func recentEvents(limit: Int) throws -> [KeystrokeEventItem] {
        lock.lock()
        defer { lock.unlock() }
        let events = eventsByDate
            .keys
            .sorted(by: >)
            .prefix(7)
            .flatMap { eventsByDate[$0, default: []] }
        return recentEvents(limit: limit, events: events)
    }

    func clearData(_ scope: DataClearScope) throws {
        lock.lock()
        defer { lock.unlock() }

        let today = DateFormatter.typeRecorderDay.string(from: .now)

        switch scope {
        case .today:
            // 清除今日数据只处理今天的事件文件和内存缓存，其他日期文件保持原样。
            pendingEventDataByDate.removeValue(forKey: today)
            closeEventFileHandle(for: today)
            eventsByDate.removeValue(forKey: today)
            try removeFileIfExists(eventFileURL(for: today))

            sessionsCache.removeAll { session in
                session.sessionID != currentSessionID
                    && DateFormatter.typeRecorderDay.string(from: session.startTime) == today
            }
        case .all:
            // 清除全部历史时关闭所有文件句柄，避免后续写入继续落到已删除的旧文件句柄里。
            pendingEventDataByDate.removeAll(keepingCapacity: true)
            closeAllEventFileHandles()
            eventsByDate.removeAll(keepingCapacity: true)
            for file in try eventFiles() {
                try removeFileIfExists(file)
            }

            sessionsCache.removeAll { $0.sessionID != currentSessionID }
        }

        pendingEventCount = pendingEventDataByDate.values.reduce(0) { count, data in
            count + data.split(separator: UInt8(ascii: "\n")).count
        }
        nextEventID = nextAvailableEventID()
        rebuildCurrentSessionFromRemainingEvents()
        try upsertCurrentSession()
    }

    private func realtimeStats(for date: String, events: [StoredKeystrokeEvent]) -> RealtimeStats {
        let keystrokes = events.count
        let characters = events.filter(\.isPrintable).count
        let deletes = events.filter(\.isDeleteKey).count
        return RealtimeStats(
            sessionID: currentSessionID,
            keystrokesCount: keystrokes,
            charactersCount: characters,
            deletedCount: deletes,
            validInputCount: max(0, characters - deletes),
            startedAt: sessionStartTime
        )
    }

    private func dailyStats(
        for date: String,
        events: [StoredKeystrokeEvent],
        sessions: [StoredTypingSession]
    ) -> DailyStats {
        return DailyStats(
            date: date,
            totalKeystrokes: events.count,
            totalCharacters: events.filter(\.isPrintable).count,
            totalDeletes: events.filter(\.isDeleteKey).count,
            totalSessions: sessions.count
        )
    }

    private func dailyStats(for date: String, events: [StoredKeystrokeEvent]) -> DailyStats {
        let sessions = sessionsCache.filter {
            DateFormatter.typeRecorderDay.string(from: $0.startTime) == date
        }
        return dailyStats(for: date, events: events, sessions: sessions)
    }

    private func hourlyKeystrokes(events: [StoredKeystrokeEvent]) -> [HourlyKeystrokeItem] {
        // 小时统计必须基于传进来的自然日 events，而不是直接读取 scopedEvents。
        // 这样分时统计不会被“每日重置”开关影响；调用方负责传入今天或昨天的数据。
        let calendar = Calendar.autoupdatingCurrent
        var countsByHour = Array(repeating: 0, count: 24)

        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            guard countsByHour.indices.contains(hour) else {
                continue
            }
            countsByHour[hour] += 1
        }

        return countsByHour.indices.map { hour in
            // 0 点没有同一天内的上一小时，所以把上一小时按 0 处理；
            // 这样趋势变化表达的是“从当天开始到当前小时”的自然增量，而不是跨天回绕。
            let previousHourCount = hour == 0 ? 0 : countsByHour[hour - 1]
            return HourlyKeystrokeItem(
                hour: hour,
                count: countsByHour[hour],
                previousHourCount: previousHourCount
            )
        }
    }

    private func eventsForStatistics(
        _ events: [StoredKeystrokeEvent],
        filter: StatisticsFilter
    ) -> [StoredKeystrokeEvent] {
        guard filter.excludesFunctionalKeys else {
            return events
        }

        return events.filter { event in
            // 这个附加开关只在“排除功能键”开启时生效：
            // 用户可以排除空格和修饰键，同时仍把 Esc / Return / Delete 算进统计。
            if filter.includesEscapeReturnDelete, event.isEscapeReturnOrDeleteStatisticsKey {
                return true
            }
            return !event.isExcludedFunctionalStatisticsKey
        }
    }

    private func wordFrequency(limit: Int, events: [StoredKeystrokeEvent]) -> [WordFrequencyItem] {
        Dictionary(grouping: events) { event in
            FrequencyKey(word: event.frequencyKey, type: event.characterKind)
        }
        .map { key, events in
            WordFrequencyItem(
                word: key.word,
                type: key.type,
                count: events.count,
                lastUsed: events.last?.timestamp
            )
        }
        .sorted {
            if $0.count == $1.count {
                return $0.displayWord < $1.displayWord
            }
            return $0.count > $1.count
        }
        .prefix(limit)
        .map { $0 }
    }

    private func applicationUsage(events: [StoredKeystrokeEvent]) -> [ApplicationUsageItem] {
        Dictionary(grouping: events, by: \.application)
            .map { applicationName, events in
                ApplicationUsageItem(
                    applicationName: applicationName,
                    keystrokes: events.count,
                    characters: events.filter(\.isPrintable).count,
                    activeSeconds: events.reduce(0) { total, event in
                        total + min(max((event.intervalMilliseconds ?? 0) / 1000, 0), 30)
                    },
                    lastWindowTitle: events.last?.windowTitle ?? ""
                )
            }
            .sorted { $0.keystrokes > $1.keystrokes }
    }

    private func recentEvents(limit: Int, events: [StoredKeystrokeEvent]) -> [KeystrokeEventItem] {
        events
            .sorted { lhs, rhs in
                lhs.id > rhs.id
            }
            .prefix(limit)
            .map { $0.item }
    }

    private func eventFileURL(for date: String) -> URL {
        eventsDirectory.appendingPathComponent("\(date).jsonl")
    }

    private func eventFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: eventsDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
    }

    private func readEvents(from url: URL) throws -> [StoredKeystrokeEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            return try decodeEventObjects(from: raw, fileName: url.lastPathComponent)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.readFailed("\(url.path)：\(error.localizedDescription)")
        }
    }

    private func bufferJSONLine<T: Encodable>(_ value: T, date: String) throws {
        do {
            let data = try JSONEncoder.typeRecorderLine.encode(value)
            pendingEventDataByDate[date, default: Data()].append(data)
            pendingEventDataByDate[date]?.append(Data("\n".utf8))
            pendingEventCount += 1
            try flushPendingEventData(force: false)
        } catch let error as DatabaseError {
            throw error
        } catch {
            throw DatabaseError.writeFailed("\(date).jsonl：\(error.localizedDescription)")
        }
    }

    private func flushPendingEventData(force: Bool) throws {
        let shouldFlush = force
            || pendingEventCount >= 200
            || Date().timeIntervalSince(lastEventFlushTime) >= 10

        guard shouldFlush, !pendingEventDataByDate.isEmpty else {
            return
        }

        do {
            for (date, data) in pendingEventDataByDate {
                let url = eventFileURL(for: date)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try eventFileHandle(for: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
            pendingEventDataByDate.removeAll(keepingCapacity: true)
            pendingEventCount = 0
            lastEventFlushTime = Date()
        } catch {
            throw DatabaseError.writeFailed("事件批量落盘失败：\(error.localizedDescription)")
        }
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try JSONEncoder.typeRecorderLine.encode(value)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try eventFileHandle(for: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        } catch {
            throw DatabaseError.writeFailed("\(url.path)：\(error.localizedDescription)")
        }
    }

    private func upsertCurrentSession() throws {
        if let index = sessionsCache.firstIndex(where: { $0.sessionID == currentSessionID }) {
            sessionsCache[index] = currentSession
        } else {
            sessionsCache.append(currentSession)
        }
        try persistSessions()
        lastSessionPersistTime = Date()
        sessionDirtyCount = 0
    }

    private func upsertCurrentSessionIfNeeded(force: Bool) throws {
        if let index = sessionsCache.firstIndex(where: { $0.sessionID == currentSessionID }) {
            sessionsCache[index] = currentSession
        } else {
            sessionsCache.append(currentSession)
        }

        sessionDirtyCount += 1
        let shouldPersist = force
            || sessionDirtyCount >= 50
            || Date().timeIntervalSince(lastSessionPersistTime) >= 3

        guard shouldPersist else {
            return
        }
        try persistSessions()
        lastSessionPersistTime = Date()
        sessionDirtyCount = 0
    }

    private func persistSessions() throws {
        do {
            let data = try JSONEncoder.typeRecorder.encode(sessionsCache)
            try data.write(to: sessionsURL, options: [.atomic])
        } catch {
            throw DatabaseError.writeFailed("\(sessionsURL.path)：\(error.localizedDescription)")
        }
    }

    private func eventFileHandle(for url: URL) throws -> FileHandle {
        let date = url.deletingPathExtension().lastPathComponent
        if let handle = eventFileHandles[date] {
            return handle
        }
        let handle = try FileHandle(forWritingTo: url)
        eventFileHandles[date] = handle
        return handle
    }

    private func closeEventFileHandle(for date: String) {
        guard let handle = eventFileHandles.removeValue(forKey: date) else {
            return
        }
        try? handle.close()
    }

    private func closeAllEventFileHandles() {
        for handle in eventFileHandles.values {
            try? handle.close()
        }
        eventFileHandles.removeAll(keepingCapacity: true)
    }

    private func removeFileIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw DatabaseError.writeFailed("\(url.path)：\(error.localizedDescription)")
        }
    }

    private func nextAvailableEventID() -> Int64 {
        let maxID = eventsByDate.values
            .flatMap { $0 }
            .map(\.id)
            .max() ?? 0
        return maxID + 1
    }

    private func rebuildCurrentSessionFromRemainingEvents() {
        let currentSessionEvents = eventsByDate.values
            .flatMap { $0 }
            .filter { $0.sessionID == currentSessionID }
            .sorted { $0.timestamp < $1.timestamp }

        currentSession.endTime = currentSessionEvents.last?.timestamp
        currentSession.durationSeconds = currentSessionEvents.last.map {
            max(0, Int($0.timestamp.timeIntervalSince(sessionStartTime)))
        } ?? 0
        currentSession.totalKeystrokes = currentSessionEvents.count
        currentSession.totalCharacters = currentSessionEvents.filter(\.isPrintable).count
        currentSession.totalBackspaces = currentSessionEvents.filter { $0.keyName == "Key.backspace" }.count
        currentSession.totalDeletes = currentSessionEvents.filter(\.isDeleteKey).count
        currentSession.inputMethodUsage = [:]
        currentSession.isActive = true
    }

    private static func loadSessions(from url: URL) throws -> [StoredTypingSession] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.typeRecorder.decode([StoredTypingSession].self, from: data)
        } catch {
            throw DatabaseError.readFailed("\(url.path)：\(error.localizedDescription)")
        }
    }

    private static func loadEventCache(from directory: URL) throws -> (eventsByDate: [String: [StoredKeystrokeEvent]], nextEventID: Int64) {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ([:], 1)
        }

        var eventsByDate: [String: [StoredKeystrokeEvent]] = [:]
        var maxID: Int64 = 0
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }

        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let events = try decodeEventObjects(from: raw, fileName: file.lastPathComponent)
            for event in events {
                eventsByDate[event.date, default: []].append(event)
                maxID = max(maxID, event.id)
            }
        }

        for date in eventsByDate.keys {
            eventsByDate[date]?.sort { lhs, rhs in
                lhs.id < rhs.id
            }
        }

        return (eventsByDate, maxID + 1)
    }
}

private func decodeEventObjects(from raw: String, fileName: String) throws -> [StoredKeystrokeEvent] {
    let chunks = splitTopLevelJSONObjects(raw)
    guard !chunks.isEmpty else {
        return []
    }

    return try chunks.map { chunk in
        guard let data = chunk.data(using: .utf8) else {
            throw DatabaseError.decodeFailed(fileName)
        }
        return try JSONDecoder.typeRecorder.decode(StoredKeystrokeEvent.self, from: data)
    }
}

private func splitTopLevelJSONObjects(_ raw: String) -> [String] {
    var chunks: [String] = []
    var startIndex: String.Index?
    var depth = 0
    var isInsideString = false
    var isEscaped = false

    for index in raw.indices {
        let character = raw[index]

        if isInsideString {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString = false
            }
            continue
        }

        if character == "\"" {
            isInsideString = true
            continue
        }

        if character == "{" {
            if depth == 0 {
                startIndex = index
            }
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0, let objectStart = startIndex {
                chunks.append(String(raw[objectStart...index]))
                startIndex = nil
            }
        }
    }

    return chunks
}

private struct FrequencyKey: Hashable {
    let word: String
    let type: CharacterKind
}

private struct StoredKeystrokeEvent: Codable {
    let id: Int64
    let sequence: Int64
    let timestamp: Date
    let date: String
    let keyCode: Int
    let keyName: String
    let keyCharacter: String?
    let inputMethod: String
    let application: String
    let windowTitle: String
    let intervalMilliseconds: Int?
    let sessionID: String
    let isPrintable: Bool
    let characterKind: CharacterKind

    enum CodingKeys: String, CodingKey {
        case id
        case sequence
        case timestamp
        case date
        case keyCode
        case keyName
        case keyCharacter
        case inputMethod
        case application
        case windowTitle
        case intervalMilliseconds
        case sessionID
        case isPrintable
        case characterKind
    }

    init(
        id: Int64,
        sequence: Int64,
        timestamp: Date,
        date: String,
        keyCode: Int,
        keyName: String,
        keyCharacter: String?,
        inputMethod: String,
        application: String,
        windowTitle: String,
        intervalMilliseconds: Int?,
        sessionID: String,
        isPrintable: Bool,
        characterKind: CharacterKind
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.date = date
        self.keyCode = keyCode
        self.keyName = keyName
        self.keyCharacter = keyCharacter
        self.inputMethod = inputMethod
        self.application = application
        self.windowTitle = windowTitle
        self.intervalMilliseconds = intervalMilliseconds
        self.sessionID = sessionID
        self.isPrintable = isPrintable
        self.characterKind = characterKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        sequence = try container.decodeIfPresent(Int64.self, forKey: .sequence) ?? id
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        date = try container.decode(String.self, forKey: .date)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        keyName = try container.decode(String.self, forKey: .keyName)
        keyCharacter = try container.decodeIfPresent(String.self, forKey: .keyCharacter)
        inputMethod = try container.decodeIfPresent(String.self, forKey: .inputMethod) ?? ""
        application = try container.decodeIfPresent(String.self, forKey: .application) ?? ""
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        intervalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .intervalMilliseconds)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        isPrintable = try container.decode(Bool.self, forKey: .isPrintable)
        characterKind = try container.decode(CharacterKind.self, forKey: .characterKind)
    }

    var frequencyKey: String {
        keyCharacter?.isEmpty == false ? keyCharacter! : keyName
    }

    var isDeleteKey: Bool {
        keyName == "Key.backspace" || keyName == "Key.delete"
    }

    var item: KeystrokeEventItem {
        KeystrokeEventItem(
            id: id,
            timestamp: timestamp,
            keyCode: keyCode,
            keyName: keyName,
            keyCharacter: keyCharacter,
            application: application,
            windowTitle: windowTitle,
            intervalMilliseconds: intervalMilliseconds,
            characterKind: characterKind
        )
    }

    var isEscapeReturnOrDeleteStatisticsKey: Bool {
        Self.escapeReturnDeleteStatisticKeyNames.contains(keyName)
    }

    var isExcludedFunctionalStatisticsKey: Bool {
        if keyCharacter == " " {
            return true
        }
        return Self.excludedFunctionalStatisticKeyNames.contains(keyName)
    }

    // 这里的名单只对应设置文案中列出的键。其他按键仍按原统计口径计算，
    // 避免“排除功能键”误伤未被用户点名的 Tab、方向键或 F1-F12。
    private static let excludedFunctionalStatisticKeyNames: Set<String> = [
        "Key.space",
        "Key.cmd",
        "Key.cmd_r",
        "Key.alt",
        "Key.alt_r",
        "Key.ctrl",
        "Key.ctrl_r",
        "Key.backspace",
        "Key.delete",
        "Key.caps_lock",
        "Key.shift",
        "Key.shift_r",
        "Key.enter",
        "Key.return",
        "Key.esc",
        "Key.escape"
    ]

    private static let escapeReturnDeleteStatisticKeyNames: Set<String> = [
        "Key.backspace",
        "Key.delete",
        "Key.enter",
        "Key.return",
        "Key.esc",
        "Key.escape"
    ]
}

private struct StoredTypingSession: Codable {
    let sessionID: String
    let startTime: Date
    var endTime: Date?
    var durationSeconds: Int
    var totalKeystrokes: Int
    var totalCharacters: Int
    var totalBackspaces: Int
    var totalDeletes: Int
    var inputMethodUsage: [String: Int]
    var isActive: Bool
    let createdAt: Date
}

private extension JSONEncoder {
    static let typeRecorder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let typeRecorderLine: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let typeRecorder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
