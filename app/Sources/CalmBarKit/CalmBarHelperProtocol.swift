import Foundation

public enum CalmBarConfig {
    public static let appBundleID = "com.chaoeng.CalmBar"
    public static let helperMachService = "com.chaoeng.CalmBar.helper"
    public static let helperLabel = "com.chaoeng.CalmBar.helper"
    public static let helperVersion = 1
}

@objc public protocol CalmBarHelperProtocol: NSObjectProtocol {
    func ping(reply: @escaping (String) -> Void)
    func setLinkedFraction(_ fraction: Double, reply: @escaping (Bool, String?) -> Void)
    func setFanRPM(_ fanIndex: UInt, rpm: Float, reply: @escaping (Bool, String?) -> Void)
    func restoreAuto(reply: @escaping (Bool, String?) -> Void)
    func listFans(reply: @escaping ([Data]?, String?) -> Void)
    func listTemperatures(reply: @escaping ([Data]?, String?) -> Void)
    func removeQuarantine(at path: String, deepSign: Bool, reply: @escaping (Bool, String?) -> Void)
}

