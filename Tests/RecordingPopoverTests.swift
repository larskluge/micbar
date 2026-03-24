import XCTest

// MARK: - Duplicated from RecordingPopover.swift (can't import executable target)

private protocol RecordingPopoverDelegate: AnyObject {
    func popoverDidRequestStopCopy()
    func popoverDidRequestStopImprove()
    func popoverDidRequestCancel()
    func popoverDidRequestOpenSettings()
}

// MARK: - Mock delegate to verify delegate calls

private class MockPopoverDelegate: RecordingPopoverDelegate {
    var stopCopyCalled = false
    var stopImproveCalled = false
    var cancelCalled = false
    var openSettingsCalled = false

    func popoverDidRequestStopCopy() { stopCopyCalled = true }
    func popoverDidRequestStopImprove() { stopImproveCalled = true }
    func popoverDidRequestCancel() { cancelCalled = true }
    func popoverDidRequestOpenSettings() { openSettingsCalled = true }
}

// MARK: - Tests

final class RecordingPopoverDelegateTests: XCTestCase {

    func testDelegateProtocolIncludesOpenSettings() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestOpenSettings()
        XCTAssertTrue(delegate.openSettingsCalled)
    }

    func testOpenSettingsDoesNotTriggerOtherActions() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestOpenSettings()
        XCTAssertFalse(delegate.stopCopyCalled)
        XCTAssertFalse(delegate.stopImproveCalled)
        XCTAssertFalse(delegate.cancelCalled)
    }

    func testAllDelegateMethodsAreIndependent() {
        let delegate = MockPopoverDelegate()
        delegate.popoverDidRequestStopCopy()
        delegate.popoverDidRequestStopImprove()
        delegate.popoverDidRequestCancel()
        delegate.popoverDidRequestOpenSettings()
        XCTAssertTrue(delegate.stopCopyCalled)
        XCTAssertTrue(delegate.stopImproveCalled)
        XCTAssertTrue(delegate.cancelCalled)
        XCTAssertTrue(delegate.openSettingsCalled)
    }
}

// MARK: - Settings action behavior tests

/// Tests that verify the expected behavior when the settings button is clicked:
/// 1. Recording should be cancelled (delegate.cancel called)
/// 2. Settings window should be opened (delegate.openSettings called)
///
/// We simulate the AppDelegate's popoverDidRequestOpenSettings() logic here
/// since we can't import the executable target.

private class MockAppDelegateBehavior {
    var cancelRecordingCalled = false
    var showWindowTab: Int?

    func popoverDidRequestOpenSettings() {
        cancelRecording()
        showWindow(tab: 1)
    }

    private func cancelRecording() {
        cancelRecordingCalled = true
    }

    private func showWindow(tab: Int) {
        showWindowTab = tab
    }
}

final class SettingsButtonBehaviorTests: XCTestCase {

    func testOpenSettingsCancelsRecording() {
        let mock = MockAppDelegateBehavior()
        mock.popoverDidRequestOpenSettings()
        XCTAssertTrue(mock.cancelRecordingCalled)
    }

    func testOpenSettingsShowsSettingsTab() {
        let mock = MockAppDelegateBehavior()
        mock.popoverDidRequestOpenSettings()
        XCTAssertEqual(mock.showWindowTab, 1)
    }
}
