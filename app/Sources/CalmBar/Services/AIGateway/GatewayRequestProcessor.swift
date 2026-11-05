import Foundation

// MARK: - 单次请求处理器

/// 处理一次推理请求：鉴权 → 路由 → 上游透传 → 故障切换 → 指标落库数据
public struct GatewayRequestProcessor: Sendable {
    private let snapshot: GatewaySnapshot
    private let cooldown: GatewayCooldownStore
    private let responseMap: GatewayResponseChannelMap

    public init(
        snapshot: GatewaySnapshot,
        cooldown: GatewayCooldownStore = .shared,
        responseMap: GatewayResponseChannelMap = .shared
    ) {
        self.snapshot = snapshot
        self.cooldown = cooldown
        self.responseMap = responseMap
    }

    // MARK: 入口

    public func run(request: GatewayHTTPRequest, connection: GatewayHTTPConnection) async -> GatewayRequestRecord? {
        let receivedAt = Date()

        // 兼容 /responses 与 /v1/responses 两种调用方式，统一成带 /v1 的规范路径
        var request = request
        request.path = Self.canonicalPath(request.path)

        if request.path == "/health" {
            await handleHealth(connection: connection)
            return nil
        }

        guard request.path == "/v1/models" || request.path == "/v1/chat/completions" || request.path == "/v1/responses" else {
            await respondError(connection, status: 404, code: "not_found", message: "未知路径：\(request.path)")
            return nil
        }

        if let rejection = securityRejection(for: request) {
            await respondError(connection, status: rejection.status, code: rejection.code, message: rejection.message)
            return nil
        }

        guard authorized(request) else {
            await respondError(connection, status: 401, code: "invalid_api_key", message: "网关访问密钥无效")
            return GatewayRequestRecord(
                requestID: UUID().uuidString,
                endpoint: request.path,
                protocolName: "unknown",
                isStream: false,
                requestedModel: "-",
                status: .rejected,
                errorMessage: "网关访问密钥无效",
                httpStatus: 401,
                durationMs: Self.milliseconds(from: receivedAt, to: Date())
            )
        }

        if request.method == "OPTIONS" {
            await respondError(connection, status: 405, code: "method_not_allowed", message: "不支持 OPTIONS 预检请求")
            return nil
        }

        if request.path == "/v1/models" {
            guard request.method == "GET" else {
                await respondError(connection, status: 405, code: "method_not_allowed", message: "仅支持 GET")
                return nil
            }
            await handleModels(connection: connection)
            return nil
        }

        guard request.method == "POST" else {
            await respondError(connection, status: 405, code: "method_not_allowed", message: "仅支持 POST")
            return nil
        }
        guard let protocolName = GatewayStreamProtocol(endpoint: request.path) else {
            await respondError(connection, status: 404, code: "not_found", message: "未知路径")
            return nil
        }
        if let contentType = request.headers["content-type"]?.lowercased(),
           !contentType.contains("application/json") {
            await respondError(connection, status: 415, code: "unsupported_media_type", message: "Content-Type 必须为 application/json")
            return nil
        }
        guard !request.body.isEmpty else {
            await respondError(connection, status: 400, code: "invalid_request_error", message: "请求体不能为空")
            return nil
        }

        let parsed: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                throw GatewayLocalError.invalidJSON
            }
            parsed = object
        } catch {
            await respondError(connection, status: 400, code: "invalid_request_error", message: "请求体不是合法 JSON 对象")
            return GatewayRequestRecord(
                requestID: UUID().uuidString,
                endpoint: request.path,
                protocolName: protocolName.rawValue,
                isStream: false,
                requestedModel: "-",
                status: .rejected,
                errorMessage: "请求体不是合法 JSON 对象",
                httpStatus: 400,
                durationMs: Self.milliseconds(from: receivedAt, to: Date())
            )
        }

        guard let requestedModel = parsed["model"] as? String, !requestedModel.isEmpty else {
            await respondError(connection, status: 400, code: "invalid_request_error", message: "缺少 model 字段")
            return GatewayRequestRecord(
                requestID: UUID().uuidString,
                endpoint: request.path,
                protocolName: protocolName.rawValue,
                isStream: false,
                requestedModel: "-",
                status: .rejected,
                errorMessage: "缺少 model 字段",
                httpStatus: 400,
                durationMs: Self.milliseconds(from: receivedAt, to: Date())
            )
        }

        let isStream = (parsed["stream"] as? Bool) ?? false
        let previousResponseID = parsed["previous_response_id"] as? String
        let estimatedInputTokens = GatewayTokenEstimator.estimateInput(from: request.body)

        let route = GatewayRouter.route(
            model: requestedModel,
            previousResponseID: previousResponseID,
            snapshot: snapshot,
            cooldown: cooldown,
            responseMap: responseMap
        )

        switch route {
        case .modelNotFound(let available):
            let hint = available.isEmpty ? "当前未配置任何可用模型" : "可用模型：\(available.joined(separator: ", "))"
            await respondError(connection, status: 404, code: "model_not_found", message: "模型 \(requestedModel) 不存在。\(hint)")
            return GatewayRequestRecord(
                requestID: UUID().uuidString,
                endpoint: request.path,
                protocolName: protocolName.rawValue,
                isStream: isStream,
                requestedModel: requestedModel,
                status: .rejected,
                errorMessage: "模型不存在",
                httpStatus: 404,
                durationMs: Self.milliseconds(from: receivedAt, to: Date())
            )
        case .noAvailableChannel(let alias, let reason):
            await respondError(connection, status: 503, code: "no_available_channel", message: "模型 \(alias) 暂无可用渠道：\(reason)")
            return GatewayRequestRecord(
                requestID: UUID().uuidString,
                endpoint: request.path,
                protocolName: protocolName.rawValue,
                isStream: isStream,
                requestedModel: requestedModel,
                status: .failed,
                errorMessage: reason,
                httpStatus: 503,
                durationMs: Self.milliseconds(from: receivedAt, to: Date())
            )
        case .routed(let alias, let channels, _):
            return await execute(
                alias: alias,
                channels: channels,
                protocolName: protocolName,
                endpoint: request.path,
                parsed: parsed,
                isStream: isStream,
                estimatedInputTokens: estimatedInputTokens,
                receivedAt: receivedAt,
                connection: connection
            )
        }
    }

    // MARK: 路径兼容

    /// 允许客户端省略 `/v1` 前缀，例如直接请求 `http://127.0.0.1:8317/responses`
    static func canonicalPath(_ path: String) -> String {
        switch path {
        case "/chat/completions", "/responses", "/models":
            return "/v1" + path
        default:
            return path
        }
    }

    /// 渠道锁定协议时校验客户端入口是否匹配；返回上游应使用的路径
    static func upstreamEndpoint(clientPath: String, protocolMode: AIGatewayUpstreamProtocol) -> String? {
        guard let locked = protocolMode.lockedEndpoint else { return clientPath }
        return locked == clientPath ? clientPath : nil
    }

    // MARK: 执行与故障切换

    private func execute(
        alias: String,
        channels: [GatewayChannelRuntime],
        protocolName: GatewayStreamProtocol,
        endpoint: String,
        parsed: [String: Any],
        isStream: Bool,
        estimatedInputTokens: Int,
        receivedAt: Date,
        connection: GatewayHTTPConnection
    ) async -> GatewayRequestRecord {
        var retryReasons: [String] = []
        var lastFailure: GatewayFailure?
        var attemptedChannels = 0
        var lockedProtocolMismatch: AIGatewayUpstreamProtocol?

        for channel in channels {
            // 渠道锁定了上游协议时，客户端必须调用匹配的入口，避免把 chat 请求体发给 responses 端点
            guard let upstreamEndpoint = Self.upstreamEndpoint(clientPath: endpoint, protocolMode: channel.protocolMode) else {
                lockedProtocolMismatch = channel.protocolMode
                continue
            }

            // 别名在该渠道下可能绑定到不同的上游模型
            let upstreamModelName = snapshot.upstreamModel(alias: alias, channelID: channel.id) ?? channel.model
            var bodyObject = parsed
            bodyObject["model"] = upstreamModelName
            let body: Data
            do {
                body = try JSONSerialization.data(withJSONObject: bodyObject)
            } catch {
                lastFailure = GatewayFailure(
                    kind: .upstreamJSONError,
                    action: .nextChannel,
                    message: "无法序列化上游请求体"
                )
                retryReasons.append("\(channel.name): 请求体序列化失败")
                continue
            }

            guard let upstreamRequest = GatewayUpstreamRequestBuilder.makeRequest(
                channel: channel,
                endpoint: upstreamEndpoint,
                body: body,
                isStream: isStream
            ) else {
                lastFailure = GatewayFailure(kind: .connectFailed, action: .nextChannel, message: "渠道 Base URL 无效")
                retryReasons.append("\(channel.name): Base URL 无效")
                continue
            }

            attemptedChannels += 1

            let result: GatewayAttemptResult
            if isStream {
                result = await performStreamAttempt(
                    channel: channel,
                    request: upstreamRequest,
                    protocolName: protocolName,
                    receivedAt: receivedAt,
                    connection: connection
                )
            } else {
                result = await performBufferedAttempt(
                    channel: channel,
                    request: upstreamRequest,
                    protocolName: protocolName,
                    receivedAt: receivedAt
                )
            }

            switch result {
            case .bufferedSuccess(let status, let headers, let upstreamBody, let usage, let responseID, let upstreamModel, let headersAt):
                let cleanHeaders = Self.sanitizedHeaders(headers)
                await connection.respond(status: status, headers: cleanHeaders, body: upstreamBody)
                responseMap.record(responseID: responseID ?? "", channelID: channel.id)
                return Self.makeRecord(
                    endpoint: endpoint,
                    protocolName: protocolName,
                    isStream: false,
                    requestedModel: alias,
                    channel: channel,
                    upstreamModel: upstreamModel,
                    status: .success,
                    errorMessage: nil,
                    httpStatus: status,
                    usage: usage,
                    estimatedInput: estimatedInputTokens,
                    estimatedOutput: nil,
                    ttftMs: Self.milliseconds(from: receivedAt, to: headersAt),
                    generationMs: nil,
                    durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                    outputTPS: nil,
                    speedSource: nil,
                    retryReasons: retryReasons,
                    clientCancelled: false
                )

            case .streamSuccess(let metrics):
                responseMap.record(responseID: metrics.responseID ?? "", channelID: channel.id)
                let outputTokens = metrics.usage?.outputTokens ?? (metrics.estimatedOutputTokens > 0 ? metrics.estimatedOutputTokens : nil)
                let generationMs: Int? = {
                    guard let last = metrics.lastContentAt else { return nil }
                    return Self.milliseconds(from: metrics.firstContentAt, to: last)
                }()
                let tps: Double? = {
                    guard let outputTokens, let generationMs, generationMs > 0 else { return nil }
                    return Double(outputTokens) / (Double(generationMs) / 1000)
                }()
                return Self.makeRecord(
                    endpoint: endpoint,
                    protocolName: protocolName,
                    isStream: true,
                    requestedModel: alias,
                    channel: channel,
                    upstreamModel: metrics.upstreamModel,
                    status: .success,
                    errorMessage: nil,
                    httpStatus: metrics.statusCode,
                    usage: metrics.usage,
                    estimatedInput: estimatedInputTokens,
                    estimatedOutput: metrics.estimatedOutputTokens,
                    ttftMs: Self.milliseconds(from: receivedAt, to: metrics.firstContentAt),
                    generationMs: generationMs,
                    durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                    outputTPS: tps,
                    speedSource: metrics.usage?.outputTokens != nil ? .usage : .estimated,
                    retryReasons: retryReasons,
                    clientCancelled: false
                )

            case .clientCancelled(let metrics):
                return Self.makeRecord(
                    endpoint: endpoint,
                    protocolName: protocolName,
                    isStream: isStream,
                    requestedModel: alias,
                    channel: channel,
                    upstreamModel: metrics?.upstreamModel,
                    status: .cancelled,
                    errorMessage: "客户端断开连接",
                    httpStatus: metrics?.statusCode,
                    usage: metrics?.usage,
                    estimatedInput: estimatedInputTokens,
                    estimatedOutput: metrics?.estimatedOutputTokens,
                    ttftMs: metrics.flatMap { m in Self.milliseconds(from: receivedAt, to: m.firstContentAt) },
                    generationMs: nil,
                    durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                    outputTPS: nil,
                    speedSource: nil,
                    retryReasons: retryReasons,
                    clientCancelled: true
                )

            case .failure(let failure, let committed, let metrics):
                lastFailure = failure
                if failure.markQuotaCooldown {
                    cooldown.markQuotaExhausted(channelID: channel.id, model: upstreamModelName)
                }
                if committed {
                    return Self.makeRecord(
                        endpoint: endpoint,
                        protocolName: protocolName,
                        isStream: true,
                        requestedModel: alias,
                        channel: channel,
                        upstreamModel: metrics?.upstreamModel,
                        status: .failed,
                        errorMessage: failure.message,
                        httpStatus: failure.httpStatus ?? metrics?.statusCode,
                        usage: metrics?.usage,
                        estimatedInput: estimatedInputTokens,
                        estimatedOutput: metrics?.estimatedOutputTokens,
                        ttftMs: metrics.flatMap { m in Self.milliseconds(from: receivedAt, to: m.firstContentAt) },
                        generationMs: nil,
                        durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                        outputTPS: nil,
                        speedSource: nil,
                        retryReasons: retryReasons,
                        clientCancelled: false
                    )
                }
                if failure.action == .relay {
                    await relay(failure, connection: connection)
                    return Self.makeRecord(
                        endpoint: endpoint,
                        protocolName: protocolName,
                        isStream: isStream,
                        requestedModel: alias,
                        channel: channel,
                        upstreamModel: nil,
                        status: .failed,
                        errorMessage: failure.message,
                        httpStatus: failure.httpStatus,
                        usage: nil,
                        estimatedInput: estimatedInputTokens,
                        estimatedOutput: nil,
                        ttftMs: nil,
                        generationMs: nil,
                        durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                        outputTPS: nil,
                        speedSource: nil,
                        retryReasons: retryReasons,
                        clientCancelled: false
                    )
                }
                retryReasons.append("\(channel.name): \(failure.message)")
                continue
            }
        }

        // 所有候选渠道都因协议锁定被跳过：明确提示该用哪个入口
        if attemptedChannels == 0, let lockedProtocolMismatch, lastFailure == nil {
            let expected = lockedProtocolMismatch.lockedEndpoint ?? endpoint
            let message = "该模型绑定的渠道仅支持 \(lockedProtocolMismatch.title)，请改用 \(expected) 调用（当前为 \(endpoint)）"
            await respondError(connection, status: 400, code: "protocol_mismatch", message: message)
            return Self.makeRecord(
                endpoint: endpoint,
                protocolName: protocolName,
                isStream: isStream,
                requestedModel: alias,
                channel: nil,
                upstreamModel: nil,
                status: .rejected,
                errorMessage: message,
                httpStatus: 400,
                usage: nil,
                estimatedInput: estimatedInputTokens,
                estimatedOutput: nil,
                ttftMs: nil,
                generationMs: nil,
                durationMs: Self.milliseconds(from: receivedAt, to: Date()),
                outputTPS: nil,
                speedSource: nil,
                retryReasons: [],
                clientCancelled: false
            )
        }

        // 所有候选渠道均失败
        let failure = lastFailure ?? GatewayFailure(
            kind: .connectFailed,
            action: .nextChannel,
            message: "没有可用渠道"
        )
        if let upstreamBody = failure.upstreamBody, let status = failure.httpStatus, (400..<600).contains(status) {
            await connection.respond(
                status: status,
                headers: [GatewayHeader(name: "Content-Type", value: "application/json; charset=utf-8")],
                body: upstreamBody
            )
        } else {
            let message = retryReasons.isEmpty ? failure.message : retryReasons.joined(separator: " → ")
            await respondError(connection, status: 502, code: "upstream_error", message: message)
        }
        return Self.makeRecord(
            endpoint: endpoint,
            protocolName: protocolName,
            isStream: isStream,
            requestedModel: alias,
            channel: nil,
            upstreamModel: nil,
            status: .failed,
            errorMessage: failure.message,
            httpStatus: failure.httpStatus ?? 502,
            usage: nil,
            estimatedInput: estimatedInputTokens,
            estimatedOutput: nil,
            ttftMs: nil,
            generationMs: nil,
            durationMs: Self.milliseconds(from: receivedAt, to: Date()),
            outputTPS: nil,
            speedSource: nil,
            retryReasons: retryReasons,
            clientCancelled: false
        )
    }

    // MARK: 非流式

    private func performBufferedAttempt(
        channel: GatewayChannelRuntime,
        request: URLRequest,
        protocolName: GatewayStreamProtocol,
        receivedAt: Date
    ) async -> GatewayAttemptResult {
        let upstream = GatewayUpstreamConnection(
            collectsBody: true,
            bodyLimit: 8 * 1024 * 1024,
            proxy: channel.proxy,
            proxyPassword: channel.proxyPassword
        )
        upstream.start(request: request)

        var statusCode = 0
        var headers: [GatewayHeader] = []
        var headersAt = Date()
        var terminalEvent: GatewayUpstreamEvent?

        for await event in upstream.events {
            switch event {
            case .response(let status, let receivedHeaders):
                statusCode = status
                headers = receivedHeaders
                headersAt = Date()
            case .timedOut(let kind):
                terminalEvent = .timedOut(kind)
            case .completed(let body, let error):
                terminalEvent = .completed(body: body, error: error)
            case .data, .cancelled:
                break
            }
            if terminalEvent != nil { break }
        }
        upstream.cancel()

        guard statusCode > 0 else {
            return .failure(
                GatewayFailure(kind: .connectFailed, action: .nextChannel, message: "上游未返回响应"),
                committed: false,
                stream: nil
            )
        }

        switch terminalEvent {
        case .timedOut(let kind):
            let failure = GatewayFailure(
                kind: kind,
                action: .nextChannel,
                message: kind == .firstContentTimeout ? "首内容超时" : "上游超时"
            )
            return .failure(failure, committed: false, stream: nil)
        case .completed(let body, let error):
            if let error {
                return .failure(
                    GatewayErrorClassifier.classify(error: error, hasCommitted: false),
                    committed: false,
                    stream: nil
                )
            }
            let body = body ?? Data()
            let failure = GatewayErrorClassifier.classify(statusCode: statusCode, body: body, upstreamURL: request.url)
            if (200..<300).contains(statusCode), failure.kind != .upstreamJSONError {
                let info = Self.parseBufferedInfo(body)
                return .bufferedSuccess(
                    status: statusCode,
                    headers: headers,
                    body: body,
                    usage: info.usage,
                    responseID: info.responseID,
                    upstreamModel: info.model,
                    headersAt: headersAt
                )
            }
            return .failure(failure, committed: false, stream: nil)
        default:
            return .failure(
                GatewayFailure(kind: .connectFailed, action: .nextChannel, message: "上游连接中断"),
                committed: false,
                stream: nil
            )
        }
    }

    // MARK: 流式

    private func performStreamAttempt(
        channel: GatewayChannelRuntime,
        request: URLRequest,
        protocolName: GatewayStreamProtocol,
        receivedAt: Date,
        connection: GatewayHTTPConnection
    ) async -> GatewayAttemptResult {
        let upstream = GatewayUpstreamConnection(
            collectsBody: false,
            proxy: channel.proxy,
            proxyPassword: channel.proxyPassword
        )
        var parser = GatewaySSEParser()
        var analyzer = GatewayStreamAnalyzer(protocolName: protocolName)

        var statusCode = 0
        var responseHeaders: [GatewayHeader] = []
        var committed = false
        var prefix = Data()
        var failure: GatewayFailure?
        var clientCancelled = false
        var completedEvent: (body: Data?, error: Error?)?

        upstream.start(request: request)

        streamLoop: for await event in upstream.events {
            switch event {
            case .response(let status, let headers):
                statusCode = status
                responseHeaders = headers

            case .data(let data):
                guard (200..<300).contains(statusCode) else { break }
                if committed {
                    // 提交后仍需继续解析 SSE，才能拿到 usage 与最后一段生成时间
                    for sse in parser.feed(data) {
                        _ = analyzer.consume(sse)
                    }
                    if !(await connection.writeStreamChunk(data)) {
                        clientCancelled = true
                        break streamLoop
                    }
                    if parser.overflowed {
                        failure = GatewayFailure(
                            kind: .responseTooLarge,
                            action: .relay,
                            message: "SSE 事件超过 1MB 限制"
                        )
                        break streamLoop
                    }
                    continue
                }
                prefix.append(data)
                let events = parser.feed(data)
                for sse in events {
                    let signal = analyzer.consume(sse)
                    switch signal {
                    case .commit:
                        if !committed {
                            committed = true
                            let headers = Self.streamHeaders(responseHeaders)
                            guard await connection.startStream(status: 200, headers: headers) else {
                                clientCancelled = true
                                break streamLoop
                            }
                            if !prefix.isEmpty, !(await connection.writeStreamChunk(prefix)) {
                                clientCancelled = true
                                break streamLoop
                            }
                            prefix.removeAll(keepingCapacity: false)
                            if let error = analyzer.streamError {
                                failure = GatewayFailure(
                                    kind: .upstreamJSONError,
                                    action: .nextChannel,
                                    message: error.message
                                )
                                break streamLoop
                            }
                        }
                    case .error:
                        if !committed {
                            if let error = analyzer.streamError {
                                failure = GatewayFailure(
                                    kind: .upstreamJSONError,
                                    action: .nextChannel,
                                    message: error.message
                                )
                            } else {
                                failure = GatewayFailure(
                                    kind: .upstreamJSONError,
                                    action: .nextChannel,
                                    message: "上游返回错误事件"
                                )
                            }
                            break streamLoop
                        }
                    case .terminal, .none:
                        break
                    }
                }
                if parser.overflowed {
                    failure = GatewayFailure(
                        kind: .responseTooLarge,
                        action: committed ? .relay : .nextChannel,
                        message: "SSE 事件超过 1MB 限制"
                    )
                    break streamLoop
                }

            case .timedOut(let kind):
                failure = GatewayFailure(
                    kind: kind,
                    action: committed ? .relay : .nextChannel,
                    message: kind == .firstContentTimeout ? "首内容超时" : (kind == .idleTimeout ? "上游生成超时" : "上游连接超时")
                )
                break streamLoop

            case .completed(let body, let error):
                completedEvent = (body, error)
                break streamLoop

            case .cancelled:
                break streamLoop
            }
        }

        if clientCancelled {
            upstream.cancel()
            return .clientCancelled(stream: Self.streamMetrics(
                analyzer: analyzer,
                statusCode: statusCode,
                hasCommitted: committed
            ))
        }

        if let failure {
            upstream.cancel()
            let metrics = Self.streamMetrics(analyzer: analyzer, statusCode: statusCode, hasCommitted: committed)
            if committed {
                let code = failure.kind == .idleTimeout ? "upstream_timeout" : "upstream_error"
                _ = await connection.writeStreamChunk(
                    GatewayErrorPayload.streamEvent(protocolName: protocolName, code: code, message: failure.message)
                )
                await connection.endStream()
            }
            return .failure(failure, committed: committed, stream: metrics)
        }

        // 正常结束：冲刷最后一段事件并做终态判定
        for sse in parser.finish() {
            _ = analyzer.consume(sse)
        }

        let metrics = Self.streamMetrics(analyzer: analyzer, statusCode: statusCode, hasCommitted: committed)

        if let error = completedEvent?.error {
            upstream.cancel()
            let classified = GatewayErrorClassifier.classify(error: error, hasCommitted: committed)
            if committed {
                _ = await connection.writeStreamChunk(
                    GatewayErrorPayload.streamEvent(protocolName: protocolName, code: "upstream_error", message: classified.message)
                )
                await connection.endStream()
            }
            return .failure(classified, committed: committed, stream: metrics)
        }

        guard (200..<300).contains(statusCode) else {
            let body = completedEvent?.body ?? Data()
            let classified = GatewayErrorClassifier.classify(statusCode: statusCode, body: body, upstreamURL: request.url)
            return .failure(classified, committed: false, stream: nil)
        }

        if !committed {
            // 上游 200 但没有任何有效生成内容
            let message = analyzer.streamError?.message ?? "上游未返回有效内容"
            upstream.cancel()
            return .failure(
                GatewayFailure(kind: .upstreamJSONError, action: .nextChannel, message: message),
                committed: false,
                stream: nil
            )
        }

        if let streamError = analyzer.streamError {
            upstream.cancel()
            await connection.writeStreamChunk(
                GatewayErrorPayload.streamEvent(protocolName: protocolName, code: streamError.code ?? "upstream_error", message: streamError.message)
            )
            await connection.endStream()
            return .failure(
                GatewayFailure(kind: .upstreamJSONError, action: .relay, message: streamError.message),
                committed: true,
                stream: metrics
            )
        }

        guard let metrics else {
            upstream.cancel()
            return .failure(
                GatewayFailure(kind: .upstreamJSONError, action: .nextChannel, message: "上游未返回有效内容"),
                committed: false,
                stream: nil
            )
        }

        await connection.endStream()
        return .streamSuccess(metrics)
    }

    // MARK: 响应

    private func handleHealth(connection: GatewayHTTPConnection) async {
        let object: [String: Any] = [
            "status": "ok",
            "enabled": snapshot.enabled,
            "models": snapshot.availableModels.count
        ]
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        await connection.respond(status: 200, headers: [], body: body)
    }

    private func handleModels(connection: GatewayHTTPConnection) async {
        let data: [[String: Any]] = GatewayRouter.availableModels(from: snapshot).map { alias in
            [
                "id": alias,
                "object": "model",
                "created": 0,
                "owned_by": "calmbar"
            ]
        }
        let object: [String: Any] = ["object": "list", "data": data]
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        await connection.respond(status: 200, headers: [], body: body)
    }

    private func relay(_ failure: GatewayFailure, connection: GatewayHTTPConnection) async {
        if let status = failure.httpStatus, let body = failure.upstreamBody, !body.isEmpty {
            await connection.respond(
                status: status,
                headers: [GatewayHeader(name: "Content-Type", value: "application/json; charset=utf-8")],
                body: body
            )
        } else {
            await respondError(
                connection,
                status: failure.httpStatus ?? 502,
                code: failure.kind == .upstreamRedirect ? "upstream_redirect" : "upstream_error",
                message: failure.message
            )
        }
    }

    private func respondError(_ connection: GatewayHTTPConnection, status: Int, code: String, message: String) async {
        let body = GatewayErrorPayload.json(code: code, type: "gateway_error", message: message)
        await connection.respond(status: status, headers: [], body: body)
    }

    // MARK: 校验

    private func securityRejection(for request: GatewayHTTPRequest) -> (status: Int, code: String, message: String)? {
        if let site = request.headers["sec-fetch-site"]?.lowercased(), site != "none" {
            return (403, "forbidden", "拒绝浏览器发起的面板外请求")
        }
        if let origin = request.headers["origin"], !origin.isEmpty {
            return (403, "forbidden", "不允许带 Origin 的跨域请求")
        }
        if let host = request.headers["host"]?.lowercased() {
            let hostname: String
            if host.hasPrefix("[") {
                hostname = String(host.prefix(while: { $0 != "]" }).dropFirst())
            } else {
                hostname = String(host.split(separator: ":").first ?? "")
            }
            if !["127.0.0.1", "localhost", "::1"].contains(hostname) {
                return (403, "forbidden", "仅允许本机回环地址访问")
            }
        }
        return nil
    }

    private func authorized(_ request: GatewayHTTPRequest) -> Bool {
        // 未设置访问密钥 = 不鉴权（仅本机回环可访问）
        guard !snapshot.serverKey.isEmpty else { return true }
        let header = request.headers["authorization"] ?? ""
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return false }
        let token = String(header.dropFirst(prefix.count))
        return Self.constantTimeEquals(token, snapshot.serverKey)
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    // MARK: 记录

    private static func makeRecord(
        endpoint: String,
        protocolName: GatewayStreamProtocol,
        isStream: Bool,
        requestedModel: String,
        channel: GatewayChannelRuntime?,
        upstreamModel: String?,
        status: GatewayRequestStatus,
        errorMessage: String?,
        httpStatus: Int?,
        usage: GatewayUsage?,
        estimatedInput: Int,
        estimatedOutput: Int?,
        ttftMs: Int?,
        generationMs: Int?,
        durationMs: Int,
        outputTPS: Double?,
        speedSource: GatewaySpeedSource?,
        retryReasons: [String],
        clientCancelled: Bool
    ) -> GatewayRequestRecord {
        let usage = usage ?? GatewayUsage()
        let inputTokens = usage.inputTokens ?? (estimatedInput > 0 ? estimatedInput : nil)
        let outputTokens: Int? = {
            if let output = usage.outputTokens { return output }
            if let estimatedOutput, estimatedOutput > 0 { return estimatedOutput }
            return nil
        }()
        let totalTokens: Int? = {
            if let total = usage.totalTokens { return total }
            guard let inputTokens, let outputTokens else { return nil }
            return inputTokens + outputTokens
        }()
        let tokenSource: GatewayTokenSource? = {
            if usage.inputTokens != nil || usage.outputTokens != nil { return .usage }
            if inputTokens != nil || outputTokens != nil { return .estimated }
            return nil
        }()

        return GatewayRequestRecord(
            createdAt: Date(),
            requestID: UUID().uuidString,
            endpoint: endpoint,
            protocolName: protocolName.rawValue,
            isStream: isStream,
            requestedModel: requestedModel,
            upstreamModel: upstreamModel ?? channel?.model,
            channelID: channel?.id,
            channelName: channel?.name,
            status: status,
            errorMessage: errorMessage,
            httpStatus: httpStatus,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            tokenSource: tokenSource,
            ttftMs: ttftMs,
            generationMs: generationMs,
            durationMs: durationMs,
            outputTPS: outputTPS,
            speedSource: speedSource,
            retryReason: retryReasons.isEmpty ? nil : retryReasons.joined(separator: " → "),
            clientCancelled: clientCancelled
        )
    }

    // MARK: 工具

    private static func streamMetrics(
        analyzer: GatewayStreamAnalyzer,
        statusCode: Int,
        hasCommitted: Bool
    ) -> GatewayStreamMetrics? {
        guard hasCommitted, let first = analyzer.firstContentAt else { return nil }
        return GatewayStreamMetrics(
            firstContentAt: first,
            lastContentAt: analyzer.lastContentAt,
            usage: analyzer.usage,
            responseID: analyzer.responseID,
            upstreamModel: analyzer.upstreamModel,
            estimatedOutputTokens: analyzer.estimatedOutputTokens,
            statusCode: statusCode
        )
    }

    private static func parseBufferedInfo(_ body: Data) -> (usage: GatewayUsage?, responseID: String?, model: String?) {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return (nil, nil, nil)
        }
        var usage: GatewayUsage?
        if let raw = object["usage"] as? [String: Any] {
            usage = GatewayUsage(
                inputTokens: raw["prompt_tokens"] as? Int ?? raw["input_tokens"] as? Int,
                outputTokens: raw["completion_tokens"] as? Int ?? raw["output_tokens"] as? Int,
                totalTokens: raw["total_tokens"] as? Int
            )
        }
        return (usage, object["id"] as? String, object["model"] as? String)
    }

    private static func sanitizedHeaders(_ headers: [GatewayHeader]) -> [GatewayHeader] {
        let blocked: Set<String> = [
            "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
            "te", "trailer", "transfer-encoding", "upgrade", "content-length", "content-encoding"
        ]
        return headers.filter { !blocked.contains($0.name.lowercased()) }
    }

    private static func streamHeaders(_ headers: [GatewayHeader]) -> [GatewayHeader] {
        var result = sanitizedHeaders(headers)
        if !result.contains(where: { $0.name.lowercased() == "content-type" }) {
            result.append(GatewayHeader(name: "Content-Type", value: "text/event-stream; charset=utf-8"))
        }
        return result
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }
}

// MARK: - 内部类型

private struct GatewayStreamMetrics: Sendable {
    let firstContentAt: Date
    let lastContentAt: Date?
    let usage: GatewayUsage?
    let responseID: String?
    let upstreamModel: String?
    let estimatedOutputTokens: Int
    let statusCode: Int
}

private enum GatewayAttemptResult: Sendable {
    case bufferedSuccess(
        status: Int,
        headers: [GatewayHeader],
        body: Data,
        usage: GatewayUsage?,
        responseID: String?,
        upstreamModel: String?,
        headersAt: Date
    )
    case streamSuccess(GatewayStreamMetrics)
    case failure(GatewayFailure, committed: Bool, stream: GatewayStreamMetrics?)
    case clientCancelled(stream: GatewayStreamMetrics?)
}

private enum GatewayLocalError: Error {
    case invalidJSON
}
