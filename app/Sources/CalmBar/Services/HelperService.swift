import Foundation
import CalmBarKit

@MainActor
public final class HelperService {
    public static let shared = HelperService()

    private let client: HelperClient

    public init(client: HelperClient = .shared) {
        self.client = client
    }

    public var isAvailable: Bool {
        client.isHelperAvailable
    }

    public func checkStatus() {
        client.checkHelperStatus()
    }
}
