import CoreGraphics

/// 在系统实际接受的宽度附近做有界二分查找，避免把超长分隔符交给 macOS 27 后移出菜单栏布局。
struct MenuBarCollapseLengthSearch {
    let expandedLength: CGFloat
    let upperBound: CGFloat
    let safetyMargin: CGFloat
    let resolution: CGFloat
    let maxProbes: Int

    private var lowerBound: CGFloat
    private var rejectedBound: CGFloat
    private var bestAcceptedLength: CGFloat
    private var pendingProbe: CGFloat?
    private(set) var probeCount = 0

    init(
        expandedLength: CGFloat,
        upperBound: CGFloat,
        safetyMargin: CGFloat = 8,
        resolution: CGFloat = 8,
        maxProbes: Int = 10
    ) {
        self.expandedLength = expandedLength
        self.upperBound = max(expandedLength + 1, upperBound)
        self.safetyMargin = safetyMargin
        self.resolution = resolution
        self.maxProbes = maxProbes
        lowerBound = expandedLength
        rejectedBound = self.upperBound
        bestAcceptedLength = expandedLength
    }

    /// 返回下一次探测宽度；查找结束或等待系统布局时返回 nil。
    mutating func nextProbe() -> CGFloat? {
        guard pendingProbe == nil,
              probeCount < maxProbes,
              rejectedBound - lowerBound > resolution else {
            return nil
        }
        pendingProbe = ((lowerBound + rejectedBound) / 2).rounded(.awayFromZero)
        return pendingProbe
    }

    mutating func record(accepted: Bool) {
        guard let probe = pendingProbe else { return }
        pendingProbe = nil
        probeCount += 1
        if accepted {
            lowerBound = probe
            bestAcceptedLength = probe
        } else {
            rejectedBound = probe
        }
    }

    var isComplete: Bool {
        pendingProbe == nil && (probeCount >= maxProbes || rejectedBound - lowerBound <= resolution)
    }

    var foundInflatedLength: Bool {
        bestAcceptedLength > expandedLength
    }

    var calibratedLength: CGFloat {
        max(expandedLength + 1, bestAcceptedLength - safetyMargin)
    }
}
