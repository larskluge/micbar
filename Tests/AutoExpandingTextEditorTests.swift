import XCTest
import SwiftUI

// MARK: - Duplicated from HistoryView.swift (can't import executable target)

private struct AutoExpandingTextEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 13))
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
        }
        .frame(minHeight: 32)
    }
}

final class AutoExpandingTextEditorTests: XCTestCase {

    func testShortTextProducesMinHeight() {
        // The hidden Text with a short string should still respect minHeight: 32
        let view = AutoExpandingTextEditor(text: .constant("Hello"))
        let hosted = NSHostingView(rootView: view)
        hosted.frame = NSRect(x: 0, y: 0, width: 400, height: 1000)
        hosted.layout()
        let fitting = hosted.fittingSize
        XCTAssertGreaterThanOrEqual(fitting.height, 32, "Should respect minHeight for short text")
    }

    func testLongTextExpandsBeyondMinHeight() {
        // Multi-line text should expand beyond 32pt
        let longText = String(repeating: "This is a long sentence for testing. ", count: 20)
        let view = AutoExpandingTextEditor(text: .constant(longText))
        let hosted = NSHostingView(rootView: view)
        hosted.frame = NSRect(x: 0, y: 0, width: 400, height: 2000)
        hosted.layout()
        let fitting = hosted.fittingSize
        XCTAssertGreaterThan(fitting.height, 50, "Long text should expand well beyond minHeight")
    }

    func testNoMaxHeightCap() {
        // Very long text should NOT be capped at 100pt (the old maxHeight)
        let veryLongText = String(repeating: "Line of text that keeps going. ", count: 80)
        let view = AutoExpandingTextEditor(text: .constant(veryLongText))
        let hosted = NSHostingView(rootView: view)
        hosted.frame = NSRect(x: 0, y: 0, width: 300, height: 3000)
        hosted.layout()
        let fitting = hosted.fittingSize
        XCTAssertGreaterThan(fitting.height, 100, "Should not be capped at old 100pt maxHeight")
    }

    func testEmptyTextUsesMinHeight() {
        let view = AutoExpandingTextEditor(text: .constant(""))
        let hosted = NSHostingView(rootView: view)
        hosted.frame = NSRect(x: 0, y: 0, width: 400, height: 1000)
        hosted.layout()
        let fitting = hosted.fittingSize
        XCTAssertGreaterThanOrEqual(fitting.height, 32, "Empty text should use minHeight")
    }
}
