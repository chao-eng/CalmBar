import ApplicationServices
import Foundation

// MARK: - M1 AX 树导出与分区顺序校验

enum M1A11yProbe {
    static func dumpAX(to path: String) -> (status: String, nodes: Int) {
        guard let window = firstWindow() else { return ("status=empty", 0) }
        var lines: [String] = []
        traverse(window, depth: 0, lines: &lines)
        let text = lines.joined(separator: "\n")
        try? text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        return (lines.isEmpty ? "status=empty" : "status=ok", lines.count)
    }

    /// M4：通过 AX 触发指定按钮，验证动作闭包接线
    static func press(descriptionPrefix: String) -> String {
        guard let window = firstWindow() else { return "no-window" }
        guard let element = find(window, depth: 0, descriptionPrefix: descriptionPrefix) else {
            return "not-found"
        }
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return error == .success ? "ok" : "error(\(error.rawValue))"
    }

    /// M6：按无障碍 value 文本查找节点（SwiftUI 静态文本使用 value 承载文案）
    static func containsValue(_ prefix: String) -> Bool {
        guard let window = firstWindow() else { return false }
        return findValue(window, depth: 0, prefix: prefix) != nil
    }

    /// 校验 header → tabbar → sectionTitle → content → footer 的实际 AX 位置
    static func orderReport() -> String {
        guard let window = firstWindow() else { return "ok=false detail=no-window" }
        var hits: [String: Int] = [:]
        var index = 0
        walkOrder(window, depth: 0, index: &index, hits: &hits)
        let expected = ["header", "tabbar", "sectionTitle", "content", "footer"]
        let positions = expected.compactMap { hits[$0] }
        let ordered = positions.count == expected.count && positions == positions.sorted()
        return "ok=\(ordered) header=\(hits["header"] ?? -1) tabbar=\(hits["tabbar"] ?? -1) "
            + "sectionTitle=\(hits["sectionTitle"] ?? -1) content=\(hits["content"] ?? -1) footer=\(hits["footer"] ?? -1)"
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
        if description == "CalmBar 状态栏" { return "header" }
        if description.contains("个分区中第") { return "tabbar" }
        if description == "分区标题" { return "sectionTitle" }
        if description == "内容区" { return "content" }
        if description == "底栏" { return "footer" }
        return nil
    }

    private static func traverse(_ element: AXUIElement, depth: Int, lines: inout [String]) {
        guard depth < 8 else { return }
        let role = stringValue(element, kAXRoleAttribute) ?? "-"
        let description = stringValue(element, kAXDescriptionAttribute) ?? ""
        let value = attribute(element, kAXValueAttribute).map { String(describing: $0) } ?? ""
        let selected = attribute(element, kAXSelectedAttribute).map { String(describing: $0) } ?? ""
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)role=\(role) desc=\(description) value=\(value) selected=\(selected)")
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                traverse(child, depth: depth + 1, lines: &lines)
            }
        }
    }

    private static func find(_ element: AXUIElement, depth: Int, descriptionPrefix: String) -> AXUIElement? {
        guard depth < 12 else { return nil }
        let description = stringValue(element, kAXDescriptionAttribute) ?? ""
        if description.hasPrefix(descriptionPrefix) {
            return element
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let match = find(child, depth: depth + 1, descriptionPrefix: descriptionPrefix) {
                    return match
                }
            }
        }
        return nil
    }

    private static func findValue(_ element: AXUIElement, depth: Int, prefix: String) -> AXUIElement? {
        guard depth < 12 else { return nil }
        if let value = stringValue(element, kAXValueAttribute), value.hasPrefix(prefix) {
            return element
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                if let match = findValue(child, depth: depth + 1, prefix: prefix) {
                    return match
                }
            }
        }
        return nil
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
