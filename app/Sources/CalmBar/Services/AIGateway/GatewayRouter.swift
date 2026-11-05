import Foundation

public enum GatewayRouteResult: Sendable {
    case routed(alias: String, channels: [GatewayChannelRuntime], stickyChannelID: String?)
    case modelNotFound(available: [String])
    case noAvailableChannel(alias: String, reason: String)
}

public enum GatewayRouter {
    /// 按别名解析候选渠道：粘性优先 → 配置顺序 → 冷却过滤（全冷却时回退全量）
    public static func route(
        model: String,
        previousResponseID: String?,
        snapshot: GatewaySnapshot,
        cooldown: GatewayCooldownStore = .shared,
        responseMap: GatewayResponseChannelMap = .shared,
        now: Date = Date()
    ) -> GatewayRouteResult {
        guard let ids = snapshot.modelRoutes[model] else {
            return .modelNotFound(available: snapshot.availableModels)
        }

        let candidates = ids.compactMap { snapshot.channels[$0] }
        guard !candidates.isEmpty else {
            return .noAvailableChannel(alias: model, reason: "模型别名未绑定可用渠道")
        }

        let stickyID = responseMap.channelID(for: previousResponseID)
        let ordered = orderedCandidates(
            candidates,
            alias: model,
            snapshot: snapshot,
            stickyChannelID: stickyID,
            cooldown: cooldown,
            now: now
        )

        guard !ordered.isEmpty else {
            return .noAvailableChannel(alias: model, reason: "所有渠道均在冷却中")
        }
        let sticky = ordered.first?.id == stickyID ? stickyID : nil
        return .routed(alias: model, channels: ordered, stickyChannelID: sticky)
    }

    private static func orderedCandidates(
        _ candidates: [GatewayChannelRuntime],
        alias: String,
        snapshot: GatewaySnapshot,
        stickyChannelID: String?,
        cooldown: GatewayCooldownStore,
        now: Date
    ) -> [GatewayChannelRuntime] {
        var ordered = candidates
        if let stickyChannelID,
           let index = ordered.firstIndex(where: { $0.id == stickyChannelID }) {
            let sticky = ordered.remove(at: index)
            ordered.insert(sticky, at: 0)
        }

        let available = ordered.filter { channel in
            let upstreamModel = snapshot.upstreamModel(alias: alias, channelID: channel.id) ?? channel.model
            return !cooldown.isCoolingDown(channelID: channel.id, model: upstreamModel, now: now)
        }
        // 全部渠道都在冷却窗口时跳过冷却过滤，按正常顺序尝试
        return available.isEmpty ? ordered : available
    }

    /// 模型列表按配置顺序输出去重后的别名
    public static func availableModels(from snapshot: GatewaySnapshot) -> [String] {
        snapshot.availableModels
    }
}
