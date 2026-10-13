import Foundation

public struct ListeningServiceItem: Identifiable, Hashable, Sendable {
    public var id: String { "\(port):\(protocolType):\(pid)" }
    public let port: Int
    public let protocolType: String // "TCP"
    public let pid: Int
    public let processName: String
    public let commandLine: String?
    public let workingDirectory: String?
    public let user: String
    public let isDocker: Bool
    public let containerName: String?

    public init(
        port: Int,
        protocolType: String = "TCP",
        pid: Int,
        processName: String,
        commandLine: String? = nil,
        workingDirectory: String? = nil,
        user: String = "",
        isDocker: Bool = false,
        containerName: String? = nil
    ) {
        self.port = port
        self.protocolType = protocolType
        self.pid = pid
        self.processName = processName
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.user = user
        self.isDocker = isDocker
        self.containerName = containerName
    }
}
