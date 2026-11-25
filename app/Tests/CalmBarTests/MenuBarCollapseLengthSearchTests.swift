import CoreGraphics
import Testing
@testable import CalmBar

@Suite("菜单栏收纳宽度校准")
struct MenuBarCollapseLengthSearchTests {

    @Test("复现本机 77pt 接受值并保留 8pt 安全余量")
    func findsSystemAcceptedLength() {
        var search = MenuBarCollapseLengthSearch(expandedLength: 20, upperBound: 4410)
        var probes: [CGFloat] = []

        while let probe = search.nextProbe() {
            probes.append(probe)
            search.record(accepted: probe <= 77)
        }

        #expect(probes.count == 10)
        #expect(search.foundInflatedLength)
        #expect(search.calibratedLength == 69)
        #expect(probes.contains(4410 / 2))
    }

    @Test("宽屏接受 600pt 时不会错误退回旧的超长宽度")
    func acceptsLargerInflatedLength() {
        var search = MenuBarCollapseLengthSearch(expandedLength: 20, upperBound: 10_000)

        while let probe = search.nextProbe() {
            search.record(accepted: probe <= 600)
        }

        #expect(search.foundInflatedLength)
        #expect(search.calibratedLength > 550)
        #expect(search.calibratedLength <= 600)
    }

    @Test("所有加宽都被系统拒绝时保持展开并报告校准失败")
    func reportsNoInflatedLength() {
        var search = MenuBarCollapseLengthSearch(expandedLength: 20, upperBound: 4410)

        while let probe = search.nextProbe() {
            search.record(accepted: false)
        }

        #expect(search.isComplete)
        #expect(!search.foundInflatedLength)
        #expect(search.calibratedLength == 21)
    }

    @Test("探测次数有硬上限，异常布局不会无限循环")
    func boundsProbeCount() {
        var search = MenuBarCollapseLengthSearch(expandedLength: 20, upperBound: 10_000, maxProbes: 3)
        var probes: [CGFloat] = []

        while let probe = search.nextProbe() {
            probes.append(probe)
            search.record(accepted: probe <= 500)
        }

        #expect(probes.count == 3)
        #expect(search.isComplete)
    }
}
