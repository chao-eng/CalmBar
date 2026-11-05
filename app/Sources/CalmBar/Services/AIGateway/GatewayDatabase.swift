import Foundation
import SQLite3

// MARK: - 请求记录

public enum GatewayRequestStatus: String, CaseIterable, Sendable {
    case success
    case failed
    case cancelled
    case rejected

    public var title: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        case .rejected: return "已拒绝"
        }
    }
}

public enum GatewaySpeedSource: String, Sendable {
    case usage
    case estimated
}

public enum GatewayTokenSource: String, Sendable {
    case usage
    case estimated
}

public struct GatewayRequestRecord: Sendable, Identifiable, Equatable {
    public var id: Int64
    public var createdAt: Date
    public var requestID: String
    public var endpoint: String
    public var protocolName: String
    public var isStream: Bool
    public var requestedModel: String
    public var upstreamModel: String?
    public var channelID: String?
    public var channelName: String?
    public var status: GatewayRequestStatus
    public var errorMessage: String?
    public var httpStatus: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var tokenSource: GatewayTokenSource?
    public var ttftMs: Int?
    public var generationMs: Int?
    public var durationMs: Int
    public var outputTPS: Double?
    public var speedSource: GatewaySpeedSource?
    public var retryReason: String?
    public var clientCancelled: Bool

    public init(
        id: Int64 = 0,
        createdAt: Date = Date(),
        requestID: String,
        endpoint: String,
        protocolName: String,
        isStream: Bool,
        requestedModel: String,
        upstreamModel: String? = nil,
        channelID: String? = nil,
        channelName: String? = nil,
        status: GatewayRequestStatus,
        errorMessage: String? = nil,
        httpStatus: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        tokenSource: GatewayTokenSource? = nil,
        ttftMs: Int? = nil,
        generationMs: Int? = nil,
        durationMs: Int = 0,
        outputTPS: Double? = nil,
        speedSource: GatewaySpeedSource? = nil,
        retryReason: String? = nil,
        clientCancelled: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.requestID = requestID
        self.endpoint = endpoint
        self.protocolName = protocolName
        self.isStream = isStream
        self.requestedModel = requestedModel
        self.upstreamModel = upstreamModel
        self.channelID = channelID
        self.channelName = channelName
        self.status = status
        self.errorMessage = errorMessage
        self.httpStatus = httpStatus
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.tokenSource = tokenSource
        self.ttftMs = ttftMs
        self.generationMs = generationMs
        self.durationMs = durationMs
        self.outputTPS = outputTPS
        self.speedSource = speedSource
        self.retryReason = retryReason
        self.clientCancelled = clientCancelled
    }
}

// MARK: - 历史筛选

/// 历史分页游标：按 (created_at, id) 倒序翻页，避免 offset 随新记录写入而漂移
public struct GatewayRequestCursor: Sendable, Equatable {
    public let createdAtMilliseconds: Int64
    public let id: Int64

    public init(createdAtMilliseconds: Int64, id: Int64) {
        self.createdAtMilliseconds = createdAtMilliseconds
        self.id = id
    }

    public init(record: GatewayRequestRecord) {
        self.createdAtMilliseconds = Int64((record.createdAt.timeIntervalSince1970 * 1000).rounded())
        self.id = record.id
    }
}

public struct GatewayRequestFilter: Sendable, Equatable {
    public var model: String?
    public var channel: String?
    public var status: GatewayRequestStatus?
    public var since: Date?
    public var until: Date?

    public init(
        model: String? = nil,
        channel: String? = nil,
        status: GatewayRequestStatus? = nil,
        since: Date? = nil,
        until: Date? = nil
    ) {
        self.model = model
        self.channel = channel
        self.status = status
        self.since = since
        self.until = until
    }
}

// MARK: - 图表聚合

public enum GatewayGranularity: String, CaseIterable, Identifiable, Sendable {
    case minute
    case hour
    case day

    public var id: String { rawValue }

    public var bucketSeconds: Int {
        switch self {
        case .minute: return 60
        case .hour: return 3600
        case .day: return 86400
        }
    }

    public var bucketCount: Int { 10 }

    public var title: String {
        switch self {
        case .minute: return "分钟"
        case .hour: return "小时"
        case .day: return "天"
        }
    }

    public var durationTitle: String {
        switch self {
        case .minute: return "10 分钟"
        case .hour: return "10 小时"
        case .day: return "10 天"
        }
    }

    /// 对齐到自然时间边界后的当前桶起点
    public func currentBucketStart(now: Date = Date()) -> Date {
        let seconds = Int(now.timeIntervalSince1970)
        let size = bucketSeconds
        return Date(timeIntervalSince1970: TimeInterval((seconds / size) * size))
    }

    public func windowBuckets(now: Date = Date()) -> [Date] {
        let current = currentBucketStart(now: now)
        return (0..<bucketCount).reversed().map {
            current.addingTimeInterval(TimeInterval(-$0 * bucketSeconds))
        }
    }
}

public struct GatewaySeriesDescriptor: Sendable, Equatable, Identifiable {
    public let key: String
    public let channelName: String
    public let model: String
    public let requestCount: Int

    public var id: String { key }
}

public struct GatewaySeriesPoint: Sendable, Equatable, Identifiable {
    public let bucketStart: Date
    public let seriesKey: String
    public let averageTPS: Double
    public let requestCount: Int

    public var id: String { "\(seriesKey)@\(bucketStart.timeIntervalSince1970)" }
}

public struct GatewaySeriesResult: Sendable, Equatable {
    public let buckets: [Date]
    public let series: [GatewaySeriesDescriptor]
    public let points: [GatewaySeriesPoint]

    public static let empty = GatewaySeriesResult(
        buckets: GatewayGranularity.minute.windowBuckets(),
        series: [],
        points: []
    )

    public func averageTPS(for seriesKey: String, at bucket: Date) -> Double? {
        points.first { $0.seriesKey == seriesKey && $0.bucketStart == bucket }?.averageTPS
    }
}

public struct GatewayWindowSummary: Sendable, Equatable {
    public let requestCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let totalTokens: Int
}

// MARK: - SQLite 封装

public enum GatewayDatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "网关数据库打开失败：\(message)"
        case .statementFailed(let message): return "网关数据库操作失败：\(message)"
        }
    }
}

public actor GatewayDatabase {
    public static let shared = GatewayDatabase()

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var db: OpaquePointer?
    private let queueLabel = "com.calmbar.aigateway.db"

    public init(path: String? = nil) {
        let resolved: String
        if let path {
            resolved = path
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = support.appendingPathComponent("CalmBar", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            resolved = directory.appendingPathComponent("aigateway.db").path
        }
        self.db = Self.openDatabase(path: resolved)
    }

    private static func openDatabase(path: String) -> OpaquePointer? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        sqlite3_busy_timeout(handle, 2000)
        execute(handle, "PRAGMA journal_mode=WAL;")
        execute(handle, "PRAGMA synchronous=NORMAL;")
        execute(handle, """
        CREATE TABLE IF NOT EXISTS requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            request_id TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            protocol TEXT NOT NULL,
            stream INTEGER NOT NULL,
            requested_model TEXT NOT NULL,
            upstream_model TEXT,
            channel_id TEXT,
            channel_name TEXT,
            status TEXT NOT NULL,
            error_message TEXT,
            http_status INTEGER,
            input_tokens INTEGER,
            output_tokens INTEGER,
            total_tokens INTEGER,
            token_source TEXT,
            ttft_ms INTEGER,
            generation_ms INTEGER,
            duration_ms INTEGER NOT NULL,
            output_tps REAL,
            speed_source TEXT,
            retry_reason TEXT,
            client_cancelled INTEGER NOT NULL DEFAULT 0
        );
        """)
        execute(handle, "CREATE INDEX IF NOT EXISTS idx_requests_created_at ON requests(created_at);")
        execute(handle, "CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);")
        return handle
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error { sqlite3_free(error) }
        }
    }

    // MARK: 写入

    public func insert(_ record: GatewayRequestRecord) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        let sql = """
        INSERT INTO requests (
            created_at, request_id, endpoint, protocol, stream, requested_model, upstream_model,
            channel_id, channel_name, status, error_message, http_status,
            input_tokens, output_tokens, total_tokens, token_source,
            ttft_ms, generation_ms, duration_ms, output_tps, speed_source,
            retry_reason, client_cancelled
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, Int64(record.createdAt.timeIntervalSince1970 * 1000))
        bind(stmt, 2, record.requestID)
        bind(stmt, 3, record.endpoint)
        bind(stmt, 4, record.protocolName)
        bind(stmt, 5, record.isStream ? 1 : 0)
        bind(stmt, 6, record.requestedModel)
        bind(stmt, 7, record.upstreamModel)
        bind(stmt, 8, record.channelID)
        bind(stmt, 9, record.channelName)
        bind(stmt, 10, record.status.rawValue)
        bind(stmt, 11, record.errorMessage)
        bind(stmt, 12, record.httpStatus)
        bind(stmt, 13, record.inputTokens)
        bind(stmt, 14, record.outputTokens)
        bind(stmt, 15, record.totalTokens)
        bind(stmt, 16, record.tokenSource?.rawValue)
        bind(stmt, 17, record.ttftMs)
        bind(stmt, 18, record.generationMs)
        bind(stmt, 19, record.durationMs)
        bind(stmt, 20, record.outputTPS)
        bind(stmt, 21, record.speedSource?.rawValue)
        bind(stmt, 22, record.retryReason)
        bind(stmt, 23, record.clientCancelled ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: 查询

    public func recent(
        filter: GatewayRequestFilter = GatewayRequestFilter(),
        before: GatewayRequestCursor? = nil,
        limit: Int,
        offset: Int = 0
    ) throws -> [GatewayRequestRecord] {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }

        var clauses: [String] = []
        var bindings: [Any] = []
        if let model = filter.model {
            clauses.append("requested_model = ?")
            bindings.append(model)
        }
        if let channel = filter.channel {
            clauses.append("channel_name = ?")
            bindings.append(channel)
        }
        if let status = filter.status {
            clauses.append("status = ?")
            bindings.append(status.rawValue)
        }
        if let since = filter.since {
            clauses.append("created_at >= ?")
            bindings.append(Int64(since.timeIntervalSince1970 * 1000))
        }
        if let until = filter.until {
            clauses.append("created_at <= ?")
            bindings.append(Int64(until.timeIntervalSince1970 * 1000))
        }
        if let before {
            clauses.append("(created_at < ? OR (created_at = ? AND id < ?))")
            bindings.append(before.createdAtMilliseconds)
            bindings.append(before.createdAtMilliseconds)
            bindings.append(before.id)
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")

        let sql = """
        SELECT id, created_at, request_id, endpoint, protocol, stream, requested_model, upstream_model,
               channel_id, channel_name, status, error_message, http_status,
               input_tokens, output_tokens, total_tokens, token_source,
               ttft_ms, generation_ms, duration_ms, output_tps, speed_source,
               retry_reason, client_cancelled
        FROM requests
        \(whereClause)
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var index: Int32 = 1
        for value in bindings {
            switch value {
            case let text as String:
                sqlite3_bind_text(stmt, index, text, -1, Self.transient)
            case let number as Int64:
                sqlite3_bind_int64(stmt, index, number)
            default:
                sqlite3_bind_null(stmt, index)
            }
            index += 1
        }
        sqlite3_bind_int(stmt, index, Int32(max(0, limit)))
        sqlite3_bind_int(stmt, index + 1, Int32(max(0, offset)))

        var rows: [GatewayRequestRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(mapRow(stmt))
        }
        return rows
    }

    public func distinctModels() throws -> [String] {
        try distinctValues(column: "requested_model")
    }

    public func distinctChannels() throws -> [String] {
        try distinctValues(column: "channel_name")
    }

    private func distinctValues(column: String) throws -> [String] {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        let sql = "SELECT DISTINCT \(column) FROM requests WHERE \(column) IS NOT NULL ORDER BY \(column) ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var values: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 0), !text.isEmpty {
                values.append(text)
            }
        }
        return values
    }

    public func delete(id: Int64) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM requests WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func count() throws -> Int {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM requests;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    public func deleteAll() throws {
        try execute("DELETE FROM requests;")
        try execute("VACUUM;")
    }

    public func delete(olderThan date: Date) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM requests WHERE created_at < ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970 * 1000))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func summary(since: Date) throws -> GatewayWindowSummary {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        let sql = """
        SELECT COUNT(*),
               SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END),
               SUM(CASE WHEN status IN ('failed', 'rejected') THEN 1 ELSE 0 END),
               SUM(COALESCE(total_tokens, 0))
        FROM requests WHERE created_at >= ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970 * 1000))
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return GatewayWindowSummary(requestCount: 0, successCount: 0, failureCount: 0, totalTokens: 0)
        }
        return GatewayWindowSummary(
            requestCount: Int(sqlite3_column_int64(stmt, 0)),
            successCount: Int(sqlite3_column_int64(stmt, 1)),
            failureCount: Int(sqlite3_column_int64(stmt, 2)),
            totalTokens: Int(sqlite3_column_int64(stmt, 3))
        )
    }

    /// 按粒度聚合最近 N 个桶的平均 Output TPS，只保留请求量最高的 4 条系列
    public func series(granularity: GatewayGranularity, now: Date = Date(), seriesLimit: Int = 4) throws -> GatewaySeriesResult {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }

        let buckets = granularity.windowBuckets(now: now)
        guard let windowStart = buckets.first else { return .empty }
        let bucketSeconds = granularity.bucketSeconds

        let sql = """
        SELECT created_at, channel_name, requested_model, output_tps
        FROM requests
        WHERE created_at >= ? AND created_at < ? AND status = 'success' AND output_tps IS NOT NULL;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        // 窗口右边界取当前桶的结束时刻，避免与查询同一毫秒写入的记录被 `< now` 排除
        let windowEnd = (buckets.last ?? now).addingTimeInterval(TimeInterval(bucketSeconds))
        sqlite3_bind_int64(stmt, 1, Int64(windowStart.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 2, Int64(windowEnd.timeIntervalSince1970 * 1000))

        struct Sample {
            let bucket: Date
            let key: String
            let channel: String
            let model: String
            let tps: Double
        }

        var samples: [Sample] = []
        var counts: [String: Int] = [:]
        var names: [String: (channel: String, model: String)] = [:]


        while sqlite3_step(stmt) == SQLITE_ROW {
            let milliseconds = sqlite3_column_int64(stmt, 0)
            guard let channel = columnText(stmt, 1) else { continue }
            guard let model = columnText(stmt, 2) else { continue }
            let tps = sqlite3_column_double(stmt, 3)
            guard tps.isFinite, tps > 0 else { continue }

            let createdAt = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            let seconds = Int(createdAt.timeIntervalSince1970)
            let bucketStart = Date(timeIntervalSince1970: TimeInterval((seconds / bucketSeconds) * bucketSeconds))
            let key = "\(channel)|\(model)"
            counts[key, default: 0] += 1
            names[key] = (channel, model)
            samples.append(Sample(bucket: bucketStart, key: key, channel: channel, model: model, tps: tps))
        }

        let topKeys = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(seriesLimit).map(\.key)

        guard !topKeys.isEmpty else {
            return GatewaySeriesResult(buckets: buckets, series: [], points: [])
        }

        var sums: [String: (sum: Double, count: Int)] = [:]
        for sample in samples where topKeys.contains(sample.key) {
            let composite = "\(sample.key)#\(Int(sample.bucket.timeIntervalSince1970))"
            var entry = sums[composite] ?? (0, 0)
            entry.sum += sample.tps
            entry.count += 1
            sums[composite] = entry
        }

        var points: [GatewaySeriesPoint] = []
        for key in topKeys {
            for bucket in buckets {
                let composite = "\(key)#\(Int(bucket.timeIntervalSince1970))"
                guard let entry = sums[composite], entry.count > 0 else { continue }
                points.append(GatewaySeriesPoint(
                    bucketStart: bucket,
                    seriesKey: key,
                    averageTPS: entry.sum / Double(entry.count),
                    requestCount: entry.count
                ))
            }
        }

        let series = topKeys.compactMap { key -> GatewaySeriesDescriptor? in
            guard let info = names[key] else { return nil }
            return GatewaySeriesDescriptor(
                key: key,
                channelName: info.channel,
                model: info.model,
                requestCount: counts[key] ?? 0
            )
        }

        return GatewaySeriesResult(buckets: buckets, series: series, points: points)
    }

    // MARK: 工具

    private func execute(_ sql: String) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            if let error { sqlite3_free(error) }
            throw GatewayDatabaseError.statementFailed(message)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    private func columnInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private func columnDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func mapRow(_ stmt: OpaquePointer) -> GatewayRequestRecord {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)) / 1000)
        return GatewayRequestRecord(
            id: sqlite3_column_int64(stmt, 0),
            createdAt: createdAt,
            requestID: columnText(stmt, 2) ?? "",
            endpoint: columnText(stmt, 3) ?? "",
            protocolName: columnText(stmt, 4) ?? "",
            isStream: sqlite3_column_int(stmt, 5) != 0,
            requestedModel: columnText(stmt, 6) ?? "",
            upstreamModel: columnText(stmt, 7),
            channelID: columnText(stmt, 8),
            channelName: columnText(stmt, 9),
            status: GatewayRequestStatus(rawValue: columnText(stmt, 10) ?? "") ?? .failed,
            errorMessage: columnText(stmt, 11),
            httpStatus: columnInt(stmt, 12),
            inputTokens: columnInt(stmt, 13),
            outputTokens: columnInt(stmt, 14),
            totalTokens: columnInt(stmt, 15),
            tokenSource: columnText(stmt, 16).flatMap(GatewayTokenSource.init(rawValue:)),
            ttftMs: columnInt(stmt, 17),
            generationMs: columnInt(stmt, 18),
            durationMs: Int(sqlite3_column_int64(stmt, 19)),
            outputTPS: columnDouble(stmt, 20),
            speedSource: columnText(stmt, 21).flatMap(GatewaySpeedSource.init(rawValue:)),
            retryReason: columnText(stmt, 22),
            clientCancelled: sqlite3_column_int(stmt, 23) != 0
        )
    }
}
