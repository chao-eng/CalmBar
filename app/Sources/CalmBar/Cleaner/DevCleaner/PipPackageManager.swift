import Foundation

public final class PipPackageManager: @unchecked Sendable {
    public static let shared = PipPackageManager()

    public init() {}

    /// Detect active Python3 executable path
    public func detectPythonPath() async -> String {
        // Try which python3
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe

        if let _ = try? process.run() {
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
                    return out
                }
            }
        }
        return "/usr/bin/python3"
    }

    /// List installed pip packages
    public func listPackages(pythonPath: String) async -> [PipPackageItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "list", "--format=json", "--disable-pip-version-check"]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe

        guard let _ = try? process.run() else { return [] }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var items: [PipPackageItem] = []
        for dict in jsonArray {
            let name = dict["name"] as? String ?? ""
            let version = dict["version"] as? String ?? ""
            if !name.isEmpty {
                items.append(PipPackageItem(name: name, version: version))
            }
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Uninstall specific pip package
    public func uninstallPackage(name: String, pythonPath: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "uninstall", "-y", name, "--disable-pip-version-check"]
        process.environment = ProcessInfo.processInfo.environment

        guard let _ = try? process.run() else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
