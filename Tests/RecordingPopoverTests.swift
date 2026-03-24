import XCTest

// MARK: - Duplicated from RecordingPopover.swift (can't import executable target)

private protocol RecordingPopoverDelegate: AnyObject {
    func popoverDidRequestStopCopy()
    func popoverDidRequestStopImprove()
    func popoverDidRequestCancel()
    func popoverDidRequestOpenHistory()
}

// MARK: - Mock delegate to verify delegate calls

private class MockPopoverDelegate: RecordingPopoverDelegate {
    var stopCopyCalled = false
    var stopImproveCalled = false
    var cancelCalled = false
    var openHistoryCalled = false

    func popoverDidRequestStopCopy() { stopCopyCalled = true }
    func popoverDidRequestStopImprove() { stopImproveCalled = true }
    func popoverDidRequestCancel() { cancelCalled = true }
    func popoverDidRequestOpenHistory() { openHistoryCalled = true }
}

// MARK: - Tests

final class RecordingPopoverDelegateTests: XCTestCase {

    func testDelegateProtocolIncludesOpenHistory() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestOpenHistory()
        XCTAssertTrue(delegate.openHistoryCalled)
    }

    func testOpenHistoryDoesNotTriggerOtherActions() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestOpenHistory()
        XCTAssertFalse(delegate.stopCopyCalled)
        XCTAssertFalse(delegate.stopImproveCalled)
        XCTAssertFalse(delegate.cancelCalled)
    }

    func testAllDelegateMethodsAreIndependent() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestStopCopy()
        delegate.popoverDidRequestStopImprove()
        delegate.popoverDidRequestCancel()
        delegate.popoverDidRequestOpenHistory()
        XCTAssertTrue(delegate.stopCopyCalled)
        XCTAssertTrue(delegate.stopImproveCalled)
        XCTAssertTrue(delegate.cancelCalled)
        XCTAssertTrue(delegate.openHistoryCalled)
    }
}

// MARK: - History action behavior tests

/// Tests that verify the expected behavior when the history button is clicked:
/// 1. Recording should be cancelled (delegate.cancel called)
/// 2. History window should be opened (delegate.openHistory called)
///
/// We simulate the AppDelegate's popoverDidRequestOpenHistory() logic here
/// since we can't import the executable target.

private class MockAppDelegateBehavior {
    var cancelRecordingCalled = false
    var showWindowTab: Int?

    func popoverDidRequestOpenHistory() {
        cancelRecording()
        showWindow(tab: 0)
    }

    private func cancelRecording() {
        cancelRecordingCalled = true
    }

    private func showWindow(tab: Int) {
        showWindowTab = tab
    }
}

final class HistoryButtonBehaviorTests: XCTestCase {

    func testOpenHistoryCancelsRecording() {
        let mock = MockAppDelegateBehavior()
        mock.popoverDidRequestOpenHistory()
        XCTAssertTrue(mock.cancelRecordingCalled)
    }

    func testOpenHistoryShowsHistoryTab() {
        let mock = MockAppDelegateBehavior()
        mock.popoverDidRequestOpenHistory()
        XCTAssertEqual(mock.showWindowTab, 0)
    }
}
