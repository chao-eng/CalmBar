import XCTest
@testable import CalmBar

final class AIGatewayTests: XCTestCase {
    // MARK: 密钥

    func testKeychainAPIKeyRoundTrip() {
        let channelID = "test-keychain-\(UUID().uuidString)"
        defer { GatewaySecretStore.setAPIKey("", for: channelID) }

        GatewaySecretStore.setAPIKey("sk-test-123", for: channelID)
        XCTAssertEqual(GatewaySecretStore.apiKey(for: channelID), "sk-test-123")

        GatewaySecretStore.setAPIKey("", for: channelID)
        XCTAssertTrue(GatewaySecretStore.apiKey(for: channelID).isEmpty)
    }

    // MARK: SSE

    func testSSEParserHandlesSplitChunksAndMultilineData() {
        var parser = GatewaySSEParser()
        let first = parser.feed(Data("event: message\r\ndata: line1\r\ndata: li".utf8))
        XCTAssertTrue(first.isEmpty)

        let second = parser.feed(Data("ne2\r\n\r\ndata: tail".utf8))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.event, "message")
        XCTAssertEqual(second.first?.data, "line1\nline2")

        let finished = parser.finish()
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished.first?.data, "tail")
    }

    func testSSEParserSupportsCROnlyAndComments() {
        var parser = GatewaySSEParser()
        let events = parser.feed(Data(": keep-alive\rdata: ok\r\r\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "ok")
    }

    func testSSEParserMarksOverflow() {
        var parser = GatewaySSEParser(maxEventBytes: 8)
        _ = parser.feed(Data("data: 12345678901234567890".utf8))
        XCTAssertTrue(parser.overflowed)
        XCTAssertTrue(parser.feed(Data("\n\n".utf8)).isEmpty)
    }

    // MARK: Token 估算

    func testTokenEstimatorCountsCJKPerCharacterAndLatinPerFour() {
        XCTAssertEqual(GatewayTokenEstimator.estimate("你好世界"), 4)
        XCTAssertEqual(GatewayTokenEstimator.estimate("abcdefgh"), 2)
        XCTAssertEqual(GatewayTokenEstimator.estimate("你好 abcdefgh"), 5)
        XCTAssertEqual(GatewayTokenEstimator.estimate(""), 0)
    }

    // MARK: 故障分类

    func testErrorClassifierRoutesAuthErrorsToRelay() {
        let failure = GatewayErrorClassifier.classify(statusCode: 401, body: Data())
        XCTAssertEqual(failure.action, .relay)
        XCTAssertEqual(failure.httpStatus, 401)
    }

    func testErrorClassifierMarksQuotaCooldownOn429() {
        let body = Data(#"{"error":{"message":"You exceeded your current quota"}}"#.utf8)
        let failure = GatewayErrorClassifier.classify(statusCode: 429, body: body)
        XCTAssertEqual(failure.action, .nextChannel)
        XCTAssertTrue(failure.markQuotaCooldown)
    }

    func testErrorClassifierSwitchesOnServerError() {
        XCTAssertEqual(GatewayErrorClassifier.classify(statusCode: 503, body: Data()).action, .nextChannel)
        XCTAssertEqual(GatewayErrorClassifier.classify(statusCode: 400, body: Data()).action, .relay)
        XCTAssertEqual(GatewayErrorClassifier.classify(statusCode: 302, body: Data()).action, .relay)
    }

    func testErrorClassifierIncludesUpstreamURLOn404() {
        let url = URL(string: "https://dashscope.aliyuncs.com/api/v1/chat/completions")!
        let failure = GatewayErrorClassifier.classify(statusCode: 404, body: Data(), upstreamURL: url)
        XCTAssertTrue(failure.message.contains("请求地址：https://dashscope.aliyuncs.com/api/v1/chat/completions"))
    }

    // MARK: Base URL 拼接与入站路径

    func testUpstreamURLStripsV1ForVersionedBase() {
        XCTAssertEqual(
            GatewayUpstreamRequestBuilder.makeURL(baseURL: "https://api.openai.com/v1", endpoint: "/v1/chat/completions")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            GatewayUpstreamRequestBuilder.makeURL(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", endpoint: "/v1/responses")?.absoluteString,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
        XCTAssertEqual(
            GatewayUpstreamRequestBuilder.makeURL(baseURL: "https://ark.cn-beijing.volces.com/api/v3", endpoint: "/v1/responses")?.absoluteString,
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
        XCTAssertEqual(
            GatewayUpstreamRequestBuilder.makeURL(baseURL: "https://gateway.example.com", endpoint: "/v1/chat/completions")?.absoluteString,
            "https://gateway.example.com/v1/chat/completions"
        )
    }

    func testInboundPathWithoutV1IsCanonicalized() {
        XCTAssertEqual(GatewayRequestProcessor.canonicalPath("/responses"), "/v1/responses")
        XCTAssertEqual(GatewayRequestProcessor.canonicalPath("/chat/completions"), "/v1/chat/completions")
        XCTAssertEqual(GatewayRequestProcessor.canonicalPath("/v1/responses"), "/v1/responses")
        XCTAssertEqual(GatewayRequestProcessor.canonicalPath("/health"), "/health")
    }

    // MARK: 渠道协议锁定

    func testChannelProtocolLocksUpstreamEndpoint() {
        XCTAssertEqual(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/chat/completions", protocolMode: .auto),
            "/v1/chat/completions"
        )
        XCTAssertEqual(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/responses", protocolMode: .auto),
            "/v1/responses"
        )
        XCTAssertEqual(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/chat/completions", protocolMode: .chat),
            "/v1/chat/completions"
        )
        XCTAssertNil(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/responses", protocolMode: .chat)
        )
        XCTAssertEqual(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/responses", protocolMode: .responses),
            "/v1/responses"
        )
        XCTAssertNil(
            GatewayRequestProcessor.upstreamEndpoint(clientPath: "/v1/chat/completions", protocolMode: .responses)
        )
    }

    func testChannelWithoutProtocolModeDecodesAsAuto() throws {
        let channel = AIGatewayChannel(id: "a", name: "A", baseURL: "https://api.example.com/v1", model: "m")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(channel)) as? [String: Any]
        )
        object.removeValue(forKey: "protocolMode")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AIGatewayChannel.self, from: data)
        XCTAssertEqual(decoded.protocolMode, .auto)
    }

    // MARK: 多上游模型

    func testLegacyChannelModelDecodesIntoModels() throws {
        let json = """
        {"id":"a","name":"A","baseURL":"https://api.example.com/v1","model":"m-1",
         "authHeader":"bearer","enabled":true,"proxy":{"mode":"direct","host":"","port":0,"username":""}}
        """
        let channel = try JSONDecoder().decode(AIGatewayChannel.self, from: Data(json.utf8))
        XCTAssertEqual(channel.models, ["m-1"])
        XCTAssertEqual(channel.model, "m-1")
    }

    func testChannelModelsRoundTripAndDeduplicate() throws {
        let channel = AIGatewayChannel(
            id: "a", name: "A", baseURL: "https://api.example.com/v1",
            models: ["m-1", " m-2 ", "m-1", ""]
        )
        XCTAssertEqual(channel.models, ["m-1", "m-2"])

        let decoded = try JSONDecoder().decode(AIGatewayChannel.self, from: JSONEncoder().encode(channel))
        XCTAssertEqual(decoded.models, ["m-1", "m-2"])
        XCTAssertEqual(decoded.model, "m-1")
    }

    func testLegacyRouteChannelIDsDecodeIntoBindings() throws {
        let json = """
        {"alias":"chat","channelIDs":["a","b"]}
        """
        let route = try JSONDecoder().decode(AIGatewayModelRoute.self, from: Data(json.utf8))
        XCTAssertEqual(route.channelIDs, ["a", "b"])
        XCTAssertEqual(route.bindings.map(\.upstreamModel), [nil, nil])
    }

    func testRouteBindingsRoundTrip() throws {
        let route = AIGatewayModelRoute(
            alias: "chat",
            bindings: [
                AIGatewayModelBinding(channelID: "a", upstreamModel: "m-x"),
                AIGatewayModelBinding(channelID: "b")
            ]
        )
        let decoded = try JSONDecoder().decode(AIGatewayModelRoute.self, from: JSONEncoder().encode(route))
        XCTAssertEqual(decoded, route)
    }

    func testSnapshotUpstreamModelResolution() {
        let channel = GatewayChannelRuntime(
            id: "a", name: "A", baseURL: "https://a.example/v1",
            model: "", models: ["m-primary", "chat"]
        )
        let snapshot = GatewaySnapshot(channels: ["a": channel])

        // 同名优先
        XCTAssertEqual(snapshot.upstreamModel(alias: "chat", channelID: "a"), "chat")
        // 无同名时回退主模型
        XCTAssertEqual(snapshot.upstreamModel(alias: "other", channelID: "a"), "m-primary")

        // 显式绑定优先于同名
        let bound = GatewaySnapshot(
            channels: ["a": channel],
            modelBindings: ["chat": ["a": "m-explicit"]]
        )
        XCTAssertEqual(bound.upstreamModel(alias: "chat", channelID: "a"), "m-explicit")
    }

    func testSnapshotBuilderCarriesBindings() {
        let channel = AIGatewayChannel(id: "a", name: "A", baseURL: "https://a.example/v1", models: ["m-1", "m-2"])
        let snapshot = GatewaySnapshotBuilder.makeSnapshot(
            enabled: true,
            port: 8317,
            serverKey: "",
            channels: [channel],
            models: [
                AIGatewayModelRoute(
                    alias: "chat",
                    bindings: [AIGatewayModelBinding(channelID: "a", upstreamModel: "m-2")]
                )
            ]
        )
        XCTAssertEqual(snapshot.modelRoutes["chat"], ["a"])
        XCTAssertEqual(snapshot.upstreamModel(alias: "chat", channelID: "a"), "m-2")
    }

    func testParseModelsSupportsOpenAIAndArrayShapes() throws {
        let openAI = try XCTUnwrap(#"{"data":[{"id":"b"},{"id":"a"},{"id":"a"}]}"#.data(using: .utf8))
        XCTAssertEqual(GatewayConnectionTester.parseModels(from: openAI), ["a", "b"])

        let array = try XCTUnwrap(#"["m-2","m-1"]"#.data(using: .utf8))
        XCTAssertEqual(GatewayConnectionTester.parseModels(from: array), ["m-1", "m-2"])

        let invalid = try XCTUnwrap("not json".data(using: .utf8))
        XCTAssertTrue(GatewayConnectionTester.parseModels(from: invalid).isEmpty)
    }

    // MARK: 路由

    func testRouterPrefersStickyResponseChannel() {
        GatewayCooldownStore.shared.clearAll()
        GatewayResponseChannelMap.shared.clearAll()

        let a = GatewayChannelRuntime(id: "a", name: "A", baseURL: "https://a.example/v1", model: "m-a")
        let b = GatewayChannelRuntime(id: "b", name: "B", baseURL: "https://b.example/v1", model: "m-b")
        let snapshot = GatewaySnapshot(
            channels: ["a": a, "b": b],
            modelRoutes: ["chat": ["a", "b"]],
            availableModels: ["chat"]
        )
        GatewayResponseChannelMap.shared.record(responseID: "resp_1", channelID: "b")

        let result = GatewayRouter.route(model: "chat", previousResponseID: "resp_1", snapshot: snapshot)
        guard case .routed(let alias, let channels, let sticky) = result else {
            return XCTFail("应命中路由")
        }
        XCTAssertEqual(alias, "chat")
        XCTAssertEqual(channels.map(\.id), ["b", "a"])
        XCTAssertEqual(sticky, "b")
    }

    func testRouterSkipsCoolingChannelUnlessAllCooling() {
        GatewayCooldownStore.shared.clearAll()
        GatewayResponseChannelMap.shared.clearAll()

        let a = GatewayChannelRuntime(id: "a", name: "A", baseURL: "https://a.example/v1", model: "m-a")
        let b = GatewayChannelRuntime(id: "b", name: "B", baseURL: "https://b.example/v1", model: "m-b")
        let snapshot = GatewaySnapshot(
            channels: ["a": a, "b": b],
            modelRoutes: ["chat": ["a", "b"]],
            availableModels: ["chat"]
        )

        GatewayCooldownStore.shared.markQuotaExhausted(channelID: "a", model: "m-a")
        guard case .routed(_, let channels, _) = GatewayRouter.route(model: "chat", previousResponseID: nil, snapshot: snapshot) else {
            return XCTFail("应命中路由")
        }
        XCTAssertEqual(channels.map(\.id), ["b"])

        // 全部冷却时回退完整顺序，避免直接失败
        GatewayCooldownStore.shared.markQuotaExhausted(channelID: "b", model: "m-b")
        guard case .routed(_, let fallback, _) = GatewayRouter.route(model: "chat", previousResponseID: nil, snapshot: snapshot) else {
            return XCTFail("应回退完整顺序")
        }
        XCTAssertEqual(fallback.map(\.id), ["a", "b"])

        GatewayCooldownStore.shared.clearAll()
    }

    func testRouterReturnsModelNotFound() {
        let snapshot = GatewaySnapshot()
        guard case .modelNotFound = GatewayRouter.route(model: "unknown", previousResponseID: nil, snapshot: snapshot) else {
            return XCTFail("未知模型应返回 modelNotFound")
        }
    }

    // MARK: 配置校验

    func testValidatorAllowsEmptyServerKeyAndChannelKey() {
        XCTAssertNil(GatewayConfigValidator.validateServerKey(""))
        XCTAssertNil(GatewayConfigValidator.validateServerKey("   "))
        XCTAssertNotNil(GatewayConfigValidator.validateServerKey("中文密钥"))
        XCTAssertNotNil(GatewayConfigValidator.validatePort(0))
        XCTAssertNil(GatewayConfigValidator.validatePort(8317))

        let channel = AIGatewayChannel(name: "本地", baseURL: "http://127.0.0.1:11434/v1", model: "llama3")
        XCTAssertTrue(GatewayConfigValidator.validateChannel(channel).isEmpty)

        let issues = GatewayConfigValidator.validate(
            port: 8317,
            serverKey: "",
            channels: [channel],
            models: [AIGatewayModelRoute(alias: "chat", channelIDs: [channel.id])]
        )
        XCTAssertTrue(issues.isEmpty, "\(issues.map(\.message))")
    }

    func testValidatorRejectsAliasWithoutExistingChannel() {
        let channel = AIGatewayChannel(name: "A", baseURL: "https://a.example/v1", model: "m")
        let issues = GatewayConfigValidator.validate(
            port: 8317,
            serverKey: "",
            channels: [channel],
            models: [AIGatewayModelRoute(alias: "chat", channelIDs: ["missing-channel"])]
        )
        XCTAssertTrue(issues.contains { $0.field == .modelChannel })
    }

    // MARK: 图表聚合与历史查询

    func testRangeBucketsAlignToWindow() {
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_123)

        let hourBuckets = GatewayRange.hour.buckets(now: now)
        XCTAssertEqual(hourBuckets.count, 60, "近 1 小时按分钟聚合")
        XCTAssertEqual(hourBuckets.last, GatewayRange.hour.currentBucketStart(now: now))
        for pair in zip(hourBuckets, hourBuckets.dropFirst()) {
            XCTAssertEqual(pair.1.timeIntervalSince(pair.0), 60)
        }

        let todayBuckets = GatewayRange.today.buckets(now: now)
        XCTAssertEqual(todayBuckets.first, calendar.startOfDay(for: now), "今天从零点开始")
        XCTAssertEqual(todayBuckets.last, calendar.dateInterval(of: .hour, for: now)?.start, "今天按小时聚合到当前小时")
        for pair in zip(todayBuckets, todayBuckets.dropFirst()) {
            XCTAssertEqual(pair.1.timeIntervalSince(pair.0), 3600)
        }

        let monthBuckets = GatewayRange.month.buckets(now: now)
        XCTAssertEqual(monthBuckets.count, 30, "近 30 天固定 30 个天桶")
        XCTAssertEqual(monthBuckets.last, calendar.startOfDay(for: now))
        for pair in zip(monthBuckets, monthBuckets.dropFirst()) {
            let days = calendar.dateComponents([.day], from: pair.0, to: pair.1).day
            XCTAssertEqual(days, 1, "天桶按自然日切分，夏令时也保持相邻一天")
        }
    }

    func testAllRangeUsesEarliestRecordAndCapsDayBuckets() {
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_123)

        XCTAssertTrue(GatewayRange.all.buckets(now: now).isEmpty, "库内无记录时「全部」没有桶")

        let earliest = calendar.date(byAdding: .day, value: -4, to: now) ?? now
        let buckets = GatewayRange.all.buckets(now: now, earliest: earliest)
        XCTAssertEqual(buckets.count, 5, "从最早记录当天到今天共 5 个天桶")
        XCTAssertEqual(buckets.first, calendar.startOfDay(for: earliest))
        XCTAssertEqual(buckets.last, calendar.startOfDay(for: now))

        let ancient = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let capped = GatewayRange.all.buckets(now: now, earliest: ancient)
        XCTAssertEqual(capped.count, GatewayRange.maxDayBuckets, "历史过长时只保留最近 90 天")
        XCTAssertEqual(capped.last, calendar.startOfDay(for: now))
    }

    func testDatabaseSeriesAveragesAndKeepsEmptyBuckets() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayRange.hour.currentBucketStart(now: now)
        let previous = current.addingTimeInterval(-60)

        try await database.insert(sample(at: current.addingTimeInterval(5), tps: 10, requestID: "r1"))
        try await database.insert(sample(at: current.addingTimeInterval(20), tps: 20, requestID: "r2"))
        try await database.insert(sample(at: previous.addingTimeInterval(30), tps: 40, requestID: "r3"))
        try await database.insert(sample(at: current.addingTimeInterval(30), tps: 99, requestID: "r4", status: .failed))

        let result = try await database.series(range: .hour, now: now)
        XCTAssertEqual(result.metric, .speed)
        XCTAssertEqual(result.buckets.count, 60, "近 1 小时共 60 个分钟桶")
        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.series.first?.requestCount, 3, "失败请求不参与速度口径，成功请求共 3 条")
        XCTAssertEqual(result.points.count, 2, "只保留有请求的桶，空桶不落点")
        let key = try XCTUnwrap(result.series.first?.key)
        XCTAssertEqual(try XCTUnwrap(result.value(for: key, at: current)), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.value(for: key, at: previous)), 40, accuracy: 0.001)
    }

    func testDatabaseSeriesSupportsTokenAndRequestMetrics() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayRange.hour.currentBucketStart(now: now)

        // 两条成功 + 一条失败：Token 与请求都应计入失败；本地拒绝则完全排除
        try await database.insert(sample(at: current.addingTimeInterval(5), tps: 10, requestID: "t1", tokens: 100))
        try await database.insert(sample(at: current.addingTimeInterval(20), tps: 20, requestID: "t2", tokens: 300))
        try await database.insert(sample(at: current.addingTimeInterval(30), tps: 0, requestID: "t3", status: .failed, tokens: 50))
        try await database.insert(sample(at: current.addingTimeInterval(40), tps: 0, requestID: "t4", status: .rejected, tokens: 999))

        let tokenResult = try await database.series(range: .hour, metric: .tokens, now: now)
        XCTAssertEqual(tokenResult.metric, .tokens)
        let tokenKey = try XCTUnwrap(tokenResult.series.first?.key)
        XCTAssertEqual(tokenResult.series.first?.requestCount, 3, "rejected 不计入系列请求数")
        XCTAssertEqual(try XCTUnwrap(tokenResult.value(for: tokenKey, at: current)), 450, accuracy: 0.001, "Token 口径为桶内累计")

        let requestResult = try await database.series(range: .hour, metric: .requests, now: now)
        XCTAssertEqual(requestResult.metric, .requests)
        let requestKey = try XCTUnwrap(requestResult.series.first?.key)
        XCTAssertEqual(try XCTUnwrap(requestResult.value(for: requestKey, at: current)), 3, accuracy: 0.001, "请求口径为次数累计")

        let speedResult = try await database.series(range: .hour, metric: .speed, now: now)
        let speedKey = try XCTUnwrap(speedResult.series.first?.key)
        XCTAssertEqual(speedResult.series.first?.requestCount, 2, "速度口径只统计成功请求")
        XCTAssertEqual(try XCTUnwrap(speedResult.value(for: speedKey, at: current)), 15, accuracy: 0.001)
    }

    func testChannelSummariesRanksByRequestCountAndSkipsEmptyChannel() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayRange.hour.currentBucketStart(now: now)

        // 渠道 A 两条（一成功一失败），渠道 B 一条成功，空渠道名的失败记录应被过滤
        try await database.insert(sample(at: current.addingTimeInterval(1), tps: 20, requestID: "a1", model: "chat", tokens: 100, channel: "渠道 A"))
        try await database.insert(sample(at: current.addingTimeInterval(2), tps: 0, requestID: "a2", status: .failed, model: "chat", tokens: 40, channel: "渠道 A"))
        try await database.insert(sample(at: current.addingTimeInterval(3), tps: 40, requestID: "b1", model: "embed", tokens: 300, channel: "渠道 B", ttft: 500))
        try await database.insert(sample(at: current.addingTimeInterval(4), tps: 0, requestID: "c1", status: .failed, model: "chat", tokens: 10, channel: ""))
        try await database.insert(sample(at: current.addingTimeInterval(5), tps: 0, requestID: "d1", status: .rejected, model: "chat", tokens: 10, channel: "渠道 C"))

        let ranking = try await database.channelSummaries(range: .hour, now: now, limit: 3)
        XCTAssertEqual(ranking.count, 2, "空渠道名与 rejected 记录不进入排行")
        XCTAssertEqual(ranking.first?.channelName, "渠道 A")
        XCTAssertEqual(ranking.first?.requestCount, 2)
        XCTAssertEqual(ranking.first?.successCount, 1)
        XCTAssertEqual(ranking.first?.totalTokens, 140)
        XCTAssertEqual(ranking.first?.averageTPS ?? 0, 20, accuracy: 0.001, "均值只统计成功请求")
        XCTAssertEqual(ranking.first?.successRate ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(ranking.last?.channelName, "渠道 B")
        XCTAssertEqual(ranking.last?.averageTTFT ?? 0, 500, accuracy: 0.001)

        let limited = try await database.channelSummaries(range: .hour, now: now, limit: 1)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited.first?.channelName, "渠道 A")
    }

    func testChannelSummariesRanksBySelectedMetric() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayRange.hour.currentBucketStart(now: now)

        // A：请求多但 Token 少、速度慢；B：请求少但 Token 多、速度快
        try await database.insert(sample(at: current.addingTimeInterval(1), tps: 5, requestID: "a1", model: "chat", tokens: 10, channel: "渠道 A"))
        try await database.insert(sample(at: current.addingTimeInterval(2), tps: 5, requestID: "a2", model: "chat", tokens: 10, channel: "渠道 A"))
        try await database.insert(sample(at: current.addingTimeInterval(3), tps: 5, requestID: "a3", model: "chat", tokens: 10, channel: "渠道 A"))
        try await database.insert(sample(at: current.addingTimeInterval(4), tps: 80, requestID: "b1", model: "embed", tokens: 900, channel: "渠道 B"))

        let byRequests = try await database.channelSummaries(range: .hour, now: now, limit: 2, metric: .requests)
        XCTAssertEqual(byRequests.first?.channelName, "渠道 A", "请求口径按次数排序")

        let byTokens = try await database.channelSummaries(range: .hour, now: now, limit: 2, metric: .tokens)
        XCTAssertEqual(byTokens.first?.channelName, "渠道 B", "Token 口径按总量排序")

        let bySpeed = try await database.channelSummaries(range: .hour, now: now, limit: 2, metric: .speed)
        XCTAssertEqual(bySpeed.first?.channelName, "渠道 B", "速度口径按平均 TPS 排序")

        // 无速度样本的渠道在速度口径里排到最后，而不是被 NULL 抢到前面
        try await database.insert(sample(at: current.addingTimeInterval(5), tps: 0, requestID: "c1", status: .failed, model: "chat", tokens: 5, channel: "渠道 C"))
        let speedWithNil = try await database.channelSummaries(range: .hour, now: now, limit: 3, metric: .speed)
        XCTAssertEqual(speedWithNil.last?.channelName, "渠道 C")
    }

    func testWindowSummaryAggregatesTotalsWithinWindow() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayRange.hour.currentBucketStart(now: now)

        try await database.insert(sample(at: current.addingTimeInterval(1), tps: 10, requestID: "s1", tokens: 100, input: 60, output: 40))
        try await database.insert(sample(at: current.addingTimeInterval(2), tps: 30, requestID: "s2", tokens: 200, input: 150, output: 50))
        try await database.insert(sample(at: current.addingTimeInterval(3), tps: 0, requestID: "s3", status: .failed, tokens: 20, input: 20, output: 0))
        // 窗口外的旧记录不应计入
        try await database.insert(sample(at: current.addingTimeInterval(-7200), tps: 99, requestID: "old", tokens: 999))

        let summary = try await database.summary(range: .hour, now: now)
        XCTAssertEqual(summary.requestCount, 3)
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.totalTokens, 320)
        XCTAssertEqual(summary.inputTokens, 230)
        XCTAssertEqual(summary.outputTokens, 90)
        XCTAssertEqual(summary.averageTPS ?? 0, 20, accuracy: 0.001)
    }

    func testDatabaseFilterAndDelete() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        try await database.insert(sample(at: Date(), tps: 12, requestID: "a", model: "chat"))
        try await database.insert(sample(at: Date(), tps: 8, requestID: "b", model: "embed"))

        let chatOnly = try await database.recent(filter: GatewayRequestFilter(model: "chat"), limit: 50)
        XCTAssertEqual(chatOnly.count, 1)
        XCTAssertEqual(chatOnly.first?.requestID, "a")

        let models = try await database.distinctModels()
        XCTAssertEqual(models, ["chat", "embed"])

        let record = try XCTUnwrap(chatOnly.first)
        try await database.delete(id: record.id)
        let remaining = try await database.count()
        XCTAssertEqual(remaining, 1)
        try await database.deleteAll()
        let emptyCount = try await database.count()
        XCTAssertEqual(emptyCount, 0)
    }

    private func sample(
        at date: Date,
        tps: Double,
        requestID: String,
        status: GatewayRequestStatus = .success,
        model: String = "chat",
        tokens: Int? = nil,
        input: Int? = nil,
        output: Int? = nil,
        channel: String = "渠道 A",
        ttft: Int? = nil
    ) -> GatewayRequestRecord {
        GatewayRequestRecord(
            createdAt: date,
            requestID: requestID,
            endpoint: "/v1/chat/completions",
            protocolName: "chat",
            isStream: true,
            requestedModel: model,
            upstreamModel: "gpt-4o-mini",
            channelID: "channel-a",
            channelName: channel,
            status: status,
            inputTokens: input,
            outputTokens: output,
            totalTokens: tokens,
            ttftMs: ttft,
            durationMs: 1200,
            outputTPS: tps,
            speedSource: .estimated
        )
    }
}
