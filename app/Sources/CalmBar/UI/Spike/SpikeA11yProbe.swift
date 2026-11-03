import ApplicationServices
import Foundation

// MARK: - AX 树读取与焦点设置（进程内 AX 客户端，替代无效的 NSView 遍历）

enum SpikeA11yProbe {
    /// 返回 (状态, 节点数)；status=ok / status=error(raw) / status=empty
    static func dumpAX(to path: String) -> (status: String, nodes: Int) {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)

        guard error == .success, let windows = windowsValue as? [AXUIElement], let window = windows.first else {
            let status = error == .success ? "status=empty" : "status=error(\(error.rawValue))"
            return (status, 0)
        }

        var lines: [String] = []
        traverse(window, depth: 0, lines: &lines)
        let text = lines.joined(separator: "\n")
        try? text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        return (lines.isEmpty ? "status=empty" : "status=ok", lines.count)
    }

    /// 期望朗读顺序（视图层声明顺序）
    static let declaredOrder = ["header", "tabbar", "sectionTitle", "content", "footer"]

    /// 从实时 AX 树读取分区出现顺序，返回可比对的报告
    static func orderReport() -> String {
        guard let window = firstWindow() else { return "ok=false detail=no-window" }
        var hits: [String: Int] = [:]
        var index = 0
        walkOrder(window, depth: 0, index: &index, hits: &hits)
        let present = ["header", "tabbar", "content", "footer"]
        let positions = present.compactMap { hits[$0] }
        let ordered = positions == positions.sorted()
        let section = hits["sectionTitle"].map(String.init) ?? "missing"
        return "ok=\(ordered) header=\(hits["header"] ?? -1) tabbar=\(hits["tabbar"] ?? -1) sectionTitle=\(section) content=\(hits["content"] ?? -1) footer=\(hits["footer"] ?? -1)"
    }

    private static func firstWindow() -> AXUIElement? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private static func walkOrder(_ element: AXUIElement, depth: Int, index: inout Int, hits: inout [String: Int]) {
        guard depth < 8 else { return }
        index += 1
        if let category = category(of: element), hits[category] == nil {
            hits[category] = index
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                walkOrder(child, depth: depth + 1, index: &index, hits: &hits)
            }
        }
    }

    private static func category(of element: AXUIElement) -> String? {
        let description = stringValue(element, kAXDescriptionAttribute) ?? ""
        let value = stringValue(element, kAXValueAttribute) ?? ""
        if description == "CalmBar 状态栏" { return "header" }
        if description.contains("个分区中第") { return "tabbar" }
        if value.hasPrefix("grid=") { return "footer" }
        if description == "应用去隔离" { return "content" }
        return nil
    }

    /// 通过 AX 把焦点设到指定 description 前缀的元素，返回 ok / error(raw) / not-found
    static func focus(descriptionPrefix: String) -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windowsValue: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        guard windowError == .success,
              let windows = windowsValue as? [AXUIElement],
              let window = windows.first else {
            return "no-window"
        }
        guard let element = find(window, depth: 0, descriptionPrefix: descriptionPrefix) else {
            return "not-found"
        }

        var error = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if error != .success {
            let value: CFTypeRef = element
            error = AXUIElementSetAttributeValue(app, kAXFocusedUIElementAttribute as CFString, value)
        }
        return error == .success ? "ok" : "error(\(error.rawValue))"
    }

    /// 读取当前 AX 焦点元素的描述摘要，用于 Space/Return 激活验证
    static func focusedDescription() -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else {
            return "none"
        }
        let element = value as! AXUIElement
        let role = stringValue(element, kAXRoleAttribute) ?? "-"
        let title = stringValue(element, kAXTitleAttribute) ?? ""
        let description = stringValue(element, kAXDescriptionAttribute) ?? ""
        return "\(role)|\(title)|\(description)"
    }

    private static func find(_ element: AXUIElement, depth: Int, descriptionPrefix: String) -> AXUIElement? {
        guard depth < 8 else { return nil }
        if let description = stringValue(element, kAXDescriptionAttribute), description.hasPrefix(descriptionPrefix) {
            return element
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let hit = find(child, depth: depth + 1, descriptionPrefix: descriptionPrefix) {
                    return hit
                }
            }
        }
        return nil
    }

    private static func traverse(_ element: AXUIElement, depth: Int, lines: inout [String]) {
        guard depth < 8 else { return }
        let role = stringValue(element, kAXRoleAttribute) ?? "-"
        let title = stringValue(element, kAXTitleAttribute) ?? ""
        let description = stringValue(element, kAXDescriptionAttribute) ?? ""
        let value = attribute(element, kAXValueAttribute).map { String(describing: $0) } ?? ""
        let selected = attribute(element, kAXSelectedAttribute).map { String(describing: $0) } ?? ""
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)role=\(role) title=\(title) desc=\(description) value=\(value) selected=\(selected)")

        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                traverse(child, depth: depth + 1, lines: &lines)
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? value : nil
    }

    private static func stringValue(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }
}
