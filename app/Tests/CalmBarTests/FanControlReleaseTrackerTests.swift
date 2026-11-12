import Testing
@testable import CalmBar

@Suite("Fan Control Release Tracker Tests")
struct FanControlReleaseTrackerTests {
    @Test("写入成功会清零连续失败计数")
    func successResetsFailures() {
        var tracker = FanControlReleaseTracker(failureThreshold: 3)
        #expect(tracker.recordWriteFailure() == false)
        #expect(tracker.recordWriteFailure() == false)
        tracker.recordWriteSuccess()
        #expect(tracker.consecutiveWriteFailures == 0)
        #expect(tracker.recordWriteFailure() == false)
    }

    @Test("连续失败达到阈值才返回交还信号")
    func failureThreshold() {
        var tracker = FanControlReleaseTracker(failureThreshold: 3)
        #expect(tracker.recordWriteFailure() == false)
        #expect(tracker.recordWriteFailure() == false)
        #expect(tracker.recordWriteFailure() == true)
        #expect(tracker.recordWriteFailure() == true)
        #expect(tracker.consecutiveWriteFailures == 4)
    }

    @Test("交还状态幂等、交接确认与清除")
    func releaseLifecycle() {
        var tracker = FanControlReleaseTracker()
        #expect(tracker.isReleased == false)

        #expect(tracker.beginRelease(cause: .temperature) == true)
        #expect(tracker.isReleased)
        #expect(tracker.beginRelease(cause: .temperature) == false)
        #expect(tracker.handoffConfirmed == false)

        tracker.confirmHandoff()
        #expect(tracker.handoffConfirmed)
        tracker.markHandoffFailed()
        #expect(tracker.handoffConfirmed == false)

        tracker.clear()
        #expect(tracker.isReleased == false)
        #expect(tracker.handoffConfirmed == false)
        #expect(tracker.consecutiveWriteFailures == 0)
    }

    @Test("不同原因可替换当前交还状态")
    func causeReplacement() {
        var tracker = FanControlReleaseTracker()
        _ = tracker.beginRelease(cause: .temperature)
        tracker.confirmHandoff()

        #expect(tracker.beginRelease(cause: .writeFailure) == true)
        #expect(tracker.cause == .writeFailure)
        #expect(tracker.handoffConfirmed == false)
    }
}
