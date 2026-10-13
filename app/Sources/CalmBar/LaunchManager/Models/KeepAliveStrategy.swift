import Foundation

public enum KeepAliveStrategy: Hashable, Sendable {
    case disabled
    case always
    case conditional([String: String])

    public var isEffectivelyActive: Bool {
        switch self {
        case .disabled:
            return false
        case .always, .conditional:
            return true
        }
    }

    public var displayDescription: String {
        switch self {
        case .disabled:
            return "不保持 (退出后不自动重启)"
        case .always:
            return "始终保持 (退出后立即重启)"
        case .conditional(let conditions):
            let summary = conditions.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            return "条件保持 (\(summary))"
        }
    }

    public static func parse(from value: Any?) -> KeepAliveStrategy {
        guard let value = value else { return .disabled }
        if let boolVal = value as? Bool {
            return boolVal ? .always : .disabled
        }
        if let dictVal = value as? [String: Any] {
            var stringDict: [String: String] = [:]
            for (k, v) in dictVal {
                stringDict[k] = "\(v)"
            }
            return .conditional(stringDict)
        }
        return .disabled
    }

    public func toPlistValue() -> Any {
        switch self {
        case .disabled:
            return false
        case .always:
            return true
        case .conditional(let dict):
            return dict
        }
    }
}
