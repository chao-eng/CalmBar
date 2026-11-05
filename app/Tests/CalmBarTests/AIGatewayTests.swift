import XCTest
@testable import CalmBar

final class AIGatewayTests: XCTestCase {
    // MARK: 密钥

    func testKeychainAPIKeyRoundTrip() {
        let channelID = "test-keychain-\(UUID().uuidString)"
        defer { GatewayKeychain.setAPIKey("", for: channelID) }

        GatewayKeychain.setAPIKey("sk-test-123", for: channelID)
        XCTAssertEqual(GatewayKeychain.apiKey(for: channelID), "sk-test-123")

        GatewayKeychain.setAPIKey("", for: channelID)
        XCTAssertTrue(GatewayKeychain.apiKey(for: channelID).isEmpty)
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

    func testGranularityBucketsAlignToWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_123)
        let buckets = GatewayGranularity.minute.windowBuckets(now: now)
        XCTAssertEqual(buckets.count, 10)
        XCTAssertEqual(buckets.last, GatewayGranularity.minute.currentBucketStart(now: now))
        for pair in zip(buckets, buckets.dropFirst()) {
            XCTAssertEqual(pair.1.timeIntervalSince(pair.0), 60)
        }
    }

    func testDatabaseSeriesAveragesAndKeepsEmptyBuckets() async throws {
        let path = NSTemporaryDirectory() + "aigateway-test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = GatewayDatabase(path: path)

        let now = Date(timeIntervalSince1970: 1_700_000_500)
        let current = GatewayGranularity.minute.currentBucketStart(now: now)
        let previous = current.addingTimeInterval(-60)

        try await database.insert(sample(at: current.addingTimeInterval(5), tps: 10, requestID: "r1"))
        try await database.insert(sample(at: current.addingTimeInterval(20), tps: 20, requestID: "r2"))
        try await database.insert(sample(at: previous.addingTimeInterval(30), tps: 40, requestID: "r3"))
        try await database.insert(sample(at: current.addingTimeInterval(30), tps: 99, requestID: "r4", status: .failed))

        let result = try await database.series(granularity: .minute, now: now)
        XCTAssertEqual(result.buckets.count, 10)
        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.series.first?.requestCount, 3)
        XCTAssertEqual(result.points.count, 2, "只保留有请求的桶，空桶不落点")
        let key = try XCTUnwrap(result.series.first?.key)
        XCTAssertEqual(try XCTUnwrap(result.averageTPS(for: key, at: current)), 15, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.averageTPS(for: key, at: previous)), 40, accuracy: 0.001)
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
        model: String = "chat"
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
            channelName: "渠道 A",
            status: status,
            durationMs: 1200,
            outputTPS: tps,
            speedSource: .estimated
        )
    }
}
